-- La revisión semántica es editorial: no modifica la selección de partidas ni
-- vuelve obligatorio que una pregunta tenga concepto_id.
grant select (concepto_id) on public.preguntas to authenticated;

create or replace function public.asignar_concepto_pregunta_admin(
  p_pregunta_id uuid,
  p_concepto_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_estado text;
begin
  if (select auth.uid()) is null then
    raise exception 'Se requiere una sesión autenticada.' using errcode = '42501';
  end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then
    raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501';
  end if;

  select estado_editorial into v_estado
  from public.preguntas
  where id = p_pregunta_id and estado_editorial in ('pendiente', 'publicada')
  for update;
  if not found then
    raise exception 'La pregunta no existe o no está disponible para edición.' using errcode = 'P0001';
  end if;

  update public.preguntas
  set concepto_id = p_concepto_id
  where id = p_pregunta_id;

  return jsonb_build_object(
    'ok', true,
    'pregunta_id', p_pregunta_id,
    'concepto_id', p_concepto_id,
    'estado_editorial', v_estado,
    'mensaje', case when p_concepto_id is null then 'Concepto quitado.' else 'Concepto asignado.' end
  );
end;
$$;

create or replace function public.agrupar_preguntas_por_concepto_admin(
  p_pregunta_id uuid,
  p_candidata_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_concepto_pregunta uuid;
  v_concepto_candidata uuid;
  v_concepto_compartido uuid;
  v_primera_id uuid;
  v_segunda_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Se requiere una sesión autenticada.' using errcode = '42501';
  end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then
    raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501';
  end if;
  if p_pregunta_id is null or p_candidata_id is null or p_pregunta_id = p_candidata_id then
    raise exception 'Se deben indicar dos preguntas diferentes.' using errcode = '22023';
  end if;

  v_primera_id := least(p_pregunta_id, p_candidata_id);
  v_segunda_id := greatest(p_pregunta_id, p_candidata_id);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('agrupar-concepto:' || v_primera_id::text || ':' || v_segunda_id::text, 0)
  );

  select concepto_id into v_concepto_pregunta
  from public.preguntas
  where id = p_pregunta_id and estado_editorial in ('pendiente', 'publicada')
  for update;
  if not found then
    raise exception 'La pregunta seleccionada no existe o no está disponible para edición.' using errcode = 'P0001';
  end if;
  select concepto_id into v_concepto_candidata
  from public.preguntas
  where id = p_candidata_id and estado_editorial in ('pendiente', 'publicada')
  for update;
  if not found then
    raise exception 'La pregunta candidata no existe o no está disponible para edición.' using errcode = 'P0001';
  end if;

  if v_concepto_pregunta is not null and v_concepto_candidata is not null
     and v_concepto_pregunta <> v_concepto_candidata then
    raise exception 'Las preguntas ya pertenecen a conceptos distintos; revisá la decisión antes de modificarlas.' using errcode = '22023';
  end if;

  v_concepto_compartido := coalesce(v_concepto_pregunta, v_concepto_candidata, pg_catalog.gen_random_uuid());
  update public.preguntas
  set concepto_id = v_concepto_compartido
  where id in (p_pregunta_id, p_candidata_id);

  return jsonb_build_object(
    'ok', true,
    'pregunta_id', p_pregunta_id,
    'candidata_id', p_candidata_id,
    'concepto_id', v_concepto_compartido,
    'mensaje', 'Preguntas agrupadas bajo el mismo concepto.'
  );
end;
$$;

revoke all on function public.asignar_concepto_pregunta_admin(uuid, uuid) from public, anon;
grant execute on function public.asignar_concepto_pregunta_admin(uuid, uuid) to authenticated;
revoke all on function public.agrupar_preguntas_por_concepto_admin(uuid, uuid) from public, anon;
grant execute on function public.agrupar_preguntas_por_concepto_admin(uuid, uuid) to authenticated;
