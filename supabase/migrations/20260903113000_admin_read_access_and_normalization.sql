-- Habilita exclusivamente las lecturas que necesita el portal estático de
-- administración. Las tablas continúan inaccesibles para anon y para cuentas
-- autenticadas que no tengan el rol administrativo.
grant select (id, nombre) on public.categorias to authenticated;
grant select (
  id, codigo_origen, categoria_id, texto, texto_original, pista, explicacion,
  dificultad, fuente, url_fuente, observaciones_revision, estado_editorial, created_at
) on public.preguntas to authenticated;
grant select (id, pregunta_id, texto, es_correcta) on public.respuestas to authenticated;

create policy "admin_read_categorias" on public.categorias
  for select to authenticated
  using (coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'admin');

create policy "admin_read_preguntas" on public.preguntas
  for select to authenticated
  using (coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'admin');

create policy "admin_read_respuestas" on public.respuestas
  for select to authenticated
  using (coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'admin');

-- Reemplaza las definiciones administrativas para que la normalización de
-- espacios sea inequívoca en PostgreSQL. No se eliminan las RPC anteriores.
create or replace function public.importar_pregunta_admin(
  p_codigo_origen text, p_categoria_id uuid, p_texto text, p_pista text,
  p_explicacion text, p_dificultad text, p_fuente text, p_url_fuente text,
  p_respuesta_correcta text, p_respuesta_2 text, p_respuesta_3 text, p_respuesta_4 text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
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
  if (select auth.uid()) is null then raise exception 'Se requiere una sesión autenticada.' using errcode = '42501'; end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501'; end if;
  if p_categoria_id is null or not exists (select 1 from public.categorias where id = p_categoria_id) then raise exception 'La categoría indicada no existe.' using errcode = '23503'; end if;
  if v_texto = '' then raise exception 'El texto de la pregunta no puede estar vacío.' using errcode = '22023'; end if;
  if coalesce(p_dificultad, '') not in ('facil', 'media', 'dificil') then raise exception 'La dificultad debe ser facil, media o dificil.' using errcode = '22023'; end if;
  v_respuestas := array[btrim(coalesce(p_respuesta_correcta, '')), btrim(coalesce(p_respuesta_2, '')), btrim(coalesce(p_respuesta_3, '')), btrim(coalesce(p_respuesta_4, ''))];
  if exists (select 1 from unnest(v_respuestas) as respuesta where respuesta = '') then raise exception 'Las cuatro respuestas deben tener contenido.' using errcode = '22023'; end if;
  v_respuestas_normalizadas := array(select lower(regexp_replace(respuesta, '[[:space:]]+', ' ', 'g')) from unnest(v_respuestas) as respuesta);
  if (select count(distinct respuesta) from unnest(v_respuestas_normalizadas) as respuesta) <> 4 then raise exception 'Las cuatro respuestas deben ser diferentes entre sí.' using errcode = '22023'; end if;
  v_texto_normalizado := lower(regexp_replace(v_texto, '[[:space:]]+', ' ', 'g'));
  v_lock_texto := hashtextextended('texto:' || v_texto_normalizado, 0);
  if v_codigo_origen is not null then
    v_lock_codigo := hashtextextended('codigo:' || v_codigo_origen, 0);
    if v_lock_codigo <= v_lock_texto then perform pg_catalog.pg_advisory_xact_lock(v_lock_codigo); perform pg_catalog.pg_advisory_xact_lock(v_lock_texto); else perform pg_catalog.pg_advisory_xact_lock(v_lock_texto); perform pg_catalog.pg_advisory_xact_lock(v_lock_codigo); end if;
  else
    perform pg_catalog.pg_advisory_xact_lock(v_lock_texto);
  end if;
  if v_codigo_origen is not null and exists (select 1 from public.preguntas where codigo_origen = v_codigo_origen) then raise exception 'Ya existe una pregunta con el codigo_origen indicado.' using errcode = '23505'; end if;
  if exists (select 1 from public.preguntas where lower(regexp_replace(btrim(texto), '[[:space:]]+', ' ', 'g')) = v_texto_normalizado) then raise exception 'Ya existe una pregunta con el mismo texto.' using errcode = '23505'; end if;
  insert into public.preguntas (codigo_origen, categoria_id, texto, texto_original, pista, explicacion, dificultad, fuente, url_fuente, activo, estado_editorial, revisado_at, publicado_at)
  values (v_codigo_origen, p_categoria_id, v_texto, v_texto, nullif(btrim(p_pista), ''), coalesce(p_explicacion, ''), p_dificultad, nullif(btrim(p_fuente), ''), nullif(btrim(p_url_fuente), ''), true, 'pendiente', null, null)
  returning id into v_pregunta_id;
  insert into public.respuestas (pregunta_id, texto, es_correcta) values (v_pregunta_id, v_respuestas[1], true), (v_pregunta_id, v_respuestas[2], false), (v_pregunta_id, v_respuestas[3], false), (v_pregunta_id, v_respuestas[4], false);
  return jsonb_build_object('ok', true, 'pregunta_id', v_pregunta_id, 'codigo_origen', v_codigo_origen, 'mensaje', 'Pregunta importada como pendiente.');
end;
$$;

create or replace function public.actualizar_pregunta_pendiente_admin(
  p_pregunta_id uuid, p_texto text, p_pista text, p_explicacion text,
  p_dificultad text, p_fuente text, p_url_fuente text, p_observaciones_revision text,
  p_respuesta_correcta_id uuid, p_respuesta_correcta text, p_respuesta_2_id uuid,
  p_respuesta_2 text, p_respuesta_3_id uuid, p_respuesta_3 text,
  p_respuesta_4_id uuid, p_respuesta_4 text
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
  v_respuestas_normalizadas := array(select lower(regexp_replace(respuesta, '[[:space:]]+', ' ', 'g')) from unnest(v_respuestas) as respuesta);
  if (select count(distinct respuesta) from unnest(v_respuestas_normalizadas) as respuesta) <> 4 then raise exception 'Las cuatro respuestas deben ser diferentes entre sí.' using errcode = '22023'; end if;
  select count(*) into v_cantidad_respuestas from public.respuestas where pregunta_id = p_pregunta_id;
  select count(*) into v_ids_de_pregunta from public.respuestas where pregunta_id = p_pregunta_id and id = any(v_respuesta_ids);
  if v_cantidad_respuestas <> 4 or v_ids_de_pregunta <> 4 then raise exception 'La pregunta debe conservar exactamente cuatro respuestas.' using errcode = 'P0001'; end if;
  update public.preguntas set texto = btrim(p_texto), pista = nullif(btrim(p_pista), ''), explicacion = coalesce(p_explicacion, ''), dificultad = p_dificultad, fuente = nullif(btrim(p_fuente), ''), url_fuente = nullif(btrim(p_url_fuente), ''), observaciones_revision = nullif(btrim(p_observaciones_revision), '') where id = p_pregunta_id;
  update public.respuestas set texto = format('__revision_tmp_%s_%s', p_pregunta_id, id) where pregunta_id = p_pregunta_id;
  update public.respuestas set texto = case id when p_respuesta_correcta_id then v_respuestas[1] when p_respuesta_2_id then v_respuestas[2] when p_respuesta_3_id then v_respuestas[3] when p_respuesta_4_id then v_respuestas[4] end, es_correcta = id = p_respuesta_correcta_id where pregunta_id = p_pregunta_id;
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
  select count(*), count(*) filter (where es_correcta), count(distinct lower(regexp_replace(btrim(texto), '[[:space:]]+', ' ', 'g')))
  into v_cantidad_respuestas, v_correctas, v_distintas from public.respuestas where pregunta_id = p_pregunta_id and btrim(texto) <> '';
  if v_cantidad_respuestas <> 4 or v_correctas <> 1 or v_distintas <> 4 then raise exception 'La pregunta no es válida para publicar: debe tener cuatro respuestas diferentes y una sola correcta.' using errcode = '22023'; end if;
  update public.preguntas set estado_editorial = 'publicada' where id = p_pregunta_id;
  return jsonb_build_object('ok', true, 'pregunta_id', p_pregunta_id, 'mensaje', 'Pregunta publicada.');
end;
$$;

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
  if exists (select 1 from unnest(v_textos) as texto where texto = '') or (select count(distinct lower(regexp_replace(texto, '[[:space:]]+', ' ', 'g'))) from unnest(v_textos) as texto) <> 4 then raise exception 'Las cuatro respuestas deben tener contenido y ser diferentes entre sí.' using errcode = '22023'; end if;
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
