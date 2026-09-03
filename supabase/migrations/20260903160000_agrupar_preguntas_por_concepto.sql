-- Agrupa variantes semánticas únicamente dentro de cada partida. Un UUID
-- nullable evita introducir una entidad adicional antes de que sea necesaria.
alter table public.preguntas
  add column concepto_id uuid;

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
  v_reemplazo_orden integer;
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

  -- Las preguntas sin concepto forman su propio grupo; las variantes con el
  -- mismo concepto sólo pueden aportar una pregunta a la partida actual.
  select count(*) into v_activas
  from (
    select distinct case
      when q.concepto_id is null then 'pregunta:' || q.id::text
      else 'concepto:' || q.concepto_id::text
    end
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

  -- Prioridad 1: preguntas nunca vistas, con una variante por concepto.
  select coalesce(array_agg(id order by prioridad), '{}'::uuid[]) into v_preguntas
  from (
    select id, random() as prioridad
    from (
      select distinct on (case
        when q.concepto_id is null then 'pregunta:' || q.id::text
        else 'concepto:' || q.concepto_id::text
      end) q.id
      from public.preguntas q
      where q.activo and q.estado_editorial = 'publicada'
        and not exists (
          select 1 from public.partida_preguntas pp
          join public.partidas p on p.id = pp.partida_id
          where p.jugador_id = v_jugador_id and pp.pregunta_id = q.id
        )
      order by case
        when q.concepto_id is null then 'pregunta:' || q.id::text
        else 'concepto:' || q.concepto_id::text
      end, random()
    ) no_vistas_por_concepto
    order by prioridad
    limit v_objetivo
  ) no_vistas;

  v_faltan := v_objetivo - coalesce(array_length(v_preguntas, 1), 0);
  if v_faltan > 0 then
    -- Prioridades 2-4 de la selección existente: mayor antigüedad, menor
    -- presencia reciente y azar. Sólo se suman conceptos aún no elegidos.
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
      ), candidatas_por_concepto as (
        select distinct on (case
          when q.concepto_id is null then 'pregunta:' || q.id::text
          else 'concepto:' || q.concepto_id::text
        end)
          q.id, h.ultima_vez, coalesce(r.apariciones_recientes, 0) as apariciones_recientes
        from public.preguntas q
        join historial h on h.pregunta_id = q.id
        left join recientes r on r.pregunta_id = q.id
        where q.activo and q.estado_editorial = 'publicada'
          and not (q.id = any(v_preguntas))
          and not exists (
            select 1
            from unnest(v_preguntas) as seleccion(pregunta_id)
            join public.preguntas elegida on elegida.id = seleccion.pregunta_id
            where (case
              when elegida.concepto_id is null then 'pregunta:' || elegida.id::text
              else 'concepto:' || elegida.concepto_id::text
            end) = (case
              when q.concepto_id is null then 'pregunta:' || q.id::text
              else 'concepto:' || q.concepto_id::text
            end)
          )
        order by case
          when q.concepto_id is null then 'pregunta:' || q.id::text
          else 'concepto:' || q.concepto_id::text
        end, h.ultima_vez asc,
          coalesce(r.apariciones_recientes, 0) asc, random()
      )
      select id,
             row_number() over (order by ultima_vez asc, apariciones_recientes asc, random()) as posicion
      from candidatas_por_concepto
      order by ultima_vez asc, apariciones_recientes asc, random()
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

  if v_es_repeticion_exacta then
    -- Primero cambia una variante por otra del mismo concepto. Así conserva
    -- los grupos representados incluso si no hay conceptos adicionales.
    select alternativa.id, seleccion.orden::integer
    into v_reemplazo, v_reemplazo_orden
    from unnest(v_preguntas) with ordinality as seleccion(pregunta_id, orden)
    join public.preguntas elegida on elegida.id = seleccion.pregunta_id
    join public.preguntas alternativa
      on alternativa.concepto_id = elegida.concepto_id
    where elegida.concepto_id is not null
      and alternativa.activo and alternativa.estado_editorial = 'publicada'
      and alternativa.id <> elegida.id
      and not (alternativa.id = any(v_preguntas))
    order by random()
    limit 1;

    if found then
      v_preguntas[v_reemplazo_orden] := v_reemplazo;
    elsif v_activas > v_objetivo then
      -- Si no hay variantes disponibles, conserva el fallback previo hacia
      -- un concepto que aún no esté representado.
      select q.id into v_reemplazo
      from public.preguntas q
      where q.activo and q.estado_editorial = 'publicada'
        and not (q.id = any(v_preguntas))
        and not exists (
          select 1
          from unnest(v_preguntas) as seleccion(pregunta_id)
          join public.preguntas elegida on elegida.id = seleccion.pregunta_id
          where (case
            when elegida.concepto_id is null then 'pregunta:' || elegida.id::text
            else 'concepto:' || elegida.concepto_id::text
          end) = (case
            when q.concepto_id is null then 'pregunta:' || q.id::text
            else 'concepto:' || q.concepto_id::text
          end)
        )
      order by random()
      limit 1;

      if found then
        v_preguntas[array_length(v_preguntas, 1)] := v_reemplazo;
      end if;
    end if;
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
        'concepto_id', q.concepto_id,
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
