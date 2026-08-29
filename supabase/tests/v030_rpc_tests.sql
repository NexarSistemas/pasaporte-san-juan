-- Ejecutar en una base con las migraciones y seed v0.3.0. Todo queda revertido.
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
begin
  -- Jugador nuevo/existente y dos primeras partidas sin repetición.
  v_primera := public.crear_partida(v_token);
  assert jsonb_array_length(v_primera->'questions') = 10, 'La primera partida debe tener 10 preguntas';
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
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion)
  select 'test-nueva', id, 'Pregunta nueva de prueba', 'Explicación de prueba'
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
    insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion)
    select format('sim-%s', v_indice), id, format('Simulación %s', v_indice), 'Simulación'
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
end;
$tests$;

rollback;
