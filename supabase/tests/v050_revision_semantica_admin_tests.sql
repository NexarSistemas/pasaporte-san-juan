-- Ejecutar luego de las migraciones y el seed. Las pruebas se revierten.
begin;

do $tests$
declare
  v_categoria_id uuid;
  v_pregunta_a uuid;
  v_pregunta_b uuid;
  v_pregunta_importada uuid;
  v_concepto uuid;
  v_resultado jsonb;
  v_respuesta_correcta_id uuid;
  v_respuesta_2_id uuid;
  v_respuesta_3_id uuid;
  v_respuesta_4_id uuid;
  v_texto_antes text;
begin
  perform set_config('request.jwt.claim.sub', '12345678-1234-4234-8234-123456789012', true);
  perform set_config('request.jwt.claims', '{"sub":"12345678-1234-4234-8234-123456789012","app_metadata":{"role":"admin"}}', true);
  select id into v_categoria_id from public.categorias order by nombre limit 1;

  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial)
  values ('test-sem-a', v_categoria_id, '¿Cuál es la capital de San Juan?', 'Prueba semántica', 'pendiente')
  returning id into v_pregunta_a;
  insert into public.preguntas (codigo_origen, categoria_id, texto, explicacion, estado_editorial)
  values ('test-sem-b', v_categoria_id, '¿Qué ciudad es la capital de San Juan?', 'Prueba semántica', 'publicada')
  returning id into v_pregunta_b;
  insert into public.respuestas (pregunta_id, texto, es_correcta) values
    (v_pregunta_a, 'San Juan', true), (v_pregunta_a, 'Mendoza', false), (v_pregunta_a, 'La Rioja', false), (v_pregunta_a, 'San Luis', false),
    (v_pregunta_b, 'Ciudad de San Juan', true), (v_pregunta_b, 'Córdoba', false), (v_pregunta_b, 'Salta', false), (v_pregunta_b, 'Neuquén', false);

  select id into v_respuesta_correcta_id from public.respuestas where pregunta_id = v_pregunta_a and es_correcta;
  select id into v_respuesta_2_id from public.respuestas where pregunta_id = v_pregunta_a and not es_correcta order by id limit 1;
  select id into v_respuesta_3_id from public.respuestas where pregunta_id = v_pregunta_a and not es_correcta order by id offset 1 limit 1;
  select id into v_respuesta_4_id from public.respuestas where pregunta_id = v_pregunta_a and not es_correcta order by id offset 2 limit 1;

  -- La edición atómica asigna, modifica y quita concepto_id junto al contenido.
  v_concepto := gen_random_uuid();
  v_resultado := public.actualizar_pregunta_admin(
    v_pregunta_a, v_categoria_id, '¿Cuál es la capital de San Juan?', null, 'Prueba semántica', 'media', null, null, null,
    v_respuesta_correcta_id, 'San Juan', v_respuesta_2_id, 'Mendoza', v_respuesta_3_id, 'La Rioja', v_respuesta_4_id, 'San Luis', v_concepto
  );
  assert (v_resultado->>'concepto_id')::uuid = v_concepto, 'La asignación administrativa debe devolver concepto_id';
  assert (select concepto_id from public.preguntas where id = v_pregunta_a) = v_concepto, 'concepto_id debe quedar persistido';
  v_concepto := gen_random_uuid();
  perform public.actualizar_pregunta_admin(
    v_pregunta_a, v_categoria_id, '¿Cuál es la capital de San Juan?', null, 'Prueba semántica', 'media', null, null, null,
    v_respuesta_correcta_id, 'San Juan', v_respuesta_2_id, 'Mendoza', v_respuesta_3_id, 'La Rioja', v_respuesta_4_id, 'San Luis', v_concepto
  );
  assert (select concepto_id from public.preguntas where id = v_pregunta_a) = v_concepto, 'La edición debe poder modificar concepto_id';
  perform public.actualizar_pregunta_admin(
    v_pregunta_a, v_categoria_id, '¿Cuál es la capital de San Juan?', null, 'Prueba semántica', 'media', null, null, null,
    v_respuesta_correcta_id, 'San Juan', v_respuesta_2_id, 'Mendoza', v_respuesta_3_id, 'La Rioja', v_respuesta_4_id, 'San Luis', null
  );
  assert (select concepto_id from public.preguntas where id = v_pregunta_a) is null, 'Quitar concepto debe restaurar NULL';

  -- El tipo uuid rechaza un valor inválido antes de entrar en la transacción;
  -- por tanto no puede persistirse una edición parcial.
  select texto into v_texto_antes from public.preguntas where id = v_pregunta_a;
  begin
    perform public.actualizar_pregunta_admin(
      v_pregunta_a, v_categoria_id, 'Texto que no debe persistir', null, 'Prueba semántica', 'media', null, null, null,
      v_respuesta_correcta_id, 'San Juan', v_respuesta_2_id, 'Mendoza', v_respuesta_3_id, 'La Rioja', v_respuesta_4_id, 'San Luis', 'concepto-invalido'::uuid
    );
    assert false, 'Un concepto inválido debe fallar';
  exception when invalid_text_representation then null;
  end;
  assert (select texto from public.preguntas where id = v_pregunta_a) = v_texto_antes,
    'Un concepto inválido no puede dejar cambios parciales';

  -- Si ambas preguntas no tienen concepto, la agrupación crea uno y lo asigna
  -- de forma atómica a las dos, sin afectar el estado editorial.
  v_resultado := public.agrupar_preguntas_por_concepto_admin(v_pregunta_a, v_pregunta_b);
  v_concepto := (v_resultado->>'concepto_id')::uuid;
  assert v_concepto is not null, 'La agrupación debe crear un concepto cuando ambos son NULL';
  assert (select count(*) from public.preguntas where id in (v_pregunta_a, v_pregunta_b) and concepto_id = v_concepto) = 2,
    'Ambas preguntas deben compartir el concepto generado';
  assert (select estado_editorial from public.preguntas where id = v_pregunta_b) = 'publicada',
    'Agrupar no debe modificar la publicación existente';
  perform public.asignar_concepto_pregunta_admin(v_pregunta_b, null);
  v_resultado := public.agrupar_preguntas_por_concepto_admin(v_pregunta_a, v_pregunta_b);
  assert (v_resultado->>'concepto_id')::uuid = (select concepto_id from public.preguntas where id = v_pregunta_a),
    'Agrupar debe reutilizar el concepto cuando solo la pregunta seleccionada lo tiene';
  assert (select concepto_id from public.preguntas where id = v_pregunta_b) = (select concepto_id from public.preguntas where id = v_pregunta_a),
    'La candidata sin concepto debe recibir el concepto ya existente';

  -- La importación y publicación previas continúan disponibles con concepto NULL.
  v_resultado := public.importar_pregunta_admin(
    'test-sem-import', v_categoria_id, '¿Qué provincia limita con San Juan al oeste?', null,
    'Prueba de regresión de importación', 'media', null, null,
    'Chile', 'Brasil', 'Uruguay', 'Paraguay'
  );
  v_pregunta_importada := (v_resultado->>'pregunta_id')::uuid;
  assert (select concepto_id from public.preguntas where id = v_pregunta_importada) is null,
    'La importación debe conservar concepto_id nullable';
  v_resultado := public.publicar_pregunta_pendiente_admin(v_pregunta_importada);
  assert (v_resultado->>'ok')::boolean, 'La publicación existente debe seguir funcionando';
end;
$tests$;

rollback;
