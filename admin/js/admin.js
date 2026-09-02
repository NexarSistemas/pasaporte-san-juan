const AdminQuestions = (() => {
  const state = { questions: [], selected: null };
  const fields = 'id, categoria_id, texto, texto_original, pista, explicacion, dificultad, activo, fuente, url_fuente, observaciones_revision, estado_editorial, revisado_at, publicado_at, categorias(nombre)';
  const statusLabel = { borrador: 'Borrador', en_revision: 'En revisión', revisada: 'Revisada', publicada: 'Publicada' };

  const byId = (id) => document.querySelector(id);
  const optionalValue = (value) => value.trim() || null;
  const categoryName = (question) => Array.isArray(question.categorias) ? question.categorias[0]?.nombre : question.categorias?.nombre;

  const setMessage = (id, text, success = false) => {
    const element = byId(id);
    element.textContent = text;
    element.classList.toggle('is-success', success);
  };

  const loadCategories = async () => {
    const { data, error } = await AdminAuth.client.from('categorias').select('id, nombre').order('nombre');
    if (error) throw error;
    const select = byId('#category-filter');
    data.forEach((category) => {
      const option = document.createElement('option');
      option.value = category.id;
      option.textContent = category.nombre;
      select.append(option);
    });
  };

  const renderQuestions = () => {
    const body = byId('#questions-body');
    body.replaceChildren();
    if (!state.questions.length) {
      const cell = document.createElement('td');
      cell.colSpan = 6;
      cell.textContent = 'No hay preguntas para los filtros seleccionados.';
      const row = document.createElement('tr');
      row.append(cell);
      body.append(row);
      return;
    }

    state.questions.forEach((question) => {
      const row = document.createElement('tr');
      const values = [categoryName(question) || 'Sin categoría', question.texto, question.dificultad, question.activo ? 'Sí' : 'No', statusLabel[question.estado_editorial] || question.estado_editorial || 'Sin estado'];
      values.forEach((value, index) => {
        const cell = document.createElement('td');
        cell.textContent = value;
        if (index === 1) cell.className = 'question-cell';
        if (index === 3 || index === 4) {
          const tag = document.createElement('span');
          tag.className = `status${index === 3 && !question.activo ? ' inactive' : ''}`;
          tag.textContent = value;
          cell.replaceChildren(tag);
        }
        row.append(cell);
      });
      const action = document.createElement('td');
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'button button-secondary row-button';
      button.textContent = 'Editar';
      button.addEventListener('click', () => openEditor(question.id));
      action.append(button);
      row.append(action);
      body.append(row);
    });
  };

  const loadQuestions = async () => {
    setMessage('#list-message', 'Cargando preguntas…');
    let query = AdminAuth.client.from('preguntas').select(fields).order('created_at', { ascending: false });
    const category = byId('#category-filter').value;
    const status = byId('#status-filter').value;
    if (category) query = query.eq('categoria_id', category);
    if (status) query = query.eq('estado_editorial', status);
    const { data, error } = await query;
    if (error) throw error;
    state.questions = data;
    byId('#questions-count').textContent = `${data.length} pregunta${data.length === 1 ? '' : 's'}`;
    renderQuestions();
    setMessage('#list-message', '');
  };

  const openEditor = (id) => {
    const question = state.questions.find((item) => item.id === id);
    if (!question) return;
    state.selected = question;
    byId('#editor-panel').hidden = false;
    byId('#editor-meta').textContent = `${categoryName(question) || 'Sin categoría'} · Activa: ${question.activo ? 'sí' : 'no'}`;
    byId('#texto').value = question.texto || '';
    byId('#texto-original').value = question.texto_original || 'Sin texto original registrado.';
    byId('#pista').value = question.pista || '';
    byId('#explicacion').value = question.explicacion || '';
    byId('#dificultad').value = question.dificultad;
    byId('#estado-editorial').value = question.estado_editorial || 'borrador';
    byId('#fuente').value = question.fuente || '';
    byId('#url-fuente').value = question.url_fuente || '';
    byId('#observaciones-revision').value = question.observaciones_revision || '';
    setMessage('#save-message', '');
    byId('#editor-panel').scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  const saveQuestion = async (event) => {
    event.preventDefault();
    if (!state.selected) return;
    const form = event.currentTarget;
    const button = byId('#save-button');
    const nextStatus = form.estado_editorial.value;
    const updates = {
      texto: form.texto.value.trim(),
      pista: optionalValue(form.pista.value),
      explicacion: form.explicacion.value.trim(),
      dificultad: form.dificultad.value,
      fuente: optionalValue(form.fuente.value),
      url_fuente: optionalValue(form.url_fuente.value),
      observaciones_revision: optionalValue(form.observaciones_revision.value),
      estado_editorial: nextStatus
    };
    if (nextStatus === 'revisada' && state.selected.estado_editorial !== 'revisada') updates.revisado_at = new Date().toISOString();
    if (nextStatus === 'publicada' && state.selected.estado_editorial !== 'publicada') updates.publicado_at = new Date().toISOString();

    button.disabled = true;
    setMessage('#save-message', '');
    try {
      const { data, error } = await AdminAuth.client.from('preguntas').update(updates).eq('id', state.selected.id).select(fields).single();
      if (error) throw error;
      state.questions = state.questions.map((question) => question.id === data.id ? data : question);
      state.selected = data;
      renderQuestions();
      openEditor(data.id);
      setMessage('#save-message', 'Cambios guardados.', true);
    } catch (_) {
      setMessage('#save-message', 'No fue posible guardar los cambios.');
    } finally {
      button.disabled = false;
    }
  };

  const init = async () => {
    if (!await AdminAuth.requireAdmin()) return;
    byId('#logout-button').addEventListener('click', async () => {
      await AdminAuth.signOut();
      window.location.replace('index.html');
    });
    byId('#category-filter').addEventListener('change', () => loadQuestions().catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    byId('#status-filter').addEventListener('change', () => loadQuestions().catch(() => setMessage('#list-message', 'No fue posible cargar las preguntas.')));
    byId('#close-editor').addEventListener('click', () => { byId('#editor-panel').hidden = true; state.selected = null; });
    byId('#question-form').addEventListener('submit', saveQuestion);
    try {
      await loadCategories();
      await loadQuestions();
    } catch (_) {
      setMessage('#list-message', 'No fue posible cargar las preguntas.');
    }
  };

  return { init };
})();

document.addEventListener('DOMContentLoaded', () => { AdminQuestions.init(); });
