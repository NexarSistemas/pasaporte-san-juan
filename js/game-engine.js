/* Motor genérico: no contiene contenido ni textos propios de una instancia. */
const GameEngine = (() => {
  const shuffle = (items) => {
    const copy = [...items];
    for (let index = copy.length - 1; index > 0; index -= 1) {
      const randomIndex = Math.floor(Math.random() * (index + 1));
      [copy[index], copy[randomIndex]] = [copy[randomIndex], copy[index]];
    }
    return copy;
  };

  const prepareQuestion = (question) => ({ ...question, answers: shuffle(question.answers) });

  const createGame = (questionBank, settings) => {
    const questions = shuffle(questionBank).slice(0, Math.min(settings.questionsPerGame, questionBank.length)).map(prepareQuestion);
    return { questions, currentIndex: 0, score: 0, streak: 0, maxStreak: 0, correctAnswers: 0, answered: false };
  };

  const getCurrentQuestion = (game) => game.questions[game.currentIndex];
  const isFinished = (game) => game.currentIndex >= game.questions.length;

  const getBonus = (streak, scoring) => {
    const rule = scoring.streakBonuses.find((item) => streak >= item.minStreak);
    return rule ? rule.points : 0;
  };

  const answer = (game, answerId, scoring) => {
    if (game.answered || isFinished(game)) return null;
    const question = getCurrentQuestion(game);
    const selected = question.answers.find((item) => item.id === answerId);
    const correct = selected && selected.id === question.correctAnswer;
    game.answered = true;
    let earned = 0;
    if (correct) {
      game.correctAnswers += 1;
      game.streak += 1;
      game.maxStreak = Math.max(game.maxStreak, game.streak);
      earned = scoring.correctAnswer + getBonus(game.streak, scoring);
      game.score += earned;
    } else {
      game.streak = 0;
    }
    return { correct, earned, correctAnswer: question.correctAnswer, question };
  };

  const next = (game) => {
    if (!game.answered) return false;
    game.currentIndex += 1;
    game.answered = false;
    return !isFinished(game);
  };

  return { createGame, getCurrentQuestion, isFinished, answer, next };
})();
