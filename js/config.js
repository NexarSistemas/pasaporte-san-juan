const GAME_CONFIG = {
  title: 'Pasaporte San Juan',
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
