-- Ejecutar en una base con todas las migraciones y el seed actuales. Todo queda revertido.
begin;

do $tests$
declare
  v_token uuid := '33333333-3333-4333-8333-333333333333';
  v_otro_token uuid := '44444444-4444-4444-8444-444444444444';
  v_primera jsonb;
  v_segunda jsonb;
  v_tercera jsonb;
  v_cuarta jsonb;
  v_quinta jsonb;
  v_respuesta_partida jsonb;
  v_finalizar_partida jsonb;
  v_ajena jsonb;
  v_resultado jsonb;
  v_pregunta jsonb;
  v_respuesta uuid;
  v_count integer;
  v_simulacion_token uuid := '55555555-5555-4555-8555-555555555555';
  v_simulacion jsonb;
  v_partidas_simuladas jsonb[] := '{}';
  v_indice integer;
  v_banco_exacto jsonb;
  v_banco_reducido_primera jsonb;
  v_banco_reducido_segunda jsonb;
  v_concepto_a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_concepto_b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_conceptos_primera jsonb;
  v_conceptos_segunda jsonb;
  v_banco_mismo_concepto jsonb;
  v_token_variantes uuid := 'aaaaaaaa-1111-4111-8111-111111111111';
  v_jugador_variantes uuid;
  v_partida_variantes_base uuid;
  v_partida_variantes_alterna uuid;
  v_regresion_variantes jsonb;
  v_token_combinaciones uuid := 'aaaaaaaa-2222-4222-8222-222222222222';
  v_jugador_combinaciones uuid;
  v_partida_combinacion_a1 uuid;
  v_partida_combinacion_a2 uuid;
  v_partida_combinacion_a3 uuid;
  v_sin_alternativa_nueva jsonb;
  v_con_alternativa_nueva jsonb;
  v_token_prioridad uuid := 'aaaaaaaa-3333-4333-8333-333333333333';
  v_jugador_prioridad uuid;
  v_partida_prioridad_base uuid;
  v_partida_prioridad_posterior uuid;
  v_prioridad_reciente jsonb;
  v_prioridad_fuera_horizonte jsonb;
  v_token_orden_reciente uuid := 'aaaaaaaa-4444-4444-8444-444444444444';
  v_jugador_orden_reciente uuid;
  v_partida_orden_antigua uuid;
  v_partida_orden_menor uuid;
  v_partida_orden_mayor uuid;
  v_orden_reciente jsonb;
begin
  -- Jugador nuevo/existente y dos primeras partidas sin repetición.
  v_primera := public.crear_partida(v_token);
  assert jsonb_array_length(v_primera->'questions') = 10, 'La primera partida debe tener 10 preguntas';
  select count(distinct q->>'id') into v_count
  from jsonb_array_elements(v_primera->'questions') q;
  assert v_count = 10, 'Una partida con banco mayor al objetivo no debe duplicar pregunta_id';
  v_segunda := public.crear_partida(v_token);
  select count(*) into v_count
  from jsonb_array_elements(v_primera->'questions') a
  join jsonb_array_elements(v_segunda->'questions') b on a->>'id' = b->>'id';
  assert v_count = 0, 'No se deben repetir preguntas entre las dos primeras partidas';
  assert (v_segunda->>'numero_partida')::integer = 2, 'El jugador existente debe conservar su contador';

  -- Agotamiento parcial y total de las 24 preguntas seed.
  v_tercera := public.crear_partida(v_token);
  select count(distinct item->>'id') into v_count
  from (
    select value as item from jsonb_array_elements(v_primera->'questions')
    union all select value from jsonb_array_elements(v_segunda->'questions')
    union all select value from jsonb_array_elements(v_tercera->'questions')
  ) banco;
  assert v_count = 24, 'Las tres primeras partidas deben cubrir las 24 preguntas';
  v_cuarta := public.crear_partida(v_token);
  assert (v_cuarta->>'ciclo')::integer = 2, 'Al agotar el banco debe iniciar ciclo 2';
  assert jsonb_array_length(v_cuarta->'questions') = 10, 'El nuevo ciclo debe conservar 10 preguntas';

  -- Una pregunta nueva se prioriza aunque el jugador esté en ciclo 2.
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial)
  select 'test-nueva', id, 'Pregunta nueva de prueba', 'Explicación de prueba', 'publicada'
  from public.categorias where slug = 'destinos';
  insert into public.respuestas (pregunta_id, texto, es_correcta)
  select id, 'Correcta nueva', true from public.preguntas where codigo_origen = 'test-nueva';
  v_quinta := public.crear_partida(v_token);
  assert exists (
    select 1 from jsonb_array_elements(v_quinta->'questions') q
    join public.preguntas p on p.id::text = q->>'id'
    where p.codigo_origen = 'test-nueva'
  ), 'Las preguntas añadidas deben tratarse como nunca vistas';

  -- Respuesta incorrecta, doble respuesta y pregunta/partida ajena.
  v_respuesta_partida := public.crear_partida(v_token);
  select value into v_pregunta from jsonb_array_elements(v_respuesta_partida->'questions') q
  where exists (
    select 1 from public.respuestas r
    where r.pregunta_id = (q.value->>'id')::uuid and not r.es_correcta
  ) limit 1;
  select r.id into v_respuesta from public.respuestas r
  where r.pregunta_id = (v_pregunta->>'id')::uuid and not r.es_correcta limit 1;
  v_resultado := public.responder_pregunta(v_token, (v_respuesta_partida->>'partida_id')::uuid, (v_pregunta->>'id')::uuid, v_respuesta);
  assert (v_resultado->>'correct')::boolean = false, 'La respuesta incorrecta debe informarse como tal';
  begin
    perform public.responder_pregunta(v_token, (v_respuesta_partida->>'partida_id')::uuid, (v_pregunta->>'id')::uuid, v_respuesta);
    assert false, 'Una segunda respuesta debe fallar';
  exception when others then null;
  end;
  v_ajena := public.crear_partida(v_otro_token);
  select value into v_pregunta from jsonb_array_elements(v_ajena->'questions') limit 1;
  select id into v_respuesta from public.respuestas where pregunta_id = (v_pregunta->>'id')::uuid limit 1;
  begin
    perform public.responder_pregunta(v_token, (v_ajena->>'partida_id')::uuid, (v_pregunta->>'id')::uuid, v_respuesta);
    assert false, 'No se debe poder responder una partida ajena';
  exception when others then null;
  end;

  -- Respuestas correctas, finalización y estadísticas reconstruidas del historial.
  v_finalizar_partida := public.crear_partida(v_token);
  for v_pregunta in select value from jsonb_array_elements(v_finalizar_partida->'questions') loop
    select id into v_respuesta from public.respuestas
    where pregunta_id = (v_pregunta->>'id')::uuid and es_correcta;
    v_resultado := public.responder_pregunta(v_token, (v_finalizar_partida->>'partida_id')::uuid, (v_pregunta->>'id')::uuid, v_respuesta);
    assert (v_resultado->>'correct')::boolean, 'La respuesta correcta debe validarse en servidor';
  end loop;
  v_resultado := public.finalizar_partida(v_token, (v_finalizar_partida->>'partida_id')::uuid);
  assert (v_resultado->>'aciertos')::integer = 10, 'La finalización debe calcular aciertos';
  assert (v_resultado->>'puntaje')::integer = 1800, 'La finalización debe reconstruir el puntaje v0.2.0';
  begin
    perform public.finalizar_partida(v_token, (v_finalizar_partida->>'partida_id')::uuid);
    assert false, 'No se debe poder finalizar dos veces';
  exception when others then null;
  end;

  -- Simulación solicitada: 100 preguntas, 10 partidas sin repetición y una 11.
  update public.preguntas set activo = false;
  for v_indice in 1..100 loop
    insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial)
    select format('sim-%s', v_indice), id, format('Simulación %s', v_indice), 'Simulación', 'publicada'
    from public.categorias where slug = 'destinos';
    insert into public.respuestas (pregunta_id, texto, es_correcta)
    select id, 'Correcta', true from public.preguntas where codigo_origen = format('sim-%s', v_indice);
  end loop;
  for v_indice in 1..10 loop
    v_simulacion := public.crear_partida(v_simulacion_token);
    assert jsonb_array_length(v_simulacion->'questions') = 10, 'Cada partida simulada debe tener 10 preguntas';
    v_partidas_simuladas := array_append(v_partidas_simuladas, v_simulacion);
  end loop;
  select count(distinct q->>'id') into v_count
  from unnest(v_partidas_simuladas) partida, jsonb_array_elements(partida->'questions') q;
  assert v_count = 100, 'Las primeras 10 partidas deben ver las 100 preguntas sin repetición';
  v_simulacion := public.crear_partida(v_simulacion_token);
  assert jsonb_array_length(v_simulacion->'questions') = 10, 'La partida 11 debe tener 10 preguntas';
  select count(*) into v_count from jsonb_array_elements(v_simulacion->'questions');
  assert v_count = 10, 'La partida 11 no debe tener duplicados internos';
  assert not exists (
    select 1
    from unnest(v_partidas_simuladas) partida
    where (select array_agg(q->>'id' order by q->>'id') from jsonb_array_elements(partida->'questions') q)
        = (select array_agg(q->>'id' order by q->>'id') from jsonb_array_elements(v_simulacion->'questions') q)
  ), 'La partida 11 no debe reconstruir una partida previa';

  -- Cada partida debe usar pregunta_id únicos incluso cuando el banco sea
  -- exactamente igual o menor que el objetivo habitual.
  update public.preguntas set activo = false;
  with banco_exacto as (
    select id from public.preguntas order by codigo_origen limit 10
  )
  update public.preguntas set activo = true
  where id in (select id from banco_exacto);
  v_banco_exacto := public.crear_partida('66666666-6666-4666-8666-666666666666');
  assert jsonb_array_length(v_banco_exacto->'questions') = 10,
    'Un banco exactamente igual al objetivo debe incluir sus 10 preguntas';
  select count(distinct q->>'id') into v_count
  from jsonb_array_elements(v_banco_exacto->'questions') q;
  assert v_count = 10,
    'Un banco exactamente igual al objetivo no debe duplicar pregunta_id';

  update public.preguntas set activo = false;
  with banco_reducido as (
    select id from public.preguntas order by codigo_origen limit 3
  )
  update public.preguntas set activo = true
  where id in (select id from banco_reducido);
  v_banco_reducido_primera := public.crear_partida('77777777-7777-4777-8777-777777777777');
  v_banco_reducido_segunda := public.crear_partida('77777777-7777-4777-8777-777777777777');
  assert jsonb_array_length(v_banco_reducido_primera->'questions') = 3,
    'Un banco menor al objetivo debe devolver todas sus preguntas únicas';
  assert jsonb_array_length(v_banco_reducido_segunda->'questions') = 3,
    'Una nueva partida debe conservar el máximo disponible del banco reducido';
  select count(distinct q->>'id') into v_count
  from jsonb_array_elements(v_banco_reducido_primera->'questions') q;
  assert v_count = 3,
    'La primera partida con banco reducido no debe duplicar pregunta_id';
  select count(distinct q->>'id') into v_count
  from jsonb_array_elements(v_banco_reducido_segunda->'questions') q;
  assert v_count = 3,
    'La segunda partida con banco reducido no debe duplicar pregunta_id';
  select count(*) into v_count
  from jsonb_array_elements(v_banco_reducido_primera->'questions') a
  join jsonb_array_elements(v_banco_reducido_segunda->'questions') b on a->>'id' = b->>'id';
  assert v_count = 3,
    'Una pregunta puede volver a usarse en una partida nueva';

  -- Las variantes semánticas se agrupan sólo dentro de una partida. Las
  -- preguntas sin concepto mantienen el comportamiento previo por pregunta_id.
  update public.preguntas set activo = false;
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial, concepto_id)
  select 'concepto-a-1', id, 'Variante A uno', 'Prueba de concepto', 'publicada', v_concepto_a
  from public.categorias where slug = 'destinos';
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial, concepto_id)
  select 'concepto-a-2', id, 'Variante A dos', 'Prueba de concepto', 'publicada', v_concepto_a
  from public.categorias where slug = 'destinos';
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial, concepto_id)
  select 'concepto-b', id, 'Variante B', 'Prueba de concepto', 'publicada', v_concepto_b
  from public.categorias where slug = 'destinos';
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial)
  select 'concepto-null', id, 'Sin concepto', 'Prueba sin concepto', 'publicada'
  from public.categorias where slug = 'destinos';
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial, concepto_id)
  select 'concepto-colision', c.id, 'Concepto que coincide con una pregunta', 'Prueba de colisión', 'publicada', p.id
  from public.categorias c
  join public.preguntas p on p.codigo_origen = 'concepto-null'
  where c.slug = 'destinos';
  insert into public.respuestas (pregunta_id, texto, es_correcta)
  select id, 'Correcta ' || codigo_origen, true
  from public.preguntas
  where codigo_origen in ('concepto-a-1', 'concepto-a-2', 'concepto-b', 'concepto-null', 'concepto-colision');

  v_conceptos_primera := public.crear_partida('88888888-8888-4888-8888-888888888888');
  assert jsonb_array_length(v_conceptos_primera->'questions') = 4,
    'Dos variantes del mismo concepto deben ocupar un solo lugar en la partida';
  select count(distinct q->>'id') into v_count
  from jsonb_array_elements(v_conceptos_primera->'questions') q;
  assert v_count = 4,
    'La agrupación por concepto conserva preguntas concretas únicas';
  select count(*) into v_count
  from jsonb_array_elements(v_conceptos_primera->'questions') q
  where q->>'concepto_id' = v_concepto_a::text;
  assert v_count = 1,
    'Una partida no debe incluir dos preguntas con el mismo concepto_id';
  assert exists (
    select 1 from jsonb_array_elements(v_conceptos_primera->'questions') q
    where q->>'concepto_id' = v_concepto_b::text
  ), 'Los conceptos diferentes deben poder aparecer en la misma partida';
  assert exists (
    select 1 from jsonb_array_elements(v_conceptos_primera->'questions') q
    where q->>'id' = (select id::text from public.preguntas where codigo_origen = 'concepto-null')
      and q->'concepto_id' = 'null'::jsonb
  ), 'Las preguntas sin concepto_id deben seguir siendo elegibles y exponerse como null';
  select count(*) into v_count
  from jsonb_array_elements(v_conceptos_primera->'questions') q
  join public.preguntas p on p.id::text = q->>'id'
  where p.codigo_origen in ('concepto-null', 'concepto-colision');
  assert v_count = 2,
    'Un concepto_id igual al id de una pregunta sin concepto debe formar dos grupos independientes';

  v_conceptos_segunda := public.crear_partida('88888888-8888-4888-8888-888888888888');
  assert exists (
    select 1 from jsonb_array_elements(v_conceptos_segunda->'questions') q
    where q->>'concepto_id' = v_concepto_a::text
  ), 'Un concepto debe volver a ser elegible al iniciar una nueva partida';

  update public.preguntas set activo = false;
  update public.preguntas
  set activo = true
  where codigo_origen in ('concepto-a-1', 'concepto-a-2');
  v_banco_mismo_concepto := public.crear_partida('99999999-9999-4999-8999-999999999999');
  assert jsonb_array_length(v_banco_mismo_concepto->'questions') = 1,
    'Un banco reducido a un concepto debe devolver una sola pregunta sin bloquearse';

  -- Con exactamente 10 conceptos, las variantes disponibles deben evitar
  -- reconstruir una combinación previa sin cambiar los grupos representados.
  update public.preguntas set activo = false;
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial, concepto_id)
  select format('fallback-%s', n), c.id, format('Fallback %s', n), 'Prueba de variantes', 'publicada',
    case n
      when 1 then '10000000-0000-4000-8000-000000000001'::uuid
      when 2 then '10000000-0000-4000-8000-000000000001'::uuid
      when 3 then '10000000-0000-4000-8000-000000000002'::uuid
      when 4 then '10000000-0000-4000-8000-000000000002'::uuid
      else ('10000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
    end
  from public.categorias c
  cross join generate_series(1, 12) n
  where c.slug = 'destinos';
  insert into public.respuestas (pregunta_id, texto, es_correcta)
  select id, 'Correcta ' || codigo_origen, true
  from public.preguntas
  where codigo_origen like 'fallback-%';

  insert into public.jugadores (player_token)
  values (v_token_variantes)
  returning id into v_jugador_variantes;
  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_variantes, 1, 1)
  returning id into v_partida_variantes_base;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_variantes_base, id, row_number() over (order by codigo_origen)::smallint
  from public.preguntas
  where codigo_origen like 'fallback-%'
    and codigo_origen not in ('fallback-2', 'fallback-4');
  update public.partidas set created_at = now() - interval '2 days'
  where id = v_partida_variantes_base;

  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_variantes, 2, 1)
  returning id into v_partida_variantes_alterna;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_variantes_alterna, id, row_number() over (order by codigo_origen)::smallint
  from public.preguntas
  where codigo_origen like 'fallback-%'
    and codigo_origen not in ('fallback-1', 'fallback-3');
  update public.partidas set created_at = now() - interval '1 day'
  where id = v_partida_variantes_alterna;

  v_regresion_variantes := public.crear_partida(v_token_variantes);
  assert jsonb_array_length(v_regresion_variantes->'questions') = 10,
    'El fallback con variantes debe conservar el tamaño objetivo';
  select count(distinct q->>'id') into v_count
  from jsonb_array_elements(v_regresion_variantes->'questions') q;
  assert v_count = 10,
    'El fallback con variantes no debe repetir pregunta_id';
  select count(distinct p.concepto_id) into v_count
  from jsonb_array_elements(v_regresion_variantes->'questions') q
  join public.preguntas p on p.id::text = q->>'id';
  assert v_count = 10,
    'El fallback con variantes debe conservar una pregunta por concepto';
  assert exists (
    select 1
    from jsonb_array_elements(v_regresion_variantes->'questions') q
    join public.preguntas p on p.id::text = q->>'id'
    where p.codigo_origen in ('fallback-2', 'fallback-4')
  ), 'El fallback debe usar una variante alternativa del mismo concepto';
  select count(*) into v_count
  from jsonb_array_elements(v_regresion_variantes->'questions') q
  join public.partida_preguntas pp
    on pp.partida_id = v_partida_variantes_base and pp.pregunta_id::text = q->>'id';
  assert v_count < 10,
    'El fallback con variantes no debe reconstruir la combinación base previa';
  select count(*) into v_count
  from jsonb_array_elements(v_regresion_variantes->'questions') q
  join public.partida_preguntas pp
    on pp.partida_id = v_partida_variantes_alterna and pp.pregunta_id::text = q->>'id';
  assert v_count < 10,
    'El fallback con variantes no debe reconstruir otra combinación previa';

  -- Si A1 y A2 ya forman las dos combinaciones conocidas, no debe haber bucle.
  -- Al agregar A3, la variante elegida debe producir una combinación nueva.
  update public.preguntas set activo = false;
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial, concepto_id)
  select format('combinacion-%s', n), c.id, format('Combinación %s', n), 'Prueba de combinaciones', 'publicada',
    case n
      when 1 then '20000000-0000-4000-8000-000000000001'::uuid
      when 2 then '20000000-0000-4000-8000-000000000001'::uuid
      else ('20000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
    end
  from public.categorias c
  cross join generate_series(1, 11) n
  where c.slug = 'destinos';
  insert into public.respuestas (pregunta_id, texto, es_correcta)
  select id, 'Correcta ' || codigo_origen, true
  from public.preguntas
  where codigo_origen like 'combinacion-%';

  insert into public.jugadores (player_token)
  values (v_token_combinaciones)
  returning id into v_jugador_combinaciones;
  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_combinaciones, 1, 1)
  returning id into v_partida_combinacion_a1;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_combinacion_a1, id, row_number() over (order by codigo_origen)::smallint
  from public.preguntas
  where codigo_origen like 'combinacion-%' and codigo_origen <> 'combinacion-2';
  update public.partidas set created_at = now() - interval '2 days'
  where id = v_partida_combinacion_a1;

  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_combinaciones, 2, 1)
  returning id into v_partida_combinacion_a2;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_combinacion_a2, id, row_number() over (order by codigo_origen)::smallint
  from public.preguntas
  where codigo_origen like 'combinacion-%' and codigo_origen <> 'combinacion-1';
  update public.partidas set created_at = now() - interval '1 day'
  where id = v_partida_combinacion_a2;

  v_sin_alternativa_nueva := public.crear_partida(v_token_combinaciones);
  assert jsonb_array_length(v_sin_alternativa_nueva->'questions') = 10,
    'Dos combinaciones conocidas sin alternativa nueva no deben bloquear la partida';

  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial, concepto_id)
  select 'combinacion-12', id, 'Combinación 12', 'Tercera variante', 'publicada', '20000000-0000-4000-8000-000000000001'::uuid
  from public.categorias where slug = 'destinos';
  insert into public.respuestas (pregunta_id, texto, es_correcta)
  select id, 'Correcta combinacion-12', true
  from public.preguntas where codigo_origen = 'combinacion-12';
  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_combinaciones, 4, 2)
  returning id into v_partida_combinacion_a3;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_combinacion_a3, id, 1
  from public.preguntas where codigo_origen = 'combinacion-12';
  update public.partidas set created_at = now() - interval '12 hours'
  where id = v_partida_combinacion_a3;

  v_con_alternativa_nueva := public.crear_partida(v_token_combinaciones);
  assert jsonb_array_length(v_con_alternativa_nueva->'questions') = 10,
    'La tercera variante debe conservar el tamaño objetivo';
  select count(distinct q->>'id') into v_count
  from jsonb_array_elements(v_con_alternativa_nueva->'questions') q;
  assert v_count = 10,
    'La tercera variante no debe repetir pregunta_id';
  select count(distinct p.concepto_id) into v_count
  from jsonb_array_elements(v_con_alternativa_nueva->'questions') q
  join public.preguntas p on p.id::text = q->>'id';
  assert v_count = 10,
    'La tercera variante debe conservar una pregunta por concepto';
  assert exists (
    select 1
    from jsonb_array_elements(v_con_alternativa_nueva->'questions') q
    join public.preguntas p on p.id::text = q->>'id'
    where p.codigo_origen = 'combinacion-12'
  ), 'La tercera variante debe producir una combinación no vista';
  select count(*) into v_count
  from jsonb_array_elements(v_con_alternativa_nueva->'questions') q
  join public.partida_preguntas pp
    on pp.partida_id = v_partida_combinacion_a1 and pp.pregunta_id::text = q->>'id';
  assert v_count < 10,
    'La tercera variante no debe reconstruir la combinación A1';
  select count(*) into v_count
  from jsonb_array_elements(v_con_alternativa_nueva->'questions') q
  join public.partida_preguntas pp
    on pp.partida_id = v_partida_combinacion_a2 and pp.pregunta_id::text = q->>'id';
  assert v_count < 10,
    'La tercera variante no debe reconstruir la combinación A2';

  -- #8: la recencia se calcula por la misma clave de grupo que la partida.
  -- Hay diez grupos antiguos y dos grupos de la partida anterior: uno sin
  -- concepto y uno con una variante nunca usada. El banco alcanza con los
  -- grupos antiguos, por lo que los dos recientes deben quedar postergados.
  update public.preguntas set activo = false;
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial)
  select format('prioridad-antigua-%s', n), c.id, format('Antigua %s', n), 'Prueba de recencia', 'publicada'
  from public.categorias c cross join generate_series(1, 10) n
  where c.slug = 'destinos';
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial, concepto_id)
  select codigo, c.id, codigo, 'Prueba de recencia', 'publicada', concepto
  from public.categorias c
  cross join (values
    ('prioridad-concepto-vista', '30000000-0000-4000-8000-000000000001'::uuid),
    ('prioridad-concepto-nueva', '30000000-0000-4000-8000-000000000001'::uuid),
    ('prioridad-null-reciente', null::uuid)
  ) as datos(codigo, concepto)
  where c.slug = 'destinos';
  insert into public.respuestas (pregunta_id, texto, es_correcta)
  select id, 'Correcta ' || codigo_origen, true
  from public.preguntas where codigo_origen like 'prioridad-%';

  insert into public.jugadores (player_token) values (v_token_prioridad)
  returning id into v_jugador_prioridad;
  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_prioridad, 1, 1) returning id into v_partida_prioridad_base;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_prioridad_base, id, row_number() over (order by codigo_origen)::smallint
  from public.preguntas
  where codigo_origen in ('prioridad-concepto-vista', 'prioridad-null-reciente');
  update public.partidas set created_at = now() - interval '1 day'
  where id = v_partida_prioridad_base;

  v_prioridad_reciente := public.crear_partida(v_token_prioridad);
  assert jsonb_array_length(v_prioridad_reciente->'questions') = 10,
    'La prioridad por recencia debe conservar el tamaño objetivo';
  assert not exists (
    select 1 from jsonb_array_elements(v_prioridad_reciente->'questions') q
    join public.preguntas p on p.id::text = q->>'id'
    where p.codigo_origen in ('prioridad-concepto-vista', 'prioridad-concepto-nueva', 'prioridad-null-reciente')
  ), 'Los grupos de la partida anterior, incluido el grupo sin concepto y su variante nueva, deben quedar postergados';

  -- Tres partidas posteriores desplazan esos grupos fuera del horizonte.
  for v_indice in 3..5 loop
    insert into public.partidas (jugador_id, numero_partida, ciclo)
    values (v_jugador_prioridad, v_indice, 1) returning id into v_partida_prioridad_posterior;
    insert into public.partida_preguntas (partida_id, pregunta_id, orden)
    select v_partida_prioridad_posterior, id, 1
    from public.preguntas where codigo_origen = 'prioridad-antigua-1';
  end loop;
  v_prioridad_fuera_horizonte := public.crear_partida(v_token_prioridad);
  assert exists (
    select 1 from jsonb_array_elements(v_prioridad_fuera_horizonte->'questions') q
    join public.preguntas p on p.id::text = q->>'id'
    where p.codigo_origen = 'prioridad-concepto-nueva'
  ), 'Un grupo fuera de las últimas tres partidas debe recuperar prioridad normal';

  -- Con timestamps iguales, numero_partida define de forma estable cuál fue
  -- la partida anterior. Hay nueve alternativas: sólo el grupo de la partida
  -- con número mayor debe recibir la penalización inmediata y quedar fuera.
  update public.preguntas set activo = false;
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial)
  select format('orden-reciente-%s', n), c.id, format('Orden reciente %s', n), 'Prueba de orden', 'publicada'
  from public.categorias c cross join generate_series(1, 11) n
  where c.slug = 'destinos';
  insert into public.respuestas (pregunta_id, texto, es_correcta)
  select id, 'Correcta ' || codigo_origen, true
  from public.preguntas where codigo_origen like 'orden-reciente-%';
  insert into public.jugadores (player_token) values (v_token_orden_reciente)
  returning id into v_jugador_orden_reciente;

  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_orden_reciente, 1, 1) returning id into v_partida_orden_antigua;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_orden_antigua, id, row_number() over (order by codigo_origen)::smallint
  from public.preguntas where codigo_origen like 'orden-reciente-%' and codigo_origen not in ('orden-reciente-10', 'orden-reciente-11');
  update public.partidas set created_at = now() - interval '1 day' where id = v_partida_orden_antigua;

  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_orden_reciente, 2, 1) returning id into v_partida_orden_menor;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_orden_menor, id, 1 from public.preguntas where codigo_origen = 'orden-reciente-10';
  insert into public.partidas (jugador_id, numero_partida, ciclo)
  values (v_jugador_orden_reciente, 3, 1) returning id into v_partida_orden_mayor;
  insert into public.partida_preguntas (partida_id, pregunta_id, orden)
  select v_partida_orden_mayor, id, 1 from public.preguntas where codigo_origen = 'orden-reciente-11';
  update public.partidas set created_at = now()
  where id in (v_partida_orden_menor, v_partida_orden_mayor);

  v_orden_reciente := public.crear_partida(v_token_orden_reciente);
  assert exists (
    select 1 from jsonb_array_elements(v_orden_reciente->'questions') q
    join public.preguntas p on p.id::text = q->>'id'
    where p.codigo_origen = 'orden-reciente-10'
  ), 'Con timestamps iguales, la partida de menor número no debe ser la inmediatamente anterior';
  assert not exists (
    select 1 from jsonb_array_elements(v_orden_reciente->'questions') q
    join public.preguntas p on p.id::text = q->>'id'
    where p.codigo_origen = 'orden-reciente-11'
  ), 'Con timestamps iguales, la partida de mayor número debe recibir la penalización inmediata';

  assert exists (
    select 1
    from pg_constraint
    where conrelid = 'public.partida_preguntas'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (partida_id, pregunta_id)'
  ), 'Debe mantenerse la constraint única de partida_preguntas';
end;
$tests$;

rollback;
