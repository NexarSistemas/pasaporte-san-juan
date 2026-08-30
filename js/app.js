(() => {
  const $ = (selector) => document.querySelector(selector);
  const screens = { welcome: $('#welcome-screen'), game: $('#game-screen'), result: $('#result-screen') };
  let game;
  let answerPending = false;
  let nextPending = false;

  const showScreen = (name) => Object.entries(screens).forEach(([key, element]) => element.classList.toggle('is-hidden', key !== name));
  const getLevel = (correctAnswers) => GAME_CONFIG.resultLevels.find((level) => correctAnswers >= level.minCorrect);
  const showConnectionMessage = (message = '') => {
    const element = $('#connection-message');
    element.textContent = message;
    element.classList.toggle('is-hidden', !message);
  };
  const setButtonLoading = (button, loading) => {
    button.disabled = loading;
    if (loading) {
      button.textContent = 'Preparando tu partida…';
    } else if (button.id === 'restart-button') {
      button.innerHTML = 'Jugar nuevamente <span aria-hidden="true">↻</span>';
    } else {
      button.innerHTML = 'Comenzar el viaje <span aria-hidden="true">→</span>';
    }
  };

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
    const media = $('#question-media');
    const image = $('#question-image');
    const mediaContext = $('#question-media-context');
    const contextImage = $('#question-context-image');
    const landscapeFallback = $('#question-fallback-landscape');
    const argentinismosFallback = $('#question-fallback-argentinismos');
    if (question.image) {
      image.src = question.image;
      image.alt = question.imageAlt || `Imagen relacionada con ${question.category}`;
      const contextVisual = question.image.toLowerCase().includes('dique')
        ? { src: 'assets/images/parque-el-leoncito.jpg', alt: 'Paisaje del Parque Nacional El Leoncito' }
        : question.image.toLowerCase().includes('leoncito')
          ? { src: 'assets/images/dique-ullum.jpg', alt: 'Vista del dique y embalse de Ullum' }
          : { src: 'assets/images/dique-ullum.jpg', alt: 'Vista del dique y embalse de Ullum' };
      contextImage.src = contextVisual.src;
      contextImage.alt = contextVisual.alt;
      mediaContext.classList.remove('is-hidden');
      media.classList.remove('is-placeholder');
      landscapeFallback.classList.add('is-hidden');
      argentinismosFallback.classList.add('is-hidden');
    } else {
      image.removeAttribute('src');
      image.alt = '';
      contextImage.removeAttribute('src');
      contextImage.alt = '';
      mediaContext.classList.add('is-hidden');
      media.classList.add('is-placeholder');
      landscapeFallback.classList.toggle('is-hidden', question.category === 'Argentinismos');
      argentinismosFallback.classList.toggle('is-hidden', question.category !== 'Argentinismos');
    }
    const feedback = $('#feedback');
    feedback.className = 'feedback feedback-pending';
    feedback.innerHTML = '<span>Elegí una opción para ver el resultado.</span>';
    const nextButton = $('#next-button');
    nextButton.disabled = true;
    nextButton.textContent = 'Respondé para continuar';
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
    answers.querySelector('button')?.focus();
  };

  const handleAnswer = async (answerId) => {
    if (answerPending || game.answered) return;
    answerPending = true;
    document.querySelectorAll('.answer').forEach((button) => { button.disabled = true; });
    const question = GameEngine.getCurrentQuestion(game);
    try {
      const remoteOutcome = await SupabaseGame.answerQuestion(game.partidaId, question.id, answerId);
      const outcome = GameEngine.answerRemote(game, answerId, remoteOutcome);
      document.querySelectorAll('.answer').forEach((button) => {
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
      feedback.innerHTML = `<strong>${outcome.correct ? '¡Respuesta correcta!' : 'No era esa respuesta.'}</strong><p>${outcome.correct ? points : `La respuesta correcta era: <b>${outcome.correctAnswerText}</b>.${points}`}</p><p>${outcome.question.explanation}</p>`;
      const nextButton = $('#next-button');
      nextButton.disabled = false;
      nextButton.innerHTML = 'Siguiente pregunta <span aria-hidden="true">→</span>';
      nextButton.focus();
    } catch (error) {
      console.error('No se pudo registrar la respuesta', error);
      $('#feedback').className = 'feedback feedback-wrong';
      $('#feedback').innerHTML = '<strong>No pudimos registrar tu respuesta.</strong><p>Revisá tu conexión e intentá nuevamente.</p>';
      document.querySelectorAll('.answer').forEach((button) => { button.disabled = false; });
    } finally {
      answerPending = false;
    }
  };

  const showResult = async () => {
    const nextButton = $('#next-button');
    nextButton.disabled = true;
    nextButton.textContent = 'Guardando resultados…';
    try {
      const finalStats = await SupabaseGame.finishGame(game.partidaId);
      game.score = finalStats.puntaje;
      game.correctAnswers = finalStats.aciertos;
      game.maxStreak = finalStats.racha_maxima;
      const level = getLevel(game.correctAnswers);
      $('#correct-text').textContent = `${game.correctAnswers}/${game.questions.length}`;
      $('#final-score-text').textContent = game.score;
      $('#max-streak-text').textContent = game.maxStreak;
      $('#result-level').textContent = level.title;
      $('#result-message').textContent = level.message;
      showScreen('result');
      $('#restart-button').focus();
    } catch (error) {
      console.error('No se pudo finalizar la partida', error);
      $('#feedback').className = 'feedback feedback-wrong';
      $('#feedback').innerHTML = '<strong>No pudimos guardar los resultados.</strong><p>Intentá finalizar nuevamente.</p>';
      nextButton.disabled = false;
      nextButton.innerHTML = 'Finalizar partida <span aria-hidden="true">→</span>';
    }
  };

  const startGame = async (event) => {
    const button = event.currentTarget;
    setButtonLoading(button, true);
    showConnectionMessage();
    try {
      const partida = await SupabaseGame.createGame();
      game = GameEngine.createRemoteGame(partida);
      if (!game.questions.length) throw new Error('La partida llegó vacía.');
      showScreen('game');
      renderQuestion();
    } catch (error) {
      console.error('No se pudo crear la partida', error);
      showScreen('welcome');
      showConnectionMessage('No pudimos preparar tu partida. Intentá nuevamente.');
    } finally {
      setButtonLoading(button, false);
    }
  };

  $('#start-button').addEventListener('click', startGame);
  $('#restart-button').addEventListener('click', startGame);
  $('#next-button').addEventListener('click', async () => {
    if (nextPending || !game?.answered) return;
    nextPending = true;
    const layout = $('#question-layout');
    const nextButton = $('#next-button');
    nextButton.disabled = true;
    layout.classList.add('is-changing');
    try {
      await new Promise((resolve) => setTimeout(resolve, 180));
      if (GameEngine.next(game)) {
        renderQuestion();
        await new Promise((resolve) => requestAnimationFrame(resolve));
      } else {
        await showResult();
      }
    } finally {
      layout.classList.remove('is-changing');
      nextPending = false;
    }
  });
})();
