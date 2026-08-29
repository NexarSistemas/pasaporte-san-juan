(() => {
  const $ = (selector) => document.querySelector(selector);
  const screens = { welcome: $('#welcome-screen'), game: $('#game-screen'), result: $('#result-screen') };
  let game;

  const showScreen = (name) => Object.entries(screens).forEach(([key, element]) => element.classList.toggle('is-hidden', key !== name));
  const getLevel = (correctAnswers) => GAME_CONFIG.resultLevels.find((level) => correctAnswers >= level.minCorrect);

  const renderQuestion = () => {
    const question = GameEngine.getCurrentQuestion(game);
    const total = game.questions.length;
    $('#progress-text').textContent = `${game.currentIndex + 1} de ${total}`;
    $('#score-text').textContent = game.score;
    $('#streak-text').textContent = game.streak;
    $('#progress-bar').style.width = `${((game.currentIndex + 1) / total) * 100}%`;
    $('#category-text').textContent = question.category;
    $('#question-heading').textContent = question.text;
    const hint = $('#hint-text');
    hint.textContent = question.hint || '';
    hint.classList.toggle('is-hidden', !question.hint);
    $('#feedback').className = 'feedback is-hidden';
    $('#next-button').classList.add('is-hidden');
    const answers = $('#answers');
    answers.innerHTML = '';
    question.answers.forEach((answer, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'answer';
      button.dataset.answerId = answer.id;
      button.innerHTML = `<span class="answer-letter" aria-hidden="true">${String.fromCharCode(65 + index)}</span><span>${answer.text}</span>`;
      button.addEventListener('click', () => handleAnswer(answer.id));
      answers.append(button);
    });
    answers.querySelector('button').focus();
  };

  const handleAnswer = (answerId) => {
    const outcome = GameEngine.answer(game, answerId, GAME_CONFIG.scoring);
    if (!outcome) return;
    document.querySelectorAll('.answer').forEach((button) => {
      button.disabled = true;
      const selected = button.dataset.answerId === answerId;
      const correct = button.dataset.answerId === outcome.correctAnswer;
      if (correct) button.classList.add('is-correct');
      if (selected && !outcome.correct) button.classList.add('is-wrong');
      if (selected) button.setAttribute('aria-label', `${button.textContent.trim()}: ${outcome.correct ? 'respuesta correcta' : 'respuesta incorrecta'}`);
    });
    $('#score-text').textContent = game.score;
    $('#streak-text').textContent = game.streak;
    const feedback = $('#feedback');
    feedback.className = `feedback ${outcome.correct ? 'feedback-correct' : 'feedback-wrong'}`;
    const points = outcome.correct ? ` +${outcome.earned} puntos.` : ' La racha vuelve a cero.';
    feedback.innerHTML = `<strong>${outcome.correct ? '¡Respuesta correcta!' : 'No era esa respuesta.'}</strong><p>${outcome.correct ? points : `La respuesta correcta era: <b>${outcome.question.answers.find((item) => item.id === outcome.correctAnswer).text}</b>.${points}`}</p><p>${outcome.question.explanation}</p>`;
    const nextButton = $('#next-button');
    nextButton.classList.remove('is-hidden');
    nextButton.focus();
  };

  const showResult = () => {
    const level = getLevel(game.correctAnswers);
    $('#correct-text').textContent = `${game.correctAnswers}/${game.questions.length}`;
    $('#final-score-text').textContent = game.score;
    $('#max-streak-text').textContent = game.maxStreak;
    $('#result-level').textContent = level.title;
    $('#result-message').textContent = level.message;
    showScreen('result');
    $('#restart-button').focus();
  };

  const startGame = () => {
    game = GameEngine.createGame(QUESTIONS, GAME_CONFIG);
    showScreen('game');
    renderQuestion();
  };

  $('#start-button').addEventListener('click', startGame);
  $('#restart-button').addEventListener('click', startGame);
  $('#next-button').addEventListener('click', () => {
    if (GameEngine.next(game)) renderQuestion();
    else showResult();
  });
})();
