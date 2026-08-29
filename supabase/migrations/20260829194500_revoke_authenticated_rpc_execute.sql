-- El juego no usa Supabase Auth: solo `anon` puede invocar estas RPC públicas.
revoke execute on function public.crear_partida(uuid) from public;
revoke execute on function public.responder_pregunta(uuid, uuid, uuid, uuid) from public;
revoke execute on function public.finalizar_partida(uuid, uuid) from public;
revoke execute on function public.crear_partida(uuid) from authenticated;
revoke execute on function public.responder_pregunta(uuid, uuid, uuid, uuid) from authenticated;
revoke execute on function public.finalizar_partida(uuid, uuid) from authenticated;
grant execute on function public.crear_partida(uuid) to anon;
grant execute on function public.responder_pregunta(uuid, uuid, uuid, uuid) to anon;
grant execute on function public.finalizar_partida(uuid, uuid) to anon;
