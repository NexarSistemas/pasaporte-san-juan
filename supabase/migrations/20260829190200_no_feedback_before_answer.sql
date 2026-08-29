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
