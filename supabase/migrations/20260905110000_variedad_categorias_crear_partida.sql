-- Mantiene una pregunta por concepto y la prioridad por no visto/recencia,
-- incorporando variedad de categorías. La degradación es explícita: primero
-- respeta ambos límites, luego admite adyacencias, después supera dos por
-- categoría conservando el espaciado y por último completa sólo por grupo.

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
  v_preguntas uuid[] := '{}'::uuid[];
  v_candidata record;
  v_modo integer;
  v_categoria_anterior uuid;
  v_es_repeticion_exacta boolean := false;
  v_reemplazo uuid;
  v_reemplazo_orden integer;
  v_agrego boolean;
begin
  if p_player_token is null then
    raise exception 'player_token requerido' using errcode = '22004';
  end if;

  insert into public.jugadores (player_token)
  values (p_player_token)
  on conflict (player_token) do update set last_seen_at = now()
  returning id into v_jugador_id;

  perform 1 from public.jugadores where id = v_jugador_id for update;
  update public.jugadores set last_seen_at = now() where id = v_jugador_id;

  select count(*) into v_activas
  from (
    select distinct case when q.concepto_id is null then 'pregunta:' || q.id::text
      else 'concepto:' || q.concepto_id::text end
    from public.preguntas q
    where q.activo and q.estado_editorial = 'publicada'
  ) grupos_activos;
  if v_activas = 0 then
    raise exception 'No hay preguntas activas' using errcode = 'P0001';
  end if;
  v_objetivo := least(10, v_activas);

  select count(*) into v_no_vistas
  from public.preguntas q
  where q.activo and q.estado_editorial = 'publicada'
    and not exists (
      select 1 from public.partida_preguntas pp
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

  -- Cada modo vuelve a recorrer las candidatas con la misma prioridad. Sólo
  -- se relajan restricciones de categoría antes de reducir una partida.
  for v_modo in 1..4 loop
    v_preguntas := '{}'::uuid[];
    v_categoria_anterior := null;
    loop
      v_agrego := false;
      for v_candidata in
      with ultimas_partidas as (
        select id, created_at, numero_partida
        from public.partidas
        where jugador_id = v_jugador_id
        order by created_at desc, numero_partida desc
        limit 3
      ), historial as (
        select pp.pregunta_id, max(p.created_at) as ultima_vez
        from public.partida_preguntas pp
        join public.partidas p on p.id = pp.partida_id
        where p.jugador_id = v_jugador_id
        group by pp.pregunta_id
      ), recientes as (
        select pp.pregunta_id, count(*) as apariciones_recientes
        from public.partida_preguntas pp
        where pp.partida_id in (select id from ultimas_partidas)
        group by pp.pregunta_id
      ), grupos_recientes as (
        select distinct case when q.concepto_id is null then 'pregunta:' || q.id::text
          else 'concepto:' || q.concepto_id::text end as grupo
        from public.partida_preguntas pp
        join public.preguntas q on q.id = pp.pregunta_id
        where pp.partida_id in (select id from ultimas_partidas)
      ), grupo_anterior as (
        select distinct case when q.concepto_id is null then 'pregunta:' || q.id::text
          else 'concepto:' || q.concepto_id::text end as grupo
        from public.partida_preguntas pp
        join public.preguntas q on q.id = pp.pregunta_id
        where pp.partida_id = (
          select id from ultimas_partidas
          order by created_at desc, numero_partida desc limit 1
        )
      ), por_grupo as (
        select distinct on (case when q.concepto_id is null then 'pregunta:' || q.id::text
          else 'concepto:' || q.concepto_id::text end)
          q.id, q.categoria_id,
          case when q.concepto_id is null then 'pregunta:' || q.id::text
            else 'concepto:' || q.concepto_id::text end as grupo,
          case when h.pregunta_id is null then 0 else 1 end as vista,
          case when (case when q.concepto_id is null then 'pregunta:' || q.id::text
            else 'concepto:' || q.concepto_id::text end) in (select grupo from grupo_anterior)
            then 1 else 0 end as fue_anterior,
          case when (case when q.concepto_id is null then 'pregunta:' || q.id::text
            else 'concepto:' || q.concepto_id::text end) in (select grupo from grupos_recientes)
            then 1 else 0 end as fue_reciente,
          h.ultima_vez, coalesce(r.apariciones_recientes, 0) as apariciones_recientes
        from public.preguntas q
        left join historial h on h.pregunta_id = q.id
        left join recientes r on r.pregunta_id = q.id
        where q.activo and q.estado_editorial = 'publicada'
        order by case when q.concepto_id is null then 'pregunta:' || q.id::text
          else 'concepto:' || q.concepto_id::text end,
          case when h.pregunta_id is null then 0 else 1 end,
          h.ultima_vez asc nulls first, coalesce(r.apariciones_recientes, 0), random()
      )
      select * from por_grupo
      order by vista, fue_anterior, fue_reciente,
        ultima_vez asc nulls first, apariciones_recientes, random()
      loop
        if (v_candidata.vista = 0 or not exists (
              select 1
              from public.preguntas no_vista
              where no_vista.activo and no_vista.estado_editorial = 'publicada'
                and not exists (
                  select 1 from public.partida_preguntas pp
                  join public.partidas p on p.id = pp.partida_id
                  where p.jugador_id = v_jugador_id
                    and pp.pregunta_id = no_vista.id
                )
                and not exists (
                  select 1
                  from unnest(v_preguntas) seleccion(pregunta_id)
                  join public.preguntas elegida on elegida.id = seleccion.pregunta_id
                  where (case when elegida.concepto_id is null then 'pregunta:' || elegida.id::text
                    else 'concepto:' || elegida.concepto_id::text end) =
                    (case when no_vista.concepto_id is null then 'pregunta:' || no_vista.id::text
                      else 'concepto:' || no_vista.concepto_id::text end)
                )
            ))
            and not (v_candidata.id = any(v_preguntas))
            and (v_modo >= 3 or (
            select count(*) < 2
            from unnest(v_preguntas) seleccion(pregunta_id)
            join public.preguntas elegida on elegida.id = seleccion.pregunta_id
            where elegida.categoria_id = v_candidata.categoria_id
          ))
          and (v_modo in (2, 4) or v_categoria_anterior is null
            or v_categoria_anterior <> v_candidata.categoria_id) then
          v_preguntas := array_append(v_preguntas, v_candidata.id);
          v_categoria_anterior := v_candidata.categoria_id;
          v_agrego := true;
        end if;
        exit when coalesce(array_length(v_preguntas, 1), 0) = v_objetivo;
      end loop;
      exit when coalesce(array_length(v_preguntas, 1), 0) = v_objetivo or not v_agrego;
    end loop;
    exit when coalesce(array_length(v_preguntas, 1), 0) = v_objetivo;
  end loop;

  -- Conserva el fallback histórico para no repetir exactamente un conjunto,
  -- sin alterar los límites de categoría que resolvió el modo seleccionado.
  select exists (
    select 1 from (
      select array_agg(pp.pregunta_id order by pp.pregunta_id) as conjunto
      from public.partida_preguntas pp
      join public.partidas p on p.id = pp.partida_id
      where p.jugador_id = v_jugador_id
      group by pp.partida_id
    ) anteriores
    where conjunto = (select array_agg(x order by x) from unnest(v_preguntas) x)
  ) into v_es_repeticion_exacta;

  if v_es_repeticion_exacta then
    select alternativa.id, seleccion.orden::integer
    into v_reemplazo, v_reemplazo_orden
    from unnest(v_preguntas) with ordinality seleccion(pregunta_id, orden)
    join public.preguntas elegida on elegida.id = seleccion.pregunta_id
    join public.preguntas alternativa on alternativa.concepto_id = elegida.concepto_id
    where elegida.concepto_id is not null
      and alternativa.activo and alternativa.estado_editorial = 'publicada'
      and alternativa.id <> elegida.id and not (alternativa.id = any(v_preguntas))
      and not exists (
        select 1
        from (
          select array_agg(pp.pregunta_id order by pp.pregunta_id) as conjunto
          from public.partida_preguntas pp
          join public.partidas p on p.id = pp.partida_id
          where p.jugador_id = v_jugador_id
          group by pp.partida_id
        ) anteriores
        where conjunto = (
          select array_agg(pregunta_id order by pregunta_id)
          from unnest(array_replace(v_preguntas, elegida.id, alternativa.id)) candidata(pregunta_id)
        )
      )
    order by random() limit 1;
    if found then
      v_preguntas[v_reemplazo_orden] := v_reemplazo;
    end if;
  end if;

  select coalesce(max(numero_partida), 0) + 1 into v_numero_partida
  from public.partidas where jugador_id = v_jugador_id;
  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_id, v_numero_partida, v_ciclo)
  returning id into v_partida_id;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_id, pregunta_id, orden::smallint
  from unnest(v_preguntas) with ordinality seleccion(pregunta_id, orden);

  return (
    select jsonb_build_object(
      'partida_id', v_partida_id, 'numero_partida', v_numero_partida,
      'ciclo', v_ciclo, 'questions', coalesce(jsonb_agg(jsonb_build_object(
        'id', q.id, 'concepto_id', q.concepto_id, 'category', c.nombre,
        'text', q.texto, 'hint', q.pista, 'image', q.imagen,
        'imageAlt', q.imagen_alt, 'answers', (
          select jsonb_agg(jsonb_build_object('id', r.id, 'text', r.texto) order by random())
          from public.respuestas r where r.pregunta_id = q.id
        )) order by pp.orden), '[]'::jsonb)
    )
    from public.partida_preguntas pp
    join public.preguntas q on q.id = pp.pregunta_id
    join public.categorias c on c.id = q.categoria_id
    where pp.partida_id = v_partida_id
  );
end;
$$;
