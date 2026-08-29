-- Pasaporte San Juan v0.3.0
-- El cliente anon solo ejecuta las RPC al final de este archivo. No recibe
-- permisos directos sobre las tablas ni sobre las respuestas correctas.

create table public.categorias (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  slug text not null unique check (slug ~ '^[a-z0-9-]+$'),
  descripcion text,
  icono text,
  activo boolean not null default true,
  orden smallint not null default 0 check (orden >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.preguntas (
  id uuid primary key default gen_random_uuid(),
  codigo_origen text unique,
  categoria_id uuid not null references public.categorias(id) on delete restrict,
  texto text not null check (length(trim(texto)) > 0),
  pista text,
  explicacion text not null,
  imagen text,
  imagen_alt text,
  fuente text,
  url_fuente text,
  fecha_revision date,
  activo boolean not null default true,
  dificultad text not null default 'media' check (dificultad in ('facil', 'media', 'dificil')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.respuestas (
  id uuid primary key default gen_random_uuid(),
  pregunta_id uuid not null references public.preguntas(id) on delete cascade,
  texto text not null check (length(trim(texto)) > 0),
  es_correcta boolean not null default false,
  created_at timestamptz not null default now(),
  unique (pregunta_id, texto)
);

create unique index respuestas_una_correcta_por_pregunta_idx
  on public.respuestas (pregunta_id) where es_correcta;

create table public.jugadores (
  id uuid primary key default gen_random_uuid(),
  player_token uuid not null unique,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table public.partidas (
  id uuid primary key default gen_random_uuid(),
  jugador_id uuid not null references public.jugadores(id) on delete cascade,
  numero_partida integer not null check (numero_partida > 0),
  ciclo integer not null check (ciclo > 0),
  puntaje integer not null default 0 check (puntaje >= 0),
  aciertos smallint not null default 0 check (aciertos >= 0),
  racha_maxima smallint not null default 0 check (racha_maxima >= 0),
  estado text not null default 'en_curso' check (estado in ('en_curso', 'finalizada')),
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  unique (jugador_id, numero_partida),
  check ((estado = 'en_curso' and finished_at is null) or (estado = 'finalizada' and finished_at is not null))
);

create table public.partida_preguntas (
  id uuid primary key default gen_random_uuid(),
  partida_id uuid not null references public.partidas(id) on delete cascade,
  pregunta_id uuid not null references public.preguntas(id) on delete restrict,
  orden smallint not null check (orden > 0),
  respuesta_id uuid references public.respuestas(id) on delete restrict,
  fue_correcta boolean,
  created_at timestamptz not null default now(),
  respondida_at timestamptz,
  unique (partida_id, pregunta_id),
  unique (partida_id, orden),
  check ((respondida_at is null and respuesta_id is null and fue_correcta is null)
      or (respondida_at is not null and respuesta_id is not null and fue_correcta is not null))
);

create index preguntas_activas_categoria_idx on public.preguntas (categoria_id, id) where activo;
create index respuestas_pregunta_idx on public.respuestas (pregunta_id, id);
create index partidas_jugador_ciclo_idx on public.partidas (jugador_id, ciclo, created_at desc);
create index partida_preguntas_pregunta_historial_idx on public.partida_preguntas (pregunta_id, partida_id);
create index partida_preguntas_partida_orden_idx on public.partida_preguntas (partida_id, orden);
create index partida_preguntas_respuesta_idx on public.partida_preguntas (respuesta_id);

create or replace function public.actualizar_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger categorias_updated_at before update on public.categorias
for each row execute function public.actualizar_updated_at();

create trigger preguntas_updated_at before update on public.preguntas
for each row execute function public.actualizar_updated_at();

-- Crea una partida y devuelve solo los datos de las preguntas elegidas. La
-- selección ocurre aquí, nunca en el navegador. `player_token` es un UUID v4
-- persistido localmente y funciona como capacidad opaca, sin datos personales.
create or replace function public.crear_partida(p_player_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_jugador_id uuid;
  v_partida_id uuid;
  v_numero_partida integer;
  v_ciclo integer;
  v_activas integer;
  v_no_vistas integer;
  v_objetivo integer;
  v_faltan integer;
  v_preguntas uuid[] := '{}'::uuid[];
  v_reemplazo uuid;
  v_es_repeticion_exacta boolean := false;
begin
  if p_player_token is null then
    raise exception 'player_token requerido' using errcode = '22004';
  end if;

  insert into public.jugadores (player_token)
  values (p_player_token)
  on conflict (player_token) do update set last_seen_at = now()
  returning id into v_jugador_id;

  -- Serializa la numeración/ciclo de un mismo jugador ante dobles clics.
  perform 1 from public.jugadores where id = v_jugador_id for update;
  update public.jugadores set last_seen_at = now() where id = v_jugador_id;

  select count(*) into v_activas from public.preguntas where activo;
  if v_activas = 0 then
    raise exception 'No hay preguntas activas' using errcode = 'P0001';
  end if;
  v_objetivo := least(10, v_activas);

  select count(*) into v_no_vistas
  from public.preguntas q
  where q.activo
    and not exists (
      select 1
      from public.partida_preguntas pp
      join public.partidas p on p.id = pp.partida_id
      where p.jugador_id = v_jugador_id and pp.pregunta_id = q.id
    );

  select coalesce(max(ciclo), 0) into v_ciclo
  from public.partidas where jugador_id = v_jugador_id;
  if v_ciclo = 0 then
    v_ciclo := 1;
  elsif v_no_vistas = 0 then
    v_ciclo := v_ciclo + 1;
  end if;

  -- Prioridad 1: todas las nunca vistas hasta completar el objetivo.
  select coalesce(array_agg(id order by prioridad), '{}'::uuid[]) into v_preguntas
  from (
    select q.id, random() as prioridad
    from public.preguntas q
    where q.activo
      and not exists (
        select 1 from public.partida_preguntas pp
        join public.partidas p on p.id = pp.partida_id
        where p.jugador_id = v_jugador_id and pp.pregunta_id = q.id
      )
    order by prioridad
    limit v_objetivo
  ) no_vistas;

  v_faltan := v_objetivo - coalesce(array_length(v_preguntas, 1), 0);
  if v_faltan > 0 then
    -- Prioridades 2-4: mayor antigüedad, menor presencia en las últimas tres
    -- partidas y azar. Así se distribuye la reutilización al agotar el banco.
    select v_preguntas || coalesce(array_agg(id order by posicion), '{}'::uuid[])
    into v_preguntas
    from (
      with historial as (
        select pp.pregunta_id, max(p.created_at) as ultima_vez
        from public.partida_preguntas pp
        join public.partidas p on p.id = pp.partida_id
        where p.jugador_id = v_jugador_id
        group by pp.pregunta_id
      ), ultimas_partidas as (
        select id from public.partidas
        where jugador_id = v_jugador_id
        order by created_at desc
        limit 3
      ), recientes as (
        select pp.pregunta_id, count(*) as apariciones_recientes
        from public.partida_preguntas pp
        where pp.partida_id in (select id from ultimas_partidas)
        group by pp.pregunta_id
      )
      select q.id,
             row_number() over (order by h.ultima_vez asc, coalesce(r.apariciones_recientes, 0) asc, random()) as posicion
      from public.preguntas q
      join historial h on h.pregunta_id = q.id
      left join recientes r on r.pregunta_id = q.id
      where q.activo and not (q.id = any(v_preguntas))
      order by h.ultima_vez asc, coalesce(r.apariciones_recientes, 0) asc, random()
      limit v_faltan
    ) reutilizadas;
  end if;

  -- Si existe otra opción, evita reconstruir exactamente el mismo conjunto de
  -- una partida previa cambiando la última pregunta por una alternativa.
  select exists (
    select 1 from (
      select array_agg(pp.pregunta_id order by pp.pregunta_id) as conjunto
      from public.partida_preguntas pp
      join public.partidas p on p.id = pp.partida_id
      where p.jugador_id = v_jugador_id
      group by pp.partida_id
    ) anteriores
    where conjunto = (select array_agg(x order by x) from unnest(v_preguntas) as x)
  ) into v_es_repeticion_exacta;

  if v_es_repeticion_exacta and v_activas > v_objetivo then
    select q.id into v_reemplazo
    from public.preguntas q
    where q.activo and not (q.id = any(v_preguntas))
    order by random()
    limit 1;
    v_preguntas[array_length(v_preguntas, 1)] := v_reemplazo;
  end if;

  select coalesce(max(numero_partida), 0) + 1 into v_numero_partida
  from public.partidas where jugador_id = v_jugador_id;

  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_id, v_numero_partida, v_ciclo)
  returning id into v_partida_id;

  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_id, pregunta_id, orden::smallint
  from unnest(v_preguntas) with ordinality as seleccion(pregunta_id, orden);

  return (
    select jsonb_build_object(
      'partida_id', v_partida_id,
      'numero_partida', v_numero_partida,
      'ciclo', v_ciclo,
      'questions', coalesce(jsonb_agg(jsonb_build_object(
        'id', q.id,
        'category', c.nombre,
        'text', q.texto,
        'hint', q.pista,
        'image', q.imagen,
        'imageAlt', q.imagen_alt,
        'answers', (
          select jsonb_agg(jsonb_build_object('id', r.id, 'text', r.texto) order by random())
          from public.respuestas r where r.pregunta_id = q.id
        )
      ) order by pp.orden), '[]'::jsonb)
    )
    from public.partida_preguntas pp
    join public.preguntas q on q.id = pp.pregunta_id
    join public.categorias c on c.id = q.categoria_id
    where pp.partida_id = v_partida_id
  );
end;
$$;

-- Registra una única respuesta, verifica que pertenece a esta partida/token y
-- recién entonces revela cuál era la correcta junto con la explicación.
create or replace function public.responder_pregunta(
  p_player_token uuid,
  p_partida_id uuid,
  p_pregunta_id uuid,
  p_respuesta_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pregunta_id uuid;
  v_correcta boolean;
  v_texto_correcto text;
  v_explicacion text;
  v_racha smallint := 0;
  v_fue_correcta boolean;
  v_ganados integer := 0;
  v_correct_answer record;
  v_hist record;
begin
  perform 1
  from public.partidas p
  join public.jugadores j on j.id = p.jugador_id
  where p.id = p_partida_id and j.player_token = p_player_token and p.estado = 'en_curso'
  for update of p;
  if not found then
    raise exception 'Partida no encontrada o no disponible' using errcode = 'P0001';
  end if;

  select pp.pregunta_id into v_pregunta_id
  from public.partida_preguntas pp
  where pp.partida_id = p_partida_id and pp.pregunta_id = p_pregunta_id and pp.respondida_at is null
  for update;
  if not found then
    raise exception 'Pregunta no disponible' using errcode = 'P0001';
  end if;

  select r.es_correcta into v_correcta
  from public.respuestas r
  where r.id = p_respuesta_id and r.pregunta_id = v_pregunta_id;
  if not found then
    raise exception 'Respuesta no pertenece a la pregunta' using errcode = 'P0001';
  end if;

  select r.id, r.texto, q.explicacion
  into v_correct_answer
  from public.respuestas r
  join public.preguntas q on q.id = r.pregunta_id
  where r.pregunta_id = v_pregunta_id and r.es_correcta;
  if not found then
    raise exception 'La pregunta no tiene respuesta correcta configurada' using errcode = 'P0001';
  end if;

  -- La racha anterior se calcula desde el historial servidor, no desde valores
  -- entregados por el navegador. Se corta ante la primera incorrecta.
  for v_hist in
    select fue_correcta from public.partida_preguntas
    where partida_id = p_partida_id and respondida_at is not null
    order by orden desc
  loop
    exit when not v_hist.fue_correcta;
    v_racha := v_racha + 1;
  end loop;

  v_fue_correcta := v_correcta;
  if v_fue_correcta then
    v_racha := v_racha + 1;
    v_ganados := 100 + case when v_racha >= 4 then 100 when v_racha >= 2 then 50 else 0 end;
  else
    v_racha := 0;
  end if;

  update public.partida_preguntas
  set respuesta_id = p_respuesta_id, fue_correcta = v_fue_correcta, respondida_at = now()
  where partida_id = p_partida_id and pregunta_id = v_pregunta_id;

  update public.jugadores set last_seen_at = now()
  where player_token = p_player_token;

  return jsonb_build_object(
    'correct', v_fue_correcta,
    'earned', v_ganados,
    'correct_answer_id', v_correct_answer.id,
    'correct_answer_text', v_correct_answer.texto,
    'explanation', v_correct_answer.explicacion
  );
end;
$$;

-- Finaliza una partida completamente respondida y reconstruye las estadísticas
-- desde `partida_preguntas`; no acepta puntaje ni rachas del cliente.
create or replace function public.finalizar_partida(p_player_token uuid, p_partida_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_total integer;
  v_respondidas integer;
  v_puntaje integer := 0;
  v_aciertos smallint := 0;
  v_racha smallint := 0;
  v_racha_maxima smallint := 0;
  v_fila record;
begin
  perform 1
  from public.partidas p join public.jugadores j on j.id = p.jugador_id
  where p.id = p_partida_id and j.player_token = p_player_token and p.estado = 'en_curso'
  for update of p;
  if not found then
    raise exception 'Partida no encontrada o ya finalizada' using errcode = 'P0001';
  end if;

  select count(*), count(*) filter (where respondida_at is not null)
  into v_total, v_respondidas
  from public.partida_preguntas where partida_id = p_partida_id;
  if v_total = 0 or v_total <> v_respondidas then
    raise exception 'La partida todavía no está completa' using errcode = 'P0001';
  end if;

  for v_fila in
    select fue_correcta from public.partida_preguntas
    where partida_id = p_partida_id order by orden
  loop
    if v_fila.fue_correcta then
      v_aciertos := v_aciertos + 1;
      v_racha := v_racha + 1;
      v_puntaje := v_puntaje + 100 + case when v_racha >= 4 then 100 when v_racha >= 2 then 50 else 0 end;
      v_racha_maxima := greatest(v_racha_maxima, v_racha);
    else
      v_racha := 0;
    end if;
  end loop;

  update public.partidas
  set puntaje = v_puntaje, aciertos = v_aciertos, racha_maxima = v_racha_maxima,
      estado = 'finalizada', finished_at = now()
  where id = p_partida_id;

  update public.jugadores set last_seen_at = now()
  where player_token = p_player_token;

  return jsonb_build_object('puntaje', v_puntaje, 'aciertos', v_aciertos, 'racha_maxima', v_racha_maxima);
end;
$$;

-- Todas las tablas expuestas mantienen RLS y no hay policies: el navegador
-- no puede listar ni modificar datos directamente. Las RPC SECURITY DEFINER
-- son la superficie mínima, con validación explícita del token y pertenencia.
alter table public.categorias enable row level security;
alter table public.preguntas enable row level security;
alter table public.respuestas enable row level security;
alter table public.jugadores enable row level security;
alter table public.partidas enable row level security;
alter table public.partida_preguntas enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on function public.actualizar_updated_at() from public;
revoke all on function public.crear_partida(uuid) from public;
revoke all on function public.responder_pregunta(uuid, uuid, uuid, uuid) from public;
revoke all on function public.finalizar_partida(uuid, uuid) from public;
grant usage on schema public to anon;
grant execute on function public.crear_partida(uuid) to anon;
grant execute on function public.responder_pregunta(uuid, uuid, uuid, uuid) to anon;
grant execute on function public.finalizar_partida(uuid, uuid) to anon;
