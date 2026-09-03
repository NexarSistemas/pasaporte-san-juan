-- Amplía la edición atómica a preguntas pendientes y publicadas, preservando
-- el estado editorial existente.
create or replace function public.actualizar_pregunta_admin(
  p_pregunta_id uuid, p_categoria_id uuid, p_texto text, p_pista text,
  p_explicacion text, p_dificultad text, p_fuente text, p_url_fuente text,
  p_observaciones_revision text, p_respuesta_correcta_id uuid, p_respuesta_correcta text,
  p_respuesta_2_id uuid, p_respuesta_2 text, p_respuesta_3_id uuid,
  p_respuesta_3 text, p_respuesta_4_id uuid, p_respuesta_4 text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ids uuid[] := array[p_respuesta_correcta_id, p_respuesta_2_id, p_respuesta_3_id, p_respuesta_4_id];
  v_textos text[] := array[btrim(coalesce(p_respuesta_correcta, '')), btrim(coalesce(p_respuesta_2, '')), btrim(coalesce(p_respuesta_3, '')), btrim(coalesce(p_respuesta_4, ''))];
  v_estado text; v_total integer; v_ids_validos integer;
begin
  if (select auth.uid()) is null then raise exception 'Se requiere una sesión autenticada.' using errcode = '42501'; end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501'; end if;
  select estado_editorial into v_estado from public.preguntas where id = p_pregunta_id and estado_editorial in ('pendiente', 'publicada') for update;
  if not found then raise exception 'La pregunta no existe o no está disponible para edición.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.categorias where id = p_categoria_id) then raise exception 'La categoría indicada no existe.' using errcode = '23503'; end if;
  if btrim(coalesce(p_texto, '')) = '' then raise exception 'El texto de la pregunta no puede estar vacío.' using errcode = '22023'; end if;
  if coalesce(p_dificultad, '') not in ('facil', 'media', 'dificil') then raise exception 'La dificultad debe ser facil, media o dificil.' using errcode = '22023'; end if;
  if exists (select 1 from unnest(v_textos) as texto where texto = '') or (select count(distinct lower(regexp_replace(texto, '\\s+', ' ', 'g'))) from unnest(v_textos) as texto) <> 4 then raise exception 'Las cuatro respuestas deben tener contenido y ser diferentes entre sí.' using errcode = '22023'; end if;
  if (select count(distinct id) from unnest(v_ids) as id) <> 4 then raise exception 'Las respuestas a actualizar no son válidas.' using errcode = '22023'; end if;
  select count(*) into v_total from public.respuestas where pregunta_id = p_pregunta_id;
  select count(*) into v_ids_validos from public.respuestas where pregunta_id = p_pregunta_id and id = any(v_ids);
  if v_total <> 4 or v_ids_validos <> 4 then raise exception 'La pregunta debe conservar exactamente cuatro respuestas.' using errcode = 'P0001'; end if;
  update public.preguntas set categoria_id = p_categoria_id, texto = btrim(p_texto), pista = nullif(btrim(p_pista), ''), explicacion = coalesce(p_explicacion, ''), dificultad = p_dificultad, fuente = nullif(btrim(p_fuente), ''), url_fuente = nullif(btrim(p_url_fuente), ''), observaciones_revision = nullif(btrim(p_observaciones_revision), '') where id = p_pregunta_id;
  update public.respuestas set texto = format('__revision_tmp_%s_%s', p_pregunta_id, id) where pregunta_id = p_pregunta_id;
  update public.respuestas set texto = case id when p_respuesta_correcta_id then v_textos[1] when p_respuesta_2_id then v_textos[2] when p_respuesta_3_id then v_textos[3] when p_respuesta_4_id then v_textos[4] end, es_correcta = id = p_respuesta_correcta_id where pregunta_id = p_pregunta_id;
  return jsonb_build_object('ok', true, 'pregunta_id', p_pregunta_id, 'estado_editorial', v_estado, 'mensaje', 'Pregunta actualizada.');
end;
$$;

revoke all on function public.actualizar_pregunta_admin(uuid, uuid, text, text, text, text, text, text, text, uuid, text, uuid, text, uuid, text, uuid, text) from public, anon;
grant execute on function public.actualizar_pregunta_admin(uuid, uuid, text, text, text, text, text, text, text, uuid, text, uuid, text, uuid, text, uuid, text) to authenticated;
