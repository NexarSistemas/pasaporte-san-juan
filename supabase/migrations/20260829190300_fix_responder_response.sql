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
