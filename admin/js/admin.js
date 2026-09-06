const AdminQuestions = (() => {
  const state = { questions: [], selected: null, pendingImage: null, imageUploadInProgress: false, searchDebounce: null, questionsRequest: 0, page: 1, pageSize: 25, totalQuestions: 0 };
  const fields = 'id, categoria_id, texto, texto_original, pista, explicacion, dificultad, fuente, url_fuente, imagen, imagen_alt, observaciones_revision, estado_editorial, concepto_id, categorias(nombre), respuestas(id, texto, es_correcta)';
  const editorialStates = ['pendiente', 'en_revision', 'revisada', 'publicada', 'rechazada'];
  const editorialLabels = { pendiente: 'Pendiente', en_revision: 'En revisión', revisada: 'Revisada', publicada: 'Publicada', rechazada: 'Rechazada' };
  const imageBucket = 'preguntas-imagenes';
  const maxImageBytes = 2 * 1024 * 1024;
  const imageExtensions = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
  const byId = (id) => document.querySelector(id);
  const optionalValue = (value) => value.trim() || null;
  const categoryName = (question) => Array.isArray(question.categorias) ? question.categorias[0]?.nombre : question.categorias?.nombre;
  const answersFor = (question) => {
    const answers = question.respuestas || [];
    return { correct: answers.find((answer) => answer.es_correcta), incorrect: answers.filter((answer) => !answer.es_correcta) };
  };
  const isEditable = (question) => ['pendiente', 'en_revision', 'revisada', 'publicada'].includes(question.estado_editorial);
  const statusLabel = (status) => editorialLabels[status] || status;

  const setMessage = (id, text, success = false) => {
    const element = byId(id);
    element.textContent = text;
    element.classList.toggle('is-success', success);
  };

  const ownStorageObjectPath = (imageUrl) => {
    try {
      const image = new URL(imageUrl);
      const project = new URL(ADMIN_SUPABASE_CONFIG.url);
      const prefix = `/storage/v1/object/public/${imageBucket}/`;
      if (image.origin !== project.origin || !image.pathname.startsWith(prefix)) return null;
      const objectPath = decodeURIComponent(image.pathname.slice(prefix.length));
      return objectPath || null;
    } catch (_) {
      return null;
    }
  };

  const removeStorageObject = async (objectPath) => {
    const { error } = await AdminAuth.client.storage.from(imageBucket).remove([objectPath]);
    if (error) throw error;
  };

  const discardPendingImage = async () => {
    const pendingImage = state.pendingImage;
    if (!pendingImage) return;
    await removeStorageObject(pendingImage.path);
    if (state.pendingImage === pendingImage) state.pendingImage = null;
  };

  const removeAssociatedStorageImage = async (imageUrl) => {
    const objectPath = ownStorageObjectPath(imageUrl);
    if (!objectPath) return false;
    await removeStorageObject(objectPath);
    return true;
  };

  const refreshImageActions = () => {
    const hasImage = Boolean(byId('#imagen').value.trim());
    byId('#replace-image-button').hidden = !hasImage;
    byId('#remove-image-button').hidden = !hasImage;
  };

  const setImageUploadInProgress = (inProgress) => {
    state.imageUploadInProgress = inProgress;
    ['#image-file', '#upload-image-button', '#replace-image-button', '#remove-image-button', '#close-editor', '#save-button']
      .forEach((id) => { byId(id).disabled = inProgress; });
  };

  const renderImagePreview = (source) => {
    const preview = byId('#image-preview');
    const image = byId('#image-preview-image');
    const previewMessage = '#image-preview-message';
    if (!source) {
      image.removeAttribute('src');
      preview.hidden = true;
      setMessage(previewMessage, '');
      refreshImageActions();
      return;
    }
    image.alt = byId('#imagen-alt').value.trim() || 'Vista previa de la imagen de la pregunta';
    image.onload = () => setMessage(previewMessage, '');
    image.onerror = () => setMessage(previewMessage, 'No se pudo cargar la vista previa de la imagen.');
    image.src = source.startsWith('assets/') ? `../${source}` : source;
    preview.hidden = false;
    refreshImageActions();
  };

  const imageFileError = (file) => {
    if (!file) return 'Elegí una imagen para subir.';
    if (!Object.hasOwn(imageExtensions, file.type)) return 'La imagen debe ser JPG, PNG o WebP.';
    if (file.size > maxImageBytes) return 'La imagen supera el máximo de 2 MB.';
    return '';
  };

  const uploadImage = async () => {
    if (!state.selected) return;
    const fileInput = byId('#image-file');
    const file = fileInput.files?.[0];
    const validationError = imageFileError(file);
    if (validationError) {
      setMessage('#image-upload-message', validationError);
      return;
    }
    if (!window.crypto?.randomUUID) {
      setMessage('#image-upload-message', 'El navegador no puede generar un nombre seguro para la imagen.');
      return;
    }
    const objectPath = `preguntas/${state.selected.id}/${window.crypto.randomUUID()}.${imageExtensions[file.type]}`;
    setImageUploadInProgress(true);
    setMessage('#image-upload-message', 'Subiendo imagen…');
    try {
      const previousPending = state.pendingImage;
      if (previousPending) {
        await discardPendingImage();
        if (byId('#imagen').value.trim() === previousPending.publicUrl) {
          byId('#imagen').value = state.selected.imagen || '';
          renderImagePreview(state.selected.imagen || '');
        }
      }
      const storage = AdminAuth.client.storage.from(imageBucket);
      const { data, error } = await storage.upload(objectPath, file, { contentType: file.type, upsert: false });
      if (error) throw error;
      const { data: publicUrlData } = storage.getPublicUrl(data.path);
      if (!publicUrlData?.publicUrl) throw new Error('No fue posible obtener la URL pública de la imagen.');
      state.pendingImage = { path: data.path, publicUrl: publicUrlData.publicUrl };
      byId('#imagen').value = publicUrlData.publicUrl;
      fileInput.value = '';
      renderImagePreview(publicUrlData.publicUrl);
      setMessage('#image-upload-message', 'Imagen subida correctamente. Guardá la pregunta para asociarla.', true);
    } catch (error) {
      setMessage('#image-upload-message', error.message || 'No fue posible subir la imagen.');
    } finally {
      setImageUploadInProgress(false);
    }
  };

  const clearSimilarityReview = () => {
    const result = byId('#similarity-results');
    result.replaceChildren();
    result.hidden = true;
    setMessage('#similarity-message', '');
  };

  const loadCategories = async () => {
    const { data, error } = await AdminAuth.client.from('categorias').select('id, nombre').order('nombre');
    if (error) throw error;
    data.forEach((category) => {
      ['#category-filter', '#editor-category'].forEach((id) => {
        const option = document.createElement('option');
        option.value = category.id;
        option.textContent = category.nombre;
        byId(id).append(option);
      });
    });
  };

  const renderQuestions = () => {
    const body = byId('#questions-body');
    body.replaceChildren();
    if (!state.questions.length) {
      const cell = document.createElement('td');
      cell.colSpan = 9;
      cell.textContent = 'No hay preguntas para los filtros seleccionados.';
      const row = document.createElement('tr');
      row.append(cell);
      body.append(row);
      return;
    }
    state.questions.forEach((question) => {
      const row = document.createElement('tr');
      const answers = answersFor(question);
      const status = statusLabel(question.estado_editorial);
      const values = [categoryName(question) || 'Sin categoría', question.texto, answers.correct?.texto || 'Respuesta inválida', answers.incorrect.map((answer) => answer.texto).join(' · ') || 'Respuestas inválidas', question.concepto_id || '—', question.dificultad, question.fuente || '—', status];
      values.forEach((value, index) => {
        const cell = document.createElement('td');
        cell.textContent = value;
        if (index === 1) cell.className = 'question-cell';
        if (index === 3) cell.className = 'import-other-answers';
        if (index === 7) {
          const tag = document.createElement('span');
          tag.className = `status status-${question.estado_editorial}`;
          tag.textContent = value;
          cell.replaceChildren(tag);
        }
        row.append(cell);
      });
      const action = document.createElement('td');
      if (isEditable(question)) {
        const edit = document.createElement('button');
        edit.type = 'button'; edit.className = 'button button-secondary row-button'; edit.textContent = 'Editar';
        edit.addEventListener('click', () => openEditor(question.id));
        action.append(edit);
      }
      const transitionActions = {
        pendiente: [['en_revision', 'Enviar a revisión', 'button-secondary'], ['rechazada', 'Rechazar', 'button-secondary']],
        en_revision: [['revisada', 'Marcar revisada', 'button-primary'], ['rechazada', 'Rechazar', 'button-secondary']],
        revisada: [['publicada', 'Publicar', 'button-primary'], ['en_revision', 'Devolver a revisión', 'button-secondary'], ['rechazada', 'Rechazar', 'button-secondary']],
        publicada: [['en_revision', 'Reabrir revisión', 'button-secondary']],
        rechazada: [['en_revision', 'Reabrir revisión', 'button-secondary']]
      };
      transitionActions[question.estado_editorial].forEach(([destination, label, className]) => {
        const transition = document.createElement('button');
        transition.type = 'button'; transition.className = `button ${className} row-button`; transition.textContent = label;
        transition.addEventListener('click', () => changeEditorialState(question.id, destination, transition));
        if (action.childElementCount) action.append(document.createTextNode(' '));
        action.append(transition);
      });
      if (question.estado_editorial !== 'rechazada') {
        const review = document.createElement('button');
        review.type = 'button'; review.className = 'button button-secondary row-button'; review.textContent = 'Revisar similitud';
        review.addEventListener('click', () => { openEditor(question.id); reviewSimilarity(); });
        if (action.childElementCount) action.append(document.createTextNode(' '));
        action.append(review);
      }
      row.append(action);
      body.append(row);
    });
  };

  const totalPages = () => Math.max(1, Math.ceil(state.totalQuestions / state.pageSize));

  const renderPagination = () => {
    const first = state.totalQuestions ? ((state.page - 1) * state.pageSize) + 1 : 0;
    const last = state.totalQuestions ? Math.min(first + state.questions.length - 1, state.totalQuestions) : 0;
    byId('#questions-range').textContent = `${first}–${last} de ${state.totalQuestions}`;
    const onFirstPage = state.page === 1;
    const onLastPage = state.page === totalPages();
    byId('#first-page').disabled = onFirstPage;
    byId('#previous-page').disabled = onFirstPage;
    byId('#next-page').disabled = onLastPage;
    byId('#last-page').disabled = onLastPage;
  };

  const loadQuestions = async () => {
    const request = ++state.questionsRequest;
    const filters = {
      status: byId('#status-filter').value,
      category: byId('#category-filter').value,
      text: byId('#text-filter').value.trim()
    };
    setMessage('#list-message', 'Cargando preguntas…');
    const from = (state.page - 1) * state.pageSize;
    let query = AdminAuth.client.from('preguntas').select(fields, { count: 'exact' }).order('created_at', { ascending: false }).order('id', { ascending: false });
    if (filters.status) query = query.eq('estado_editorial', filters.status);
    if (filters.category) query = query.eq('categoria_id', filters.category);
    if (filters.text) query = query.ilike('texto', `%${filters.text}%`);
    const { data, error, count } = await query.range(from, from + state.pageSize - 1);
    if (request !== state.questionsRequest) return false;
    if (error) throw error;
    state.totalQuestions = count || 0;
    if (state.page > totalPages()) {
      state.page = totalPages();
      return loadQuestions();
    }
    state.questions = data || [];
    byId('#questions-count').textContent = `${state.totalQuestions} pregunta${state.totalQuestions === 1 ? '' : 's'} para los filtros seleccionados`;
    renderQuestions();
    renderPagination();
    setMessage('#list-message', '');
    return true;
  };

  const resetQuestionsPage = () => {
    state.page = 1;
    return loadQuestions();
  };

  const goToPage = async (page) => {
    const previousPage = state.page;
    state.page = Math.min(Math.max(page, 1), totalPages());
    try {
      return await loadQuestions();
    } catch (error) {
      state.page = previousPage;
      throw error;
    }
  };

  const syncStickyHeaderOffset = () => {
    document.documentElement.style.setProperty('--topbar-height', `${document.querySelector('.topbar').offsetHeight}px`);
  };

  const loadStatusSummary = async () => {
    const results = await Promise.all(editorialStates.map(async (status) => {
      const { count, error } = await AdminAuth.client.from('preguntas')
        .select('*', { count: 'exact', head: true })
        .eq('estado_editorial', status);
      if (error) throw error;
      return [status, count || 0];
    }));
    results.forEach(([status, count]) => {
      byId(`#status-count-${status}`).textContent = count;
    });
  };

  const openEditor = (id) => {
    if (state.pendingImage && state.selected?.id !== id) {
      setMessage('#list-message', 'Guardá o cerrá la pregunta actual antes de editar otra imagen pendiente.');
      return;
    }
    const question = state.questions.find((item) => item.id === id);
    const answers = question && answersFor(question);
    if (question && !isEditable(question)) {
      setMessage('#list-message', `Las preguntas ${statusLabel(question.estado_editorial).toLocaleLowerCase('es-AR')} se conservan visibles, pero no están habilitadas para edición en este flujo.`);
      return;
    }
    if (!question || !answers.correct || answers.incorrect.length !== 3) {
      setMessage('#list-message', 'La pregunta no tiene cuatro respuestas válidas para editar.');
      return;
    }
    clearSimilarityReview();
    state.selected = question;
    byId('#editor-panel').hidden = false;
    byId('#editor-meta').textContent = `${categoryName(question) || 'Sin categoría'} · Estado: ${question.estado_editorial}`;
    byId('#editor-category').value = question.categoria_id;
    byId('#texto').value = question.texto || '';
    byId('#texto-original').value = question.texto_original || 'Sin texto original registrado.';
    byId('#pista').value = question.pista || '';
    byId('#explicacion').value = question.explicacion || '';
    byId('#dificultad').value = question.dificultad;
    byId('#fuente').value = question.fuente || '';
    byId('#concepto-id').value = question.concepto_id || '';
    byId('#url-fuente').value = question.url_fuente || '';
    byId('#imagen').value = question.imagen || '';
    byId('#imagen-alt').value = question.imagen_alt || '';
    byId('#image-file').value = '';
    setMessage('#image-upload-message', '');
    renderImagePreview(question.imagen || '');
    byId('#observaciones-revision').value = question.observaciones_revision || '';
    byId('#respuesta-correcta').value = answers.correct.texto;
    answers.incorrect.forEach((answer, index) => { byId(`#respuesta-${index + 2}`).value = answer.texto; });
    setMessage('#save-message', '');
    byId('#editor-panel').scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  const candidateView = (candidate, reviewedQuestionId) => {
    const answers = answersFor(candidate);
    const container = document.createElement('article');
    container.className = 'similarity-candidate';
    const title = document.createElement('h4');
    title.textContent = candidate.texto;
    const meta = document.createElement('p');
    meta.className = 'similarity-meta';
    meta.textContent = `${categoryName(candidate) || 'Sin categoría'} · ${statusLabel(candidate.estado_editorial)} · Concepto: ${candidate.concepto_id || 'sin asignar'}`;
    const answer = document.createElement('p');
    answer.textContent = `Respuesta correcta: ${answers.correct?.texto || 'Sin respuesta válida'}`;
    const score = document.createElement('p');
    score.className = 'similarity-score';
    score.textContent = `${SimilarityReview.labelFor(candidate.score)} · ${candidate.score}%`;
    container.append(title, meta, answer, score);
    const actions = document.createElement('div');
    actions.className = 'similarity-actions';
    if (!isEditable(candidate)) {
      const unavailable = document.createElement('p');
      unavailable.className = 'similarity-meta';
      unavailable.textContent = 'Sin acciones disponibles para este estado editorial.';
      container.append(unavailable);
    } else if (candidate.concepto_id) {
      const reuse = document.createElement('button');
      reuse.type = 'button'; reuse.className = 'button button-secondary'; reuse.textContent = 'Reutilizar concepto';
      reuse.addEventListener('click', () => assignConcept(candidate.concepto_id, reviewedQuestionId)
        .catch((error) => setMessage('#similarity-message', error.message || 'No fue posible reutilizar el concepto.')));
      actions.append(reuse);
    } else {
      const group = document.createElement('button');
      group.type = 'button'; group.className = 'button button-secondary'; group.textContent = 'Agrupar como variante';
      group.addEventListener('click', () => groupQuestions(candidate.id, reviewedQuestionId));
      actions.append(group);
    }
    if (actions.childElementCount) container.append(actions);
    return container;
  };

  const reviewSimilarity = async () => {
    if (!state.selected) return;
    const reviewedQuestionId = state.selected.id;
    const result = byId('#similarity-results');
    setMessage('#similarity-message', 'Buscando coincidencias…');
    result.hidden = true; result.replaceChildren();
    try {
      const { data, error } = await AdminAuth.client.from('preguntas').select(fields).order('created_at', { ascending: false });
      if (error) throw error;
      if (!SimilarityReview.isCurrentReview(reviewedQuestionId, state.selected?.id)) return;
      const selectedAnswers = answersFor(state.selected);
      const candidates = SimilarityReview.rankCandidates(
        { ...state.selected, correctAnswer: selectedAnswers.correct?.texto || '' },
        data.map((candidate) => ({ ...candidate, correctAnswer: answersFor(candidate).correct?.texto || '' }))
      );
      if (!candidates.length) {
        setMessage('#similarity-message', 'Sin coincidencias relevantes. La decisión editorial sigue siendo manual.', true);
        return;
      }
      candidates.forEach((candidate) => result.append(candidateView(candidate, reviewedQuestionId)));
      result.hidden = false;
      setMessage('#similarity-message', `${candidates.length} coincidencia${candidates.length === 1 ? '' : 's'} relevante${candidates.length === 1 ? '' : 's'}; revisá el contenido antes de decidir.`, true);
    } catch (error) {
      setMessage('#similarity-message', error.message || 'No fue posible revisar similitud.');
    }
  };

  const assignConcept = async (conceptId, reviewedQuestionId) => {
    if (!state.selected || !SimilarityReview.isCurrentReview(reviewedQuestionId, state.selected.id)) {
      throw new Error('La revisión ya no corresponde a la pregunta abierta. Volvé a revisar similitud.');
    }
    const { data, error } = await AdminAuth.client.rpc('asignar_concepto_pregunta_admin', { p_pregunta_id: state.selected.id, p_concepto_id: conceptId || null });
    if (error || !data?.ok) throw new Error(error?.message || data?.mensaje);
    state.selected.concepto_id = data.concepto_id;
    byId('#concepto-id').value = data.concepto_id || '';
    await Promise.all([loadQuestions(), loadStatusSummary()]);
    setMessage('#save-message', data.mensaje, true);
  };

  const groupQuestions = async (candidateId, reviewedQuestionId) => {
    if (!state.selected || !SimilarityReview.isCurrentReview(reviewedQuestionId, state.selected.id)) {
      setMessage('#similarity-message', 'La revisión ya no corresponde a la pregunta abierta. Volvé a revisar similitud.');
      return;
    }
    try {
      const { data, error } = await AdminAuth.client.rpc('agrupar_preguntas_por_concepto_admin', { p_pregunta_id: state.selected.id, p_candidata_id: candidateId });
      if (error || !data?.ok) throw new Error(error?.message || data?.mensaje);
      state.selected.concepto_id = data.concepto_id;
      byId('#concepto-id').value = data.concepto_id;
      await Promise.all([loadQuestions(), loadStatusSummary()]);
      setMessage('#similarity-message', data.mensaje, true);
      await reviewSimilarity();
    } catch (error) {
      setMessage('#similarity-message', error.message || 'No fue posible agrupar las preguntas.');
    }
  };

  const saveQuestionChanges = async ({ skipImageRemovalConfirmation = false } = {}) => {
    if (!state.selected) return;
    if (state.imageUploadInProgress) {
      setMessage('#save-message', 'Esperá a que termine la subida de la imagen.');
      return false;
    }
    const button = byId('#save-button');
    const selectedQuestion = state.selected;
    const answers = answersFor(selectedQuestion);
    const requestedConceptId = byId('#concepto-id').value.trim() || null;
    const image = optionalValue(byId('#imagen').value);
    const imageAlt = optionalValue(byId('#imagen-alt').value);
    if (selectedQuestion.imagen && !image && !skipImageRemovalConfirmation
      && !window.confirm('¿Querés quitar la imagen de esta pregunta?')) {
      return false;
    }
    if (image && !imageAlt) {
      setMessage('#save-message', 'Agregá un texto alternativo para la imagen antes de guardar.');
      byId('#imagen-alt').focus();
      return false;
    }
    const pendingImage = state.pendingImage;
    const savesPendingImage = pendingImage?.publicUrl === image;
    if (pendingImage && !savesPendingImage) {
      try {
        await discardPendingImage();
      } catch (error) {
        setMessage('#save-message', error.message || 'No fue posible eliminar la imagen pendiente.');
        return false;
      }
    }
    button.disabled = true;
    setMessage('#save-message', '');
    try {
      const { data, error } = await AdminAuth.client.rpc('actualizar_pregunta_admin', {
        p_pregunta_id: selectedQuestion.id, p_categoria_id: byId('#editor-category').value, p_texto: byId('#texto').value.trim(), p_pista: optionalValue(byId('#pista').value), p_explicacion: byId('#explicacion').value.trim(), p_dificultad: byId('#dificultad').value, p_fuente: optionalValue(byId('#fuente').value), p_url_fuente: optionalValue(byId('#url-fuente').value), p_observaciones_revision: optionalValue(byId('#observaciones-revision').value),
        p_respuesta_correcta_id: answers.correct.id, p_respuesta_correcta: byId('#respuesta-correcta').value.trim(),
        p_respuesta_2_id: answers.incorrect[0].id, p_respuesta_2: byId('#respuesta-2').value.trim(),
        p_respuesta_3_id: answers.incorrect[1].id, p_respuesta_3: byId('#respuesta-3').value.trim(),
        p_respuesta_4_id: answers.incorrect[2].id, p_respuesta_4: byId('#respuesta-4').value.trim(),
        p_concepto_id: requestedConceptId, p_imagen: image, p_imagen_alt: imageAlt
      });
      if (error || !data?.ok) throw new Error(error?.message || data?.mensaje);
      if (savesPendingImage) state.pendingImage = null;
      let cleanupError = '';
      if (selectedQuestion.imagen && selectedQuestion.imagen !== image) {
        try {
          await removeAssociatedStorageImage(selectedQuestion.imagen);
        } catch (error) {
          cleanupError = error.message || 'No fue posible eliminar la imagen anterior de Storage.';
        }
      }
      const selectedId = selectedQuestion.id;
      await Promise.all([loadQuestions(), loadStatusSummary()]);
      openEditor(selectedId);
      setMessage('#save-message', cleanupError || `Cambios guardados. La pregunta continúa ${state.selected.estado_editorial}.`, !cleanupError);
      return true;
    } catch (error) {
      setMessage('#save-message', error.message || 'No fue posible guardar los cambios.');
      return false;
    } finally {
      button.disabled = false;
    }
  };

  const saveQuestion = (event) => {
    event.preventDefault();
    saveQuestionChanges();
  };

  const replaceImage = () => {
    const fileInput = byId('#image-file');
    fileInput.value = '';
    fileInput.click();
    setMessage('#image-upload-message', 'Elegí una imagen y presioná “Subir imagen”.');
  };

  const removeImage = async () => {
    if (!state.selected || (!byId('#imagen').value.trim() && !state.pendingImage)) return;
    if (state.imageUploadInProgress) {
      setMessage('#save-message', 'Esperá a que termine la subida de la imagen.');
      return;
    }
    if (!window.confirm('¿Querés quitar la imagen de esta pregunta?')) return;
    const button = byId('#remove-image-button');
    button.disabled = true;
    try {
      await discardPendingImage();
      byId('#imagen').value = '';
      byId('#imagen-alt').value = '';
      renderImagePreview('');
      await saveQuestionChanges({ skipImageRemovalConfirmation: true });
    } catch (error) {
      setMessage('#save-message', error.message || 'No fue posible quitar la imagen pendiente.');
    } finally {
      button.disabled = false;
    }
  };

  const closeEditor = async () => {
    if (state.imageUploadInProgress) {
      setMessage('#save-message', 'Esperá a que termine la subida de la imagen.');
      return;
    }
    const button = byId('#close-editor');
    button.disabled = true;
    try {
      await discardPendingImage();
      clearSimilarityReview();
      byId('#editor-panel').hidden = true;
      state.selected = null;
    } catch (error) {
      setMessage('#save-message', error.message || 'No fue posible eliminar la imagen pendiente.');
    } finally {
      button.disabled = false;
    }
  };

  const changeEditorialState = async (id, destination, button) => {
    const destinationLabel = statusLabel(destination).toLocaleLowerCase('es-AR');
    if (destination === 'publicada' && !window.confirm('La pregunta se publicará y quedará disponible para el juego. ¿Deseás continuar?')) return;
    button.disabled = true;
    setMessage('#list-message', `Actualizando estado a ${destinationLabel}…`);
    try {
      const { data, error } = await AdminAuth.client.rpc('cambiar_estado_editorial_pregunta_admin', { p_pregunta_id: id, p_estado_destino: destination });
      if (error || !data?.ok) throw new Error(error?.message || data?.mensaje);
      await Promise.all([loadQuestions(), loadStatusSummary()]);
      if (state.selected?.id === id) {
        if (destination === 'rechazada' || !state.questions.some((question) => question.id === id)) {
          state.selected = null; byId('#editor-panel').hidden = true;
        } else openEditor(id);
      }
      setMessage('#list-message', data.mensaje, true);
    } catch (error) {
      setMessage('#list-message', error.message || 'No fue posible actualizar el estado editorial.');
    } finally {
      button.disabled = false;
    }
  };

  const init = async () => {
    if (!await AdminAuth.requireAdmin()) return;
    syncStickyHeaderOffset();
    window.addEventListener('resize', syncStickyHeaderOffset);
    byId('#logout-button').addEventListener('click', async () => { await AdminAuth.signOut(); window.location.replace('index.html'); });
    byId('#category-filter').addEventListener('change', () => resetQuestionsPage().catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    byId('#status-filter').addEventListener('change', () => resetQuestionsPage().catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    byId('#text-filter').addEventListener('input', () => {
      window.clearTimeout(state.searchDebounce);
      state.searchDebounce = window.setTimeout(() => {
        resetQuestionsPage().catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.'));
      }, 250);
    });
    byId('#page-size').addEventListener('change', () => {
      state.pageSize = Number(byId('#page-size').value);
      resetQuestionsPage().catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.'));
    });
    byId('#first-page').addEventListener('click', () => goToPage(1).catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    byId('#previous-page').addEventListener('click', () => goToPage(state.page - 1).catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    byId('#next-page').addEventListener('click', () => goToPage(state.page + 1).catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    byId('#last-page').addEventListener('click', () => goToPage(totalPages()).catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    document.addEventListener('admin:questions-changed', () => {
      Promise.all([resetQuestionsPage(), loadStatusSummary()]).catch(() => setMessage('#list-message', 'No fue posible actualizar las preguntas.'));
    });
    byId('#close-editor').addEventListener('click', closeEditor);
    byId('#question-form').addEventListener('submit', saveQuestion);
    byId('#imagen').addEventListener('input', () => renderImagePreview(byId('#imagen').value.trim()));
    byId('#imagen-alt').addEventListener('input', () => {
      const preview = byId('#image-preview-image');
      if (preview.getAttribute('src')) preview.alt = byId('#imagen-alt').value.trim() || 'Vista previa de la imagen de la pregunta';
    });
    byId('#upload-image-button').addEventListener('click', uploadImage);
    byId('#replace-image-button').addEventListener('click', replaceImage);
    byId('#remove-image-button').addEventListener('click', removeImage);
    byId('#review-similarity-button').addEventListener('click', () => reviewSimilarity());
    try { await loadCategories(); await Promise.all([loadQuestions(), loadStatusSummary()]); } catch (_) { setMessage('#list-message', 'No fue posible cargar las preguntas.'); }
  };

  return { init };
})();

document.addEventListener('DOMContentLoaded', () => { AdminQuestions.init(); });
