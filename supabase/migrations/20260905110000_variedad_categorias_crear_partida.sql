-- Mantiene grupos tipados y prioridad por no visto/recencia. Para completar
-- hasta diez, la degradación intenta en orden: (1) dos por categoría y sin
-- adyacencias, (2) dos por categoría, (3) sin adyacencias y (4) sólo grupos.

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
  v_grupos_no_vistos integer;
  v_objetivo integer;
  v_limite_categoria integer;
  v_modo integer;
  v_preguntas uuid[] := '{}'::uuid[];
  v_ordenadas uuid[];
  v_restantes uuid[];
  v_candidata_array uuid[];
  v_categoria_anterior uuid;
  v_categoria uuid;
  v_candidata record;
  v_seleccion record;
  v_alternativa record;
  v_reemplazo uuid;
  v_reemplazado boolean := false;
  v_restricciones_validas boolean;
  v_no_repite boolean;
  v_seleccion_completa boolean := false;
begin
  if p_player_token is null then
    raise exception 'player_token requerido' using errcode = '22004';
  end if;

  insert into public.jugadores (player_token)
  values (p_player_token)
  on conflict (player_token) do update set last_seen_at = now()
  returning id into v_jugador_id;

  -- Serializa numeración y ciclo de un mismo jugador ante dobles clics.
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
  select count(*) into v_grupos_no_vistos
  from (
    select distinct case when q.concepto_id is null then 'pregunta:' || q.id::text
      else 'concepto:' || q.concepto_id::text end
    from public.preguntas q
    where q.activo and q.estado_editorial = 'publicada'
      and not exists (
        select 1 from public.partida_preguntas pp
        join public.partidas p on p.id = pp.partida_id
        where p.jugador_id = v_jugador_id and pp.pregunta_id = q.id
      )
  ) grupos_no_vistos;

  select coalesce(max(ciclo), 0) into v_ciclo
  from public.partidas where jugador_id = v_jugador_id;
  if v_ciclo = 0 then
    v_ciclo := 1;
  elsif v_no_vistas = 0 then
    v_ciclo := v_ciclo + 1;
  end if;

  -- Un modo sólo tiene éxito si alcanza el objetivo. Los modos con
  -- adyacencia construyen después un orden completo con mayor frecuencia
  -- restante, que encuentra una secuencia válida cuando ésta existe.
  for v_modo in 1..4 loop
    v_limite_categoria := case v_modo
      when 1 then least(2, (v_objetivo + 1) / 2)
      when 2 then 2
      when 3 then (v_objetivo + 1) / 2
      else v_objetivo
    end;
    v_preguntas := '{}'::uuid[];

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
      -- La comparación es por grupo tipado y no sólo por pregunta_id: una
      -- variante que aparezca en otro recorrido nunca ocupa otro lugar.
      if not exists (
          select 1
          from unnest(v_preguntas) seleccion(pregunta_id)
          join public.preguntas elegida on elegida.id = seleccion.pregunta_id
          where (case when elegida.concepto_id is null then 'pregunta:' || elegida.id::text
            else 'concepto:' || elegida.concepto_id::text end) = v_candidata.grupo
        )
        and (select count(*) < v_limite_categoria
          from unnest(v_preguntas) seleccion(pregunta_id)
          join public.preguntas elegida on elegida.id = seleccion.pregunta_id
          where elegida.categoria_id = v_candidata.categoria_id) then
        v_preguntas := array_append(v_preguntas, v_candidata.id);
      end if;
      exit when coalesce(array_length(v_preguntas, 1), 0) = v_objetivo;
    end loop;

    if coalesce(array_length(v_preguntas, 1), 0) <> v_objetivo then
      continue;
    end if;

    -- Si todos los grupos no vistos caben, no se acepta una solución que
    -- deje alguno afuera sólo para completar con un grupo ya visto.
    if v_grupos_no_vistos <= v_objetivo and exists (
      select 1
      from public.preguntas no_vista
      where no_vista.activo and no_vista.estado_editorial = 'publicada'
        and not exists (
          select 1 from public.partida_preguntas pp
          join public.partidas p on p.id = pp.partida_id
          where p.jugador_id = v_jugador_id and pp.pregunta_id = no_vista.id
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
    ) then
      continue;
    end if;

    if v_modo in (1, 3) then
      v_restantes := v_preguntas;
      v_ordenadas := '{}'::uuid[];
      v_categoria_anterior := null;
      loop
        select opcion.id, opcion.categoria_id
        into v_reemplazo, v_categoria
        from (
          select p.id, p.categoria_id, seleccion.orden,
            count(*) over (partition by p.categoria_id) as cantidad_restante
          from unnest(v_restantes) with ordinality seleccion(pregunta_id, orden)
          join public.preguntas p on p.id = seleccion.pregunta_id
          where v_categoria_anterior is null or p.categoria_id <> v_categoria_anterior
        ) opcion
        order by opcion.cantidad_restante desc, opcion.orden
        limit 1;
        exit when not found;
        v_ordenadas := array_append(v_ordenadas, v_reemplazo);
        v_restantes := array_remove(v_restantes, v_reemplazo);
        v_categoria_anterior := v_categoria;
        exit when coalesce(array_length(v_ordenadas, 1), 0) = v_objetivo;
      end loop;
      if coalesce(array_length(v_ordenadas, 1), 0) <> v_objetivo then
        continue;
      end if;
      v_preguntas := v_ordenadas;
    end if;

    v_seleccion_completa := true;
    exit;
  end loop;

  if not v_seleccion_completa then
    raise exception 'No fue posible seleccionar grupos activos' using errcode = 'P0001';
  end if;

  -- Si el conjunto coincide con una partida anterior, primero intenta otra
  -- variante del mismo grupo y luego un grupo no seleccionado. Ambos caminos
  -- validan el arreglo completo contra el modo alcanzado antes de reemplazar.
  select exists (
    select 1 from (
      select array_agg(pp.pregunta_id order by pp.pregunta_id) as conjunto
      from public.partida_preguntas pp
      join public.partidas p on p.id = pp.partida_id
      where p.jugador_id = v_jugador_id
      group by pp.partida_id
    ) anteriores
    where conjunto = (select array_agg(x order by x) from unnest(v_preguntas) x)
  ) into v_no_repite;

  if v_no_repite then
    <<buscar_variante>>
    for v_seleccion in
      select seleccion.pregunta_id, seleccion.orden::integer
      from unnest(v_preguntas) with ordinality seleccion(pregunta_id, orden)
    loop
      for v_alternativa in
        select alternativa.id
        from public.preguntas elegida
        join public.preguntas alternativa on alternativa.concepto_id = elegida.concepto_id
        where elegida.id = v_seleccion.pregunta_id and elegida.concepto_id is not null
          and alternativa.activo and alternativa.estado_editorial = 'publicada'
          and alternativa.id <> elegida.id and not (alternativa.id = any(v_preguntas))
      loop
        v_candidata_array := array_replace(v_preguntas, v_seleccion.pregunta_id, v_alternativa.id);
        select (v_modo not in (1, 2) or not exists (
            select 1
            from unnest(v_candidata_array) seleccion(pregunta_id)
            join public.preguntas p on p.id = seleccion.pregunta_id
            group by p.categoria_id having count(*) > 2
          )) and (v_modo not in (1, 3) or not exists (
            select 1 from (
              select p.categoria_id, lag(p.categoria_id) over (order by seleccion.orden) as anterior
              from unnest(v_candidata_array) with ordinality seleccion(pregunta_id, orden)
              join public.preguntas p on p.id = seleccion.pregunta_id
            ) ordenadas where categoria_id = anterior
          )) into v_restricciones_validas;
        select not exists (
          select 1 from (
            select array_agg(pp.pregunta_id order by pp.pregunta_id) as conjunto
            from public.partida_preguntas pp
            join public.partidas p on p.id = pp.partida_id
            where p.jugador_id = v_jugador_id group by pp.partida_id
          ) anteriores
          where conjunto = (select array_agg(x order by x) from unnest(v_candidata_array) x)
        ) into v_no_repite;
        if v_restricciones_validas and v_no_repite then
          v_preguntas := v_candidata_array;
          v_reemplazado := true;
          exit buscar_variante;
        end if;
      end loop;
    end loop;

    if not v_reemplazado then
      <<buscar_grupo_nuevo>>
      for v_seleccion in
        select seleccion.pregunta_id, seleccion.orden::integer
        from unnest(v_preguntas) with ordinality seleccion(pregunta_id, orden)
      loop
        for v_alternativa in
          select alternativa.id
          from public.preguntas alternativa
          where alternativa.activo and alternativa.estado_editorial = 'publicada'
            and not exists (
              select 1
              from unnest(v_preguntas) seleccion(pregunta_id)
              join public.preguntas elegida on elegida.id = seleccion.pregunta_id
              where (case when elegida.concepto_id is null then 'pregunta:' || elegida.id::text
                else 'concepto:' || elegida.concepto_id::text end) =
                (case when alternativa.concepto_id is null then 'pregunta:' || alternativa.id::text
                  else 'concepto:' || alternativa.concepto_id::text end)
            )
        loop
          v_candidata_array := array_replace(v_preguntas, v_seleccion.pregunta_id, v_alternativa.id);
          select (v_modo not in (1, 2) or not exists (
              select 1
              from unnest(v_candidata_array) seleccion(pregunta_id)
              join public.preguntas p on p.id = seleccion.pregunta_id
              group by p.categoria_id having count(*) > 2
            )) and (v_modo not in (1, 3) or not exists (
              select 1 from (
                select p.categoria_id, lag(p.categoria_id) over (order by seleccion.orden) as anterior
                from unnest(v_candidata_array) with ordinality seleccion(pregunta_id, orden)
                join public.preguntas p on p.id = seleccion.pregunta_id
              ) ordenadas where categoria_id = anterior
            )) into v_restricciones_validas;
          select not exists (
            select 1 from (
              select array_agg(pp.pregunta_id order by pp.pregunta_id) as conjunto
              from public.partida_preguntas pp
              join public.partidas p on p.id = pp.partida_id
              where p.jugador_id = v_jugador_id group by pp.partida_id
            ) anteriores
            where conjunto = (select array_agg(x order by x) from unnest(v_candidata_array) x)
          ) into v_no_repite;
          if v_restricciones_validas and v_no_repite then
            v_preguntas := v_candidata_array;
            exit buscar_grupo_nuevo;
          end if;
        end loop;
      end loop;
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
      'partida_id', v_partida_id, 'numero_partida', v_numero_partida, 'ciclo', v_ciclo,
      'questions', coalesce(jsonb_agg(jsonb_build_object(
        'id', q.id, 'concepto_id', q.concepto_id, 'category', c.nombre, 'text', q.texto,
        'hint', q.pista, 'image', q.imagen, 'imageAlt', q.imagen_alt, 'answers', (
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
