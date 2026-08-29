/* Cliente mínimo para GitHub Pages. Solo consume RPC; no lee tablas. */
const SupabaseGame = (() => {
  const getPlayerToken = () => {
    const { playerTokenStorageKey } = SUPABASE_CONFIG;
    const existing = localStorage.getItem(playerTokenStorageKey);
    if (existing && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(existing)) return existing;
    if (!crypto?.randomUUID) throw new Error('El navegador no admite el identificador seguro requerido.');
    const token = crypto.randomUUID();
    localStorage.setItem(playerTokenStorageKey, token);
    return token;
  };

  const rpc = async (name, body) => {
    const response = await fetch(`${SUPABASE_CONFIG.url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: SUPABASE_CONFIG.publishableKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      console.error(`Supabase RPC ${name} failed`, { status: response.status, payload });
      throw new Error(`RPC ${name} failed`);
    }
    return payload;
  };

  const createGame = () => rpc('crear_partida', { p_player_token: getPlayerToken() });
  const answerQuestion = (partidaId, preguntaId, respuestaId) => rpc('responder_pregunta', {
    p_player_token: getPlayerToken(), p_partida_id: partidaId, p_pregunta_id: preguntaId, p_respuesta_id: respuestaId
  });
  const finishGame = (partidaId) => rpc('finalizar_partida', { p_player_token: getPlayerToken(), p_partida_id: partidaId });

  return { createGame, answerQuestion, finishGame };
})();
