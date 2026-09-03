-- La revisión conserva las cuatro respuestas existentes y actualiza la
-- pregunta de forma atómica. Sólo un administrador autenticado puede editar
-- o publicar contenido pendiente.
create or replace function public.actualizar_pregunta_pendiente_admin(
  p_pregunta_id uuid, p_texto text, p_pista text, p_explicacion text,
  p_dificultad text, p_fuente text, p_url_fuente text, p_observaciones_revision text,
  p_respuesta_correcta_id uuid, p_respuesta_correcta text,
  p_respuesta_2_id uuid, p_respuesta_2 text, p_respuesta_3_id uuid,
  p_respuesta_3 text, p_respuesta_4_id uuid, p_respuesta_4 text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_respuesta_ids uuid[] := array[p_respuesta_correcta_id, p_respuesta_2_id, p_respuesta_3_id, p_respuesta_4_id];
  v_respuestas text[] := array[btrim(coalesce(p_respuesta_correcta, '')), btrim(coalesce(p_respuesta_2, '')), btrim(coalesce(p_respuesta_3, '')), btrim(coalesce(p_respuesta_4, ''))];
  v_respuestas_normalizadas text[];
  v_cantidad_respuestas integer;
  v_ids_de_pregunta integer;
begin
  if (select auth.uid()) is null then raise exception 'Se requiere una sesión autenticada.' using errcode = '42501'; end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501'; end if;

  perform 1 from public.preguntas where id = p_pregunta_id and estado_editorial = 'pendiente' for update;
  if not found then raise exception 'La pregunta no existe o ya no está pendiente.' using errcode = 'P0001'; end if;
  if btrim(coalesce(p_texto, '')) = '' then raise exception 'El texto de la pregunta no puede estar vacío.' using errcode = '22023'; end if;
  if coalesce(p_dificultad, '') not in ('facil', 'media', 'dificil') then raise exception 'La dificultad debe ser facil, media o dificil.' using errcode = '22023'; end if;
  if exists (select 1 from unnest(v_respuestas) as respuesta where respuesta = '') then raise exception 'Las cuatro respuestas deben tener contenido.' using errcode = '22023'; end if;
  if (select count(distinct respuesta) from unnest(v_respuesta_ids) as respuesta) <> 4 then raise exception 'Las respuestas a actualizar no son válidas.' using errcode = '22023'; end if;
  v_respuestas_normalizadas := array(select lower(regexp_replace(respuesta, '\\s+', ' ', 'g')) from unnest(v_respuestas) as respuesta);
  if (select count(distinct respuesta) from unnest(v_respuestas_normalizadas) as respuesta) <> 4 then raise exception 'Las cuatro respuestas deben ser diferentes entre sí.' using errcode = '22023'; end if;

  select count(*) into v_cantidad_respuestas from public.respuestas where pregunta_id = p_pregunta_id;
  select count(*) into v_ids_de_pregunta from public.respuestas where pregunta_id = p_pregunta_id and id = any(v_respuesta_ids);
  if v_cantidad_respuestas <> 4 or v_ids_de_pregunta <> 4 then raise exception 'La pregunta debe conservar exactamente cuatro respuestas.' using errcode = 'P0001'; end if;

  update public.preguntas
  set texto = btrim(p_texto), pista = nullif(btrim(p_pista), ''), explicacion = coalesce(p_explicacion, ''), dificultad = p_dificultad,
      fuente = nullif(btrim(p_fuente), ''), url_fuente = nullif(btrim(p_url_fuente), ''), observaciones_revision = nullif(btrim(p_observaciones_revision), '')
  where id = p_pregunta_id;

  -- Evita colisiones transitorias con la restricción única al intercambiar textos.
  update public.respuestas set texto = format('__revision_tmp_%s_%s', p_pregunta_id, id) where pregunta_id = p_pregunta_id;
  update public.respuestas
  set texto = case id when p_respuesta_correcta_id then v_respuestas[1] when p_respuesta_2_id then v_respuestas[2] when p_respuesta_3_id then v_respuestas[3] when p_respuesta_4_id then v_respuestas[4] end,
      es_correcta = id = p_respuesta_correcta_id
  where pregunta_id = p_pregunta_id;

  return jsonb_build_object('ok', true, 'pregunta_id', p_pregunta_id, 'mensaje', 'Pregunta pendiente actualizada.');
end;
$$;

create or replace function public.publicar_pregunta_pendiente_admin(p_pregunta_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_cantidad_respuestas integer; v_correctas integer; v_distintas integer;
begin
  if (select auth.uid()) is null then raise exception 'Se requiere una sesión autenticada.' using errcode = '42501'; end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501'; end if;
  perform 1 from public.preguntas where id = p_pregunta_id and estado_editorial = 'pendiente' for update;
  if not found then raise exception 'La pregunta no existe o ya no está pendiente.' using errcode = 'P0001'; end if;
  select count(*), count(*) filter (where es_correcta), count(distinct lower(regexp_replace(btrim(texto), '\\s+', ' ', 'g')))
  into v_cantidad_respuestas, v_correctas, v_distintas from public.respuestas where pregunta_id = p_pregunta_id and btrim(texto) <> '';
  if v_cantidad_respuestas <> 4 or v_correctas <> 1 or v_distintas <> 4 then raise exception 'La pregunta no es válida para publicar: debe tener cuatro respuestas diferentes y una sola correcta.' using errcode = '22023'; end if;
  update public.preguntas set estado_editorial = 'publicada' where id = p_pregunta_id;
  return jsonb_build_object('ok', true, 'pregunta_id', p_pregunta_id, 'mensaje', 'Pregunta publicada.');
end;
$$;

revoke all on function public.actualizar_pregunta_pendiente_admin(uuid, text, text, text, text, text, text, text, uuid, text, uuid, text, uuid, text, uuid, text) from public, anon;
grant execute on function public.actualizar_pregunta_pendiente_admin(uuid, text, text, text, text, text, text, text, uuid, text, uuid, text, uuid, text, uuid, text) to authenticated;
revoke all on function public.publicar_pregunta_pendiente_admin(uuid) from public, anon;
grant execute on function public.publicar_pregunta_pendiente_admin(uuid) to authenticated;
