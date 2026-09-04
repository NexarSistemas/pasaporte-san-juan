(() => {
  const $ = (selector) => document.querySelector(selector);
  const screens = { welcome: $('#welcome-screen'), game: $('#game-screen'), result: $('#result-screen') };
  let game;
  let answerPending = false;
  let nextPending = false;

  const ILLUSTRATIVE_IMAGES = {
    ischigualasto: {
      src: 'assets/images/ischigualasto-hero.jpg',
      alt: 'Formación rocosa del Parque Provincial Ischigualasto, San Juan',
    },
    leoncito: {
      src: 'assets/images/parque-el-leoncito.jpg',
      alt: 'Paisaje del Parque Nacional El Leoncito, Calingasta',
    },
    ullum: {
      src: 'assets/images/dique-ullum.jpg',
      alt: 'Vista aérea del dique y embalse de Ullum, San Juan',
    },
    general: {
      src: 'assets/images/ischigualasto-hero.jpg',
      alt: 'Paisaje ilustrativo de San Juan',
    },
  };
  const ILLUSTRATIVE_IMAGE_RULES = [
    { keywords: ['ischigualasto', 'valle de la luna'], image: ILLUSTRATIVE_IMAGES.ischigualasto },
    { keywords: ['leoncito', 'pampa del leoncito', 'barreal', 'calingasta'], image: ILLUSTRATIVE_IMAGES.leoncito },
    { keywords: ['ullum', 'dique de ullum', 'punta negra', 'cuesta del viento'], image: ILLUSTRATIVE_IMAGES.ullum },
    { keywords: ['franklin', 'biblioteca franklin'], image: ILLUSTRATIVE_IMAGES.general },
    { keywords: ['bodega', 'vino', 'viñedo', 'viñedos', 'vid'], image: ILLUSTRATIVE_IMAGES.general },
  ];
  const ILLUSTRATIVE_IMAGES_BY_CATEGORY = {
    Naturaleza: ILLUSTRATIVE_IMAGES.leoncito,
    Aventura: ILLUSTRATIVE_IMAGES.leoncito,
    Destinos: ILLUSTRATIVE_IMAGES.ullum,
    Cultura: ILLUSTRATIVE_IMAGES.general,
    Historia: ILLUSTRATIVE_IMAGES.general,
    'Identidad sanjuanina': ILLUSTRATIVE_IMAGES.general,
    Argentinismos: ILLUSTRATIVE_IMAGES.general,
  };
  const GENERAL_ILLUSTRATIVE_IMAGE = ILLUSTRATIVE_IMAGES.general;

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

  const resolveIllustrativeImage = (question) => {
    const searchableText = [question.text, question.hint, question.explanation, question.category]
      .filter(Boolean)
      .join(' ')
      .toLowerCase();
    const matchesKeyword = (keyword) => new RegExp(`(^|\\s)${keyword}(?=\\s|$|[.,;:¿?¡!()])`).test(searchableText);
    const matchedRule = ILLUSTRATIVE_IMAGE_RULES.find(({ keywords }) => keywords.some(matchesKeyword));
    const image = matchedRule?.image || ILLUSTRATIVE_IMAGES_BY_CATEGORY[question.category] || GENERAL_ILLUSTRATIVE_IMAGE;
    return { ...image, isIllustrative: true };
  };

  const renderCategories = (categories) => {
    const list = $('#category-cards');
    list.replaceChildren();
    categories.forEach(({ nombre, icono }) => {
      const item = document.createElement('li');
      item.textContent = `${icono ? `${icono} ` : ''}${nombre}`;
      list.append(item);
    });
  };

  const loadCategories = async () => {
    try {
      renderCategories(await SupabaseGame.listPublicCategories());
    } catch (error) {
      console.error('No se pudieron cargar las categorías', error);
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
    const caption = $('#question-image-caption');
    if (question.image) {
      image.src = question.image;
      image.alt = question.imageAlt || `Imagen relacionada con ${question.category}`;
      media.classList.remove('is-placeholder');
      caption.classList.add('is-hidden');
    } else {
      const illustrativeImage = resolveIllustrativeImage(question);
      image.src = illustrativeImage.src;
      image.alt = illustrativeImage.alt;
      media.classList.add('is-placeholder');
      caption.classList.remove('is-hidden');
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
  loadCategories();
})();
