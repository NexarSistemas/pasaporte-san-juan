-- Importa una pregunta editorial completa desde el administrador. Cada llamada
-- es una transacción: cualquier excepción revierte tanto la pregunta como sus
-- respuestas.
create or replace function public.importar_pregunta_admin(
  p_codigo_origen text,
  p_categoria_id uuid,
  p_texto text,
  p_pista text,
  p_explicacion text,
  p_dificultad text,
  p_fuente text,
  p_url_fuente text,
  p_respuesta_correcta text,
  p_respuesta_2 text,
  p_respuesta_3 text,
  p_respuesta_4 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pregunta_id uuid;
  v_codigo_origen text := nullif(btrim(p_codigo_origen), '');
  v_texto text := btrim(coalesce(p_texto, ''));
  v_texto_normalizado text;
  v_respuestas text[];
  v_respuestas_normalizadas text[];
  v_lock_codigo bigint;
  v_lock_texto bigint;
begin
  if (select auth.uid()) is null then
    raise exception 'Se requiere una sesión autenticada.' using errcode = '42501';
  end if;

  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then
    raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501';
  end if;

  if p_categoria_id is null or not exists (
    select 1 from public.categorias where id = p_categoria_id
  ) then
    raise exception 'La categoría indicada no existe.' using errcode = '23503';
  end if;

  if v_texto = '' then
    raise exception 'El texto de la pregunta no puede estar vacío.' using errcode = '22023';
  end if;

  if coalesce(p_dificultad, '') not in ('facil', 'media', 'dificil') then
    raise exception 'La dificultad debe ser facil, media o dificil.' using errcode = '22023';
  end if;

  v_respuestas := array[
    btrim(coalesce(p_respuesta_correcta, '')),
    btrim(coalesce(p_respuesta_2, '')),
    btrim(coalesce(p_respuesta_3, '')),
    btrim(coalesce(p_respuesta_4, ''))
  ];
  if exists (select 1 from unnest(v_respuestas) as respuesta where respuesta = '') then
    raise exception 'Las cuatro respuestas deben tener contenido.' using errcode = '22023';
  end if;

  v_respuestas_normalizadas := array(
    select lower(regexp_replace(respuesta, '\\s+', ' ', 'g'))
    from unnest(v_respuestas) as respuesta
  );
  if (select count(distinct respuesta) from unnest(v_respuestas_normalizadas) as respuesta) <> 4 then
    raise exception 'Las cuatro respuestas deben ser diferentes entre sí.' using errcode = '22023';
  end if;

  v_texto_normalizado := lower(regexp_replace(v_texto, '\\s+', ' ', 'g'));
  v_lock_texto := hashtextextended('texto:' || v_texto_normalizado, 0);
  if v_codigo_origen is not null then
    v_lock_codigo := hashtextextended('codigo:' || v_codigo_origen, 0);
    if v_lock_codigo <= v_lock_texto then
      perform pg_catalog.pg_advisory_xact_lock(v_lock_codigo);
      perform pg_catalog.pg_advisory_xact_lock(v_lock_texto);
    else
      perform pg_catalog.pg_advisory_xact_lock(v_lock_texto);
      perform pg_catalog.pg_advisory_xact_lock(v_lock_codigo);
    end if;
  else
    perform pg_catalog.pg_advisory_xact_lock(v_lock_texto);
  end if;

  if v_codigo_origen is not null and exists (
    select 1 from public.preguntas where codigo_origen = v_codigo_origen
  ) then
    raise exception 'Ya existe una pregunta con el codigo_origen indicado.' using errcode = '23505';
  end if;

  if exists (
    select 1
    from public.preguntas
    where lower(regexp_replace(btrim(texto), '\\s+', ' ', 'g')) = v_texto_normalizado
  ) then
    raise exception 'Ya existe una pregunta con el mismo texto.' using errcode = '23505';
  end if;

  insert into public.preguntas (
    codigo_origen, categoria_id, texto, texto_original, pista, explicacion,
    dificultad, fuente, url_fuente, activo, estado_editorial, revisado_at, publicado_at
  ) values (
    v_codigo_origen, p_categoria_id, v_texto, v_texto, nullif(btrim(p_pista), ''),
    coalesce(p_explicacion, ''), p_dificultad, nullif(btrim(p_fuente), ''),
    nullif(btrim(p_url_fuente), ''), true, 'pendiente', null, null
  ) returning id into v_pregunta_id;

  insert into public.respuestas (pregunta_id, texto, es_correcta)
  values
    (v_pregunta_id, v_respuestas[1], true),
    (v_pregunta_id, v_respuestas[2], false),
    (v_pregunta_id, v_respuestas[3], false),
    (v_pregunta_id, v_respuestas[4], false);

  return jsonb_build_object(
    'ok', true,
    'pregunta_id', v_pregunta_id,
    'codigo_origen', v_codigo_origen,
    'mensaje', 'Pregunta importada como pendiente.'
  );
end;
$$;

revoke all on function public.importar_pregunta_admin(text, uuid, text, text, text, text, text, text, text, text, text, text) from public;
revoke all on function public.importar_pregunta_admin(text, uuid, text, text, text, text, text, text, text, text, text, text) from anon;
grant execute on function public.importar_pregunta_admin(text, uuid, text, text, text, text, text, text, text, text, text, text) to authenticated;
