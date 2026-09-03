const AdminQuestions = (() => {
  const state = { questions: [], selected: null };
  const fields = 'id, categoria_id, texto, texto_original, pista, explicacion, dificultad, fuente, url_fuente, observaciones_revision, estado_editorial, categorias(nombre), respuestas(id, texto, es_correcta)';
  const byId = (id) => document.querySelector(id);
  const optionalValue = (value) => value.trim() || null;
  const categoryName = (question) => Array.isArray(question.categorias) ? question.categorias[0]?.nombre : question.categorias?.nombre;
  const answersFor = (question) => {
    const answers = question.respuestas || [];
    return { correct: answers.find((answer) => answer.es_correcta), incorrect: answers.filter((answer) => !answer.es_correcta) };
  };

  const setMessage = (id, text, success = false) => {
    const element = byId(id);
    element.textContent = text;
    element.classList.toggle('is-success', success);
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
      cell.colSpan = 8;
      cell.textContent = 'No hay preguntas para los filtros seleccionados.';
      const row = document.createElement('tr');
      row.append(cell);
      body.append(row);
      return;
    }
    state.questions.forEach((question) => {
      const row = document.createElement('tr');
      const answers = answersFor(question);
      const status = question.estado_editorial === 'publicada' ? 'Publicada' : 'Pendiente';
      const values = [categoryName(question) || 'Sin categoría', question.texto, answers.correct?.texto || 'Respuesta inválida', answers.incorrect.map((answer) => answer.texto).join(' · ') || 'Respuestas inválidas', question.dificultad, question.fuente || '—', status];
      values.forEach((value, index) => {
        const cell = document.createElement('td');
        cell.textContent = value;
        if (index === 1) cell.className = 'question-cell';
        if (index === 3) cell.className = 'import-other-answers';
        if (index === 6) {
          const tag = document.createElement('span');
          tag.className = 'status';
          tag.textContent = value;
          cell.replaceChildren(tag);
        }
        row.append(cell);
      });
      const action = document.createElement('td');
      const edit = document.createElement('button');
      edit.type = 'button'; edit.className = 'button button-secondary row-button'; edit.textContent = 'Editar';
      edit.addEventListener('click', () => openEditor(question.id));
      action.append(edit);
      if (question.estado_editorial === 'pendiente') {
        const publish = document.createElement('button');
        publish.type = 'button'; publish.className = 'button button-primary row-button'; publish.textContent = 'Publicar';
        publish.addEventListener('click', () => publishQuestion(question.id, publish));
        action.append(document.createTextNode(' '), publish);
      }
      row.append(action);
      body.append(row);
    });
  };

  const loadQuestions = async () => {
    const status = byId('#status-filter').value;
    setMessage('#list-message', `Cargando preguntas ${status === 'publicada' ? 'publicadas' : 'pendientes'}…`);
    let query = AdminAuth.client.from('preguntas').select(fields).eq('estado_editorial', status).order('created_at', { ascending: false });
    const category = byId('#category-filter').value;
    if (category) query = query.eq('categoria_id', category);
    const { data, error } = await query;
    if (error) throw error;
    state.questions = data;
    byId('#questions-count').textContent = `${data.length} pregunta${data.length === 1 ? '' : 's'} ${status === 'publicada' ? 'publicada' : 'pendiente'}${data.length === 1 ? '' : 's'}`;
    renderQuestions();
    setMessage('#list-message', '');
  };

  const openEditor = (id) => {
    const question = state.questions.find((item) => item.id === id);
    const answers = question && answersFor(question);
    if (!question || !answers.correct || answers.incorrect.length !== 3) {
      setMessage('#list-message', 'La pregunta no tiene cuatro respuestas válidas para editar.');
      return;
    }
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
    byId('#url-fuente').value = question.url_fuente || '';
    byId('#observaciones-revision').value = question.observaciones_revision || '';
    byId('#respuesta-correcta').value = answers.correct.texto;
    answers.incorrect.forEach((answer, index) => { byId(`#respuesta-${index + 2}`).value = answer.texto; });
    setMessage('#save-message', '');
    byId('#editor-panel').scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  const saveQuestion = async (event) => {
    event.preventDefault();
    if (!state.selected) return;
    const button = byId('#save-button');
    const answers = answersFor(state.selected);
    button.disabled = true;
    setMessage('#save-message', '');
    try {
      const { data, error } = await AdminAuth.client.rpc('actualizar_pregunta_pendiente_admin', {
        p_pregunta_id: state.selected.id, p_categoria_id: byId('#editor-category').value, p_texto: byId('#texto').value.trim(), p_pista: optionalValue(byId('#pista').value), p_explicacion: byId('#explicacion').value.trim(), p_dificultad: byId('#dificultad').value, p_fuente: optionalValue(byId('#fuente').value), p_url_fuente: optionalValue(byId('#url-fuente').value), p_observaciones_revision: optionalValue(byId('#observaciones-revision').value),
        p_respuesta_correcta_id: answers.correct.id, p_respuesta_correcta: byId('#respuesta-correcta').value.trim(),
        p_respuesta_2_id: answers.incorrect[0].id, p_respuesta_2: byId('#respuesta-2').value.trim(),
        p_respuesta_3_id: answers.incorrect[1].id, p_respuesta_3: byId('#respuesta-3').value.trim(),
        p_respuesta_4_id: answers.incorrect[2].id, p_respuesta_4: byId('#respuesta-4').value.trim()
      });
      if (error || !data?.ok) throw new Error(error?.message || data?.mensaje);
      const selectedId = state.selected.id;
      await loadQuestions();
      openEditor(selectedId);
      setMessage('#save-message', `Cambios guardados. La pregunta continúa ${state.selected.estado_editorial}.`, true);
    } catch (error) {
      setMessage('#save-message', error.message || 'No fue posible guardar los cambios.');
    } finally {
      button.disabled = false;
    }
  };

  const publishQuestion = async (id, button) => {
    if (!window.confirm('La pregunta se publicará y quedará disponible para el juego. ¿Deseás continuar?')) return;
    button.disabled = true;
    setMessage('#list-message', 'Publicando pregunta…');
    try {
      const { data, error } = await AdminAuth.client.rpc('publicar_pregunta_pendiente_admin', { p_pregunta_id: id });
      if (error || !data?.ok) throw new Error(error?.message || data?.mensaje);
      if (state.selected?.id === id) { state.selected = null; byId('#editor-panel').hidden = true; }
      await loadQuestions();
      setMessage('#list-message', 'Pregunta publicada.', true);
    } catch (error) {
      setMessage('#list-message', error.message || 'No fue posible publicar la pregunta.');
    } finally {
      button.disabled = false;
    }
  };

  const init = async () => {
    if (!await AdminAuth.requireAdmin()) return;
    byId('#logout-button').addEventListener('click', async () => { await AdminAuth.signOut(); window.location.replace('index.html'); });
    byId('#category-filter').addEventListener('change', () => loadQuestions().catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas pendientes.')));
    byId('#status-filter').addEventListener('change', () => loadQuestions().catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    byId('#close-editor').addEventListener('click', () => { byId('#editor-panel').hidden = true; state.selected = null; });
    byId('#question-form').addEventListener('submit', saveQuestion);
    try { await loadCategories(); await loadQuestions(); } catch (_) { setMessage('#list-message', 'No fue posible cargar las preguntas pendientes.'); }
  };

  return { init };
})();

document.addEventListener('DOMContentLoaded', () => { AdminQuestions.init(); });
