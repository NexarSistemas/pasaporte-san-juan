-- Centraliza el flujo editorial: el panel no actualiza estado_editorial
-- directamente y todas las transiciones pasan por esta RPC administrativa.
create or replace function public.cambiar_estado_editorial_pregunta_admin(
  p_pregunta_id uuid,
  p_estado_destino text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_estado_actual text;
  v_cantidad_respuestas integer;
  v_correctas integer;
  v_distintas integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Se requiere una sesión autenticada.' using errcode = '42501';
  end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then
    raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501';
  end if;

  select estado_editorial into v_estado_actual
  from public.preguntas
  where id = p_pregunta_id
  for update;
  if not found then
    raise exception 'La pregunta no existe.' using errcode = 'P0001';
  end if;

  if not (
    (v_estado_actual = 'pendiente' and p_estado_destino in ('en_revision', 'rechazada'))
    or (v_estado_actual = 'en_revision' and p_estado_destino in ('revisada', 'rechazada'))
    or (v_estado_actual = 'revisada' and p_estado_destino in ('publicada', 'en_revision', 'rechazada'))
    or (v_estado_actual = 'publicada' and p_estado_destino = 'en_revision')
    or (v_estado_actual = 'rechazada' and p_estado_destino = 'en_revision')
  ) then
    raise exception 'La transición editorial de % a % no está permitida.', v_estado_actual, coalesce(p_estado_destino, 'NULL') using errcode = '22023';
  end if;

  if p_estado_destino = 'publicada' then
    select
      count(*),
      count(*) filter (where es_correcta),
      count(distinct lower(regexp_replace(btrim(texto), '[[:space:]]+', ' ', 'g')))
    into v_cantidad_respuestas, v_correctas, v_distintas
    from public.respuestas
    where pregunta_id = p_pregunta_id
      and btrim(texto) <> '';

    if v_cantidad_respuestas <> 4 or v_correctas <> 1 or v_distintas <> 4 then
      raise exception 'La pregunta no es válida para publicar: debe tener cuatro respuestas diferentes y una sola correcta.' using errcode = '22023';
    end if;
  end if;

  update public.preguntas
  set estado_editorial = p_estado_destino,
      revisado_at = case when p_estado_destino = 'revisada' then now() else revisado_at end,
      publicado_at = case when p_estado_destino = 'publicada' then now() else publicado_at end
  where id = p_pregunta_id;

  return jsonb_build_object(
    'ok', true,
    'pregunta_id', p_pregunta_id,
    'estado_anterior', v_estado_actual,
    'estado_editorial', p_estado_destino,
    'mensaje', format('Estado editorial actualizado a %s.', p_estado_destino)
  );
end;
$$;

-- Reemplaza las RPC de edición para incluir todos los estados reabribles;
-- rechazada queda excluida hasta que se la mueva nuevamente a en_revision.
create or replace function public.actualizar_pregunta_admin(
  p_pregunta_id uuid, p_categoria_id uuid, p_texto text, p_pista text,
  p_explicacion text, p_dificultad text, p_fuente text, p_url_fuente text,
  p_observaciones_revision text, p_respuesta_correcta_id uuid, p_respuesta_correcta text,
  p_respuesta_2_id uuid, p_respuesta_2 text, p_respuesta_3_id uuid,
  p_respuesta_3 text, p_respuesta_4_id uuid, p_respuesta_4 text, p_concepto_id uuid
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ids uuid[] := array[p_respuesta_correcta_id, p_respuesta_2_id, p_respuesta_3_id, p_respuesta_4_id];
  v_textos text[] := array[btrim(coalesce(p_respuesta_correcta, '')), btrim(coalesce(p_respuesta_2, '')), btrim(coalesce(p_respuesta_3, '')), btrim(coalesce(p_respuesta_4, ''))];
  v_estado text; v_total integer; v_ids_validos integer;
begin
  if (select auth.uid()) is null then raise exception 'Se requiere una sesión autenticada.' using errcode = '42501'; end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501'; end if;
  select estado_editorial into v_estado from public.preguntas where id = p_pregunta_id and estado_editorial in ('pendiente', 'en_revision', 'revisada', 'publicada') for update;
  if not found then raise exception 'La pregunta no existe o debe reabrirse antes de editarse.' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.categorias where id = p_categoria_id) then raise exception 'La categoría indicada no existe.' using errcode = '23503'; end if;
  if btrim(coalesce(p_texto, '')) = '' then raise exception 'El texto de la pregunta no puede estar vacío.' using errcode = '22023'; end if;
  if coalesce(p_dificultad, '') not in ('facil', 'media', 'dificil') then raise exception 'La dificultad debe ser facil, media o dificil.' using errcode = '22023'; end if;
  if exists (select 1 from unnest(v_textos) as texto where texto = '') or (select count(distinct lower(regexp_replace(texto, '[[:space:]]+', ' ', 'g'))) from unnest(v_textos) as texto) <> 4 then raise exception 'Las cuatro respuestas deben tener contenido y ser diferentes entre sí.' using errcode = '22023'; end if;
  if (select count(distinct id) from unnest(v_ids) as id) <> 4 then raise exception 'Las respuestas a actualizar no son válidas.' using errcode = '22023'; end if;
  select count(*) into v_total from public.respuestas where pregunta_id = p_pregunta_id;
  select count(*) into v_ids_validos from public.respuestas where pregunta_id = p_pregunta_id and id = any(v_ids);
  if v_total <> 4 or v_ids_validos <> 4 then raise exception 'La pregunta debe conservar exactamente cuatro respuestas.' using errcode = 'P0001'; end if;
  update public.preguntas set categoria_id = p_categoria_id, texto = btrim(p_texto), pista = nullif(btrim(p_pista), ''), explicacion = coalesce(p_explicacion, ''), dificultad = p_dificultad, fuente = nullif(btrim(p_fuente), ''), url_fuente = nullif(btrim(p_url_fuente), ''), observaciones_revision = nullif(btrim(p_observaciones_revision), ''), concepto_id = p_concepto_id where id = p_pregunta_id;
  update public.respuestas set texto = format('__revision_tmp_%s_%s', p_pregunta_id, id) where pregunta_id = p_pregunta_id;
  update public.respuestas set texto = case id when p_respuesta_correcta_id then v_textos[1] when p_respuesta_2_id then v_textos[2] when p_respuesta_3_id then v_textos[3] when p_respuesta_4_id then v_textos[4] end, es_correcta = id = p_respuesta_correcta_id where pregunta_id = p_pregunta_id;
  return jsonb_build_object('ok', true, 'pregunta_id', p_pregunta_id, 'concepto_id', p_concepto_id, 'estado_editorial', v_estado, 'mensaje', 'Pregunta actualizada.');
end;
$$;

create or replace function public.asignar_concepto_pregunta_admin(p_pregunta_id uuid, p_concepto_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_estado text;
begin
  if (select auth.uid()) is null then raise exception 'Se requiere una sesión autenticada.' using errcode = '42501'; end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501'; end if;
  select estado_editorial into v_estado from public.preguntas where id = p_pregunta_id and estado_editorial in ('pendiente', 'en_revision', 'revisada', 'publicada') for update;
  if not found then raise exception 'La pregunta no existe o debe reabrirse antes de editarse.' using errcode = 'P0001'; end if;
  update public.preguntas set concepto_id = p_concepto_id where id = p_pregunta_id;
  return jsonb_build_object('ok', true, 'pregunta_id', p_pregunta_id, 'concepto_id', p_concepto_id, 'estado_editorial', v_estado, 'mensaje', case when p_concepto_id is null then 'Concepto quitado.' else 'Concepto asignado.' end);
end;
$$;

create or replace function public.agrupar_preguntas_por_concepto_admin(p_pregunta_id uuid, p_candidata_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_concepto_pregunta uuid; v_concepto_candidata uuid; v_concepto_compartido uuid; v_primera_id uuid; v_segunda_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Se requiere una sesión autenticada.' using errcode = '42501'; end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501'; end if;
  if p_pregunta_id is null or p_candidata_id is null or p_pregunta_id = p_candidata_id then raise exception 'Se deben indicar dos preguntas diferentes.' using errcode = '22023'; end if;
  v_primera_id := least(p_pregunta_id, p_candidata_id); v_segunda_id := greatest(p_pregunta_id, p_candidata_id);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('agrupar-concepto:' || v_primera_id::text || ':' || v_segunda_id::text, 0));
  select concepto_id into v_concepto_pregunta from public.preguntas where id = p_pregunta_id and estado_editorial in ('pendiente', 'en_revision', 'revisada', 'publicada') for update;
  if not found then raise exception 'La pregunta seleccionada no existe o debe reabrirse antes de editarse.' using errcode = 'P0001'; end if;
  select concepto_id into v_concepto_candidata from public.preguntas where id = p_candidata_id and estado_editorial in ('pendiente', 'en_revision', 'revisada', 'publicada') for update;
  if not found then raise exception 'La pregunta candidata no existe o debe reabrirse antes de editarse.' using errcode = 'P0001'; end if;
  if v_concepto_pregunta is not null and v_concepto_candidata is not null and v_concepto_pregunta <> v_concepto_candidata then raise exception 'Las preguntas ya pertenecen a conceptos distintos; revisá la decisión antes de modificarlas.' using errcode = '22023'; end if;
  v_concepto_compartido := coalesce(v_concepto_pregunta, v_concepto_candidata, pg_catalog.gen_random_uuid());
  update public.preguntas set concepto_id = v_concepto_compartido where id in (p_pregunta_id, p_candidata_id);
  return jsonb_build_object('ok', true, 'pregunta_id', p_pregunta_id, 'candidata_id', p_candidata_id, 'concepto_id', v_concepto_compartido, 'mensaje', 'Preguntas agrupadas bajo el mismo concepto.');
end;
$$;

-- La RPC anterior permitía saltar el flujo pendiente -> publicada. Se conserva
-- por compatibilidad de esquema, pero deja de estar disponible para el panel.
revoke all on function public.publicar_pregunta_pendiente_admin(uuid) from public, anon, authenticated;
revoke all on function public.actualizar_pregunta_pendiente_admin(uuid, text, text, text, text, text, text, text, uuid, text, uuid, text, uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function public.cambiar_estado_editorial_pregunta_admin(uuid, text) from public, anon;
grant execute on function public.cambiar_estado_editorial_pregunta_admin(uuid, text) to authenticated;
