const GAME_CONFIG = {
  title: 'Pasaporte San Juan',
  version: '0.6.0',
  questionsPerGame: 10,
  scoring: {
    correctAnswer: 100,
    streakBonuses: [
      { minStreak: 4, points: 100 },
      { minStreak: 2, points: 50 }
    ]
  },
  resultLevels: [
    { minCorrect: 9, title: 'Guía experto de San Juan', message: 'Conocés la provincia como quien ya recorrió cada rincón.' },
    { minCorrect: 7, title: 'Explorador sanjuanino', message: 'Tu curiosidad te llevó muy lejos. ¡Seguí explorando!' },
    { minCorrect: 5, title: 'Turista curioso', message: 'Vas por buen camino: cada pregunta es una nueva parada.' },
    { minCorrect: 0, title: 'Viajero en entrenamiento', message: 'Todo gran viaje empieza con el primer paso. ¡Intentá de nuevo!' }
  ]
};

// Los mensajes mensuales rotan de forma determinística según el día del mes.
const PRESENTATION_CONFIG = {
  defaultBadge: 'Descubrí San Juan',
  monthEvents: { 6: ['Mes de la Fundación'], 9: ['Mes del Turismo', 'Mes del Maestro'] },
  specialEvents: { '6-13': 'Feliz Día San Juan', '9-11': 'Día del Maestro', '9-27': 'Día del Turismo' }
};

// Una publishable key está diseñada para estar en el navegador. El acceso a
// datos depende de RLS y de las RPC, no del secreto de esta clave.
const SUPABASE_CONFIG = {
  url: 'https://xffndejkcvsnvozeswbk.supabase.co',
  publishableKey: 'sb_publishable_4ccM1EMSzxn7Agt8pjNqdA_Ge8hkEhN',
  playerTokenStorageKey: 'pasaporte-san-juan.player-token.v1'
};
