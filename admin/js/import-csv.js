const AdminCsvImport = (() => {
  const expectedColumns = [
    'codigo_origen', 'categoria', 'texto', 'respuesta_correcta', 'respuesta_2',
    'respuesta_3', 'respuesta_4', 'pista', 'explicacion', 'dificultad', 'fuente', 'url_fuente'
  ];
  const requiredColumns = ['categoria', 'texto', 'respuesta_correcta', 'respuesta_2', 'respuesta_3', 'respuesta_4'];
  const validDifficulties = new Set(['facil', 'media', 'dificil']);
  const state = { rows: [], emptyRows: 0 };

  const byId = (id) => document.querySelector(id);
  const valueOrEmpty = (value) => (value || '').trim();

  const setMessage = (text, success = false) => {
    const element = byId('#csv-message');
    element.textContent = text;
    element.classList.toggle('is-success', success);
  };

  const parseCsv = (text) => {
    const rows = [];
    let row = [];
    let field = '';
    let inQuotes = false;

    for (let index = 0; index < text.length; index += 1) {
      const character = text[index];
      if (character === '"') {
        if (inQuotes && text[index + 1] === '"') {
          field += '"';
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (character === ',' && !inQuotes) {
        row.push(field);
        field = '';
      } else if ((character === '\n' || character === '\r') && !inQuotes) {
        if (character === '\r' && text[index + 1] === '\n') index += 1;
        row.push(field);
        rows.push(row);
        row = [];
        field = '';
      } else {
        field += character;
      }
    }

    if (inQuotes) throw new Error('Hay una comilla sin cerrar en el archivo CSV.');
    if (field || row.length) {
      row.push(field);
      rows.push(row);
    }
    return rows;
  };

  const isEmptyRow = (row) => row.every((value) => !valueOrEmpty(value));
  const normalizeCategory = (value) => valueOrEmpty(value).toLowerCase();
  const normalizeQuestionText = (value) => valueOrEmpty(value).toLowerCase().replace(/\s+/g, ' ');

  const validateRow = (values, rowNumber) => {
    const errors = [];
    const answers = ['respuesta_correcta', 'respuesta_2', 'respuesta_3', 'respuesta_4'].map((column) => values[column]);
    if (!values.categoria) errors.push('La categoría no puede estar vacía.');
    if (!values.texto) errors.push('El texto no puede estar vacío.');
    if (answers.some((answer) => !answer)) errors.push('Las cuatro respuestas son obligatorias.');
    if (answers.filter(Boolean).length === 4 && new Set(answers).size !== 4) errors.push('Las cuatro respuestas deben ser diferentes entre sí.');
    if (values.dificultad && !validDifficulties.has(values.dificultad)) errors.push('La dificultad debe ser facil, media o dificil.');
    if (values.url_fuente) {
      try {
        new URL(values.url_fuente);
      } catch (_) {
        errors.push('La URL de fuente no tiene un formato válido.');
      }
    }
    return { rowNumber, values, errors };
  };

  const createCell = (value, className = '') => {
    const cell = document.createElement('td');
    cell.textContent = value || '—';
    if (className) cell.className = className;
    return cell;
  };

  const comparisonLabel = (comparison) => {
    if (!comparison) return { text: 'Pendiente', className: 'import-comparison-pending' };
    if (comparison.status === 'lista_para_importar') return { text: 'Lista para importar', className: 'import-comparison-ready' };
    if (comparison.status === 'importada') return { text: 'Importada', className: 'import-comparison-ready' };
    if (comparison.status === 'omitida') return { text: 'Omitida: se detectó un duplicado al importar', className: 'import-comparison-warning' };
    if (comparison.status === 'categoria_no_encontrada') return { text: 'Categoría no encontrada', className: 'import-comparison-warning' };
    return { text: `Posible duplicado: ${comparison.duplicateReasons.join(' y ')}`, className: 'import-comparison-warning' };
  };

  const renderComparisonSummary = (validRows) => {
    const summary = byId('#csv-comparison-summary');
    const comparisons = validRows.map((row) => row.comparison).filter(Boolean);
    if (comparisons.length !== validRows.length) {
      summary.hidden = true;
      return;
    }
    byId('#csv-compared-rows').textContent = validRows.length;
    byId('#csv-ready-rows').textContent = comparisons.filter((comparison) => comparison.status === 'lista_para_importar').length;
    byId('#csv-missing-category-rows').textContent = comparisons.filter((comparison) => comparison.status === 'categoria_no_encontrada').length;
    byId('#csv-duplicate-rows').textContent = comparisons.filter((comparison) => comparison.status === 'posible_duplicado').length;
    summary.hidden = false;
  };

  const readyRows = () => state.rows.filter((row) => row.comparison?.status === 'lista_para_importar');

  const resetImportStatus = () => {
    byId('#csv-import-status').hidden = true;
    byId('#csv-import-progress').textContent = '';
    byId('#csv-import-summary').textContent = '';
    byId('#csv-import-details').replaceChildren();
    byId('#csv-import-details').hidden = true;
  };

  const renderResults = ({ rows, emptyRows, structuralError }) => {
    const results = byId('#csv-results');
    const errors = byId('#csv-errors');
    const preview = byId('#csv-preview-body');
    const validRows = rows.filter((row) => !row.errors.length);
    const invalidRows = rows.filter((row) => row.errors.length);
    byId('#csv-total-rows').textContent = rows.length + emptyRows;
    byId('#csv-valid-rows').textContent = validRows.length;
    byId('#csv-invalid-rows').textContent = invalidRows.length;
    byId('#csv-empty-rows').textContent = emptyRows;
    results.hidden = false;
    preview.replaceChildren();
    errors.replaceChildren();

    if (structuralError) {
      const paragraph = document.createElement('p');
      paragraph.textContent = structuralError;
      errors.append(paragraph);
      errors.hidden = false;
      return;
    }

    invalidRows.forEach((row) => {
      const paragraph = document.createElement('p');
      paragraph.textContent = `Fila ${row.rowNumber}: ${row.errors.join(' ')}`;
      errors.append(paragraph);
    });
    errors.hidden = !invalidRows.length;
    renderComparisonSummary(validRows);

    const importButton = byId('#csv-import-button');
    const comparisonCompleted = comparisons.length === validRows.length && validRows.length > 0;
    importButton.hidden = !comparisonCompleted;
    importButton.disabled = !readyRows().length;

    validRows.forEach((row) => {
      const values = row.values;
      const comparison = comparisonLabel(row.comparison);
      const tableRow = document.createElement('tr');
      tableRow.append(
        createCell(String(row.rowNumber)),
        createCell(values.categoria),
        createCell(row.comparison?.category?.nombre),
        createCell(values.texto, 'question-cell'),
        createCell(values.respuesta_correcta),
        createCell([values.respuesta_2, values.respuesta_3, values.respuesta_4].join(' · '), 'import-other-answers'),
        createCell(values.dificultad),
        createCell(values.fuente),
        createCell('Válida', 'import-preview-valid'),
        createCell(comparison.text, comparison.className)
      );
      preview.append(tableRow);
    });
  };

  const loadAllQuestions = async () => {
    const pageSize = 1000;
    const questions = [];
    let from = 0;
    while (true) {
      const { data, error } = await AdminAuth.client.from('preguntas').select('codigo_origen, texto').range(from, from + pageSize - 1);
      if (error) throw error;
      questions.push(...data);
      if (data.length < pageSize) return questions;
      from += pageSize;
    }
  };

  const compareRows = async () => {
    const validRows = state.rows.filter((row) => !row.errors.length);
    if (!validRows.length) return;

    const button = byId('#csv-compare-button');
    button.disabled = true;
    setMessage('Comprobando categorías y posibles duplicados…');
    try {
      const [{ data: categories, error: categoryError }, questions] = await Promise.all([
        AdminAuth.client.from('categorias').select('id, nombre'),
        loadAllQuestions()
      ]);
      if (categoryError) throw categoryError;
      const categoriesByName = new Map(categories.map((category) => [normalizeCategory(category.nombre), category]));
      const questionsByCode = new Set(questions.map((question) => question.codigo_origen).filter(Boolean));
      const questionsByText = new Set(questions.map((question) => normalizeQuestionText(question.texto)));

      validRows.forEach((row) => {
        const category = categoriesByName.get(normalizeCategory(row.values.categoria));
        const duplicateReasons = [];
        if (row.values.codigo_origen && questionsByCode.has(row.values.codigo_origen)) duplicateReasons.push('codigo_origen');
        if (questionsByText.has(normalizeQuestionText(row.values.texto))) duplicateReasons.push('texto');
        row.comparison = {
          category,
          duplicateReasons,
          status: !category
            ? 'categoria_no_encontrada'
            : duplicateReasons.length ? 'posible_duplicado' : 'lista_para_importar'
        };
      });
      renderResults({ rows: state.rows, emptyRows: state.emptyRows });
      setMessage(
        readyRows().length
          ? 'Comprobación contra Supabase completada.'
          : 'No hay filas nuevas para importar: todas fueron excluidas por duplicados o categorías no encontradas.',
        Boolean(readyRows().length)
      );
    } catch (_) {
      setMessage('No fue posible comprobar el CSV contra Supabase. La previsualización local se conserva.');
    } finally {
      button.disabled = false;
    }
  };

  const processFile = async (file) => {
    byId('#csv-results').hidden = true;
    byId('#csv-compare-button').hidden = true;
    byId('#csv-import-button').hidden = true;
    resetImportStatus();
    state.rows = [];
    state.emptyRows = 0;
    if (!file) return;
    if (!file.name.toLowerCase().endsWith('.csv')) {
      setMessage('Seleccioná un archivo con extensión .csv.');
      return;
    }

    setMessage('Procesando archivo…');
    const text = (await file.text()).replace(/^\uFEFF/, '');
    if (!text.trim()) {
      renderResults({ rows: [], emptyRows: 0, structuralError: 'El archivo CSV está vacío.' });
      setMessage('No se pudo procesar el archivo por un error estructural.');
      return;
    }

    let records;
    try {
      records = parseCsv(text);
    } catch (error) {
      renderResults({ rows: [], emptyRows: 0, structuralError: error.message });
      setMessage('No se pudo procesar el archivo por un error estructural.');
      return;
    }

    const header = records.shift();
    if (!header || isEmptyRow(header)) {
      renderResults({ rows: [], emptyRows: 0, structuralError: 'El archivo no contiene encabezados.' });
      setMessage('No se pudo procesar el archivo por un error estructural.');
      return;
    }

    const columns = header.map(valueOrEmpty);
    const missingColumns = requiredColumns.filter((column) => !columns.includes(column));
    if (missingColumns.length) {
      renderResults({ rows: [], emptyRows: 0, structuralError: `Faltan encabezados obligatorios: ${missingColumns.join(', ')}.` });
      setMessage('No se pudo procesar el archivo por un error estructural.');
      return;
    }

    let emptyRows = 0;
    const rows = records.reduce((validatedRows, record, index) => {
      if (isEmptyRow(record)) {
        emptyRows += 1;
        return validatedRows;
      }
      const values = expectedColumns.reduce((rowValues, column) => {
        rowValues[column] = valueOrEmpty(record[columns.indexOf(column)]);
        return rowValues;
      }, {});
      validatedRows.push(validateRow(values, index + 2));
      return validatedRows;
    }, []);
    state.rows = rows;
    state.emptyRows = emptyRows;
    renderResults({ rows, emptyRows });
    byId('#csv-compare-button').hidden = !rows.some((row) => !row.errors.length);
    const invalidRows = rows.filter((row) => row.errors.length).length;
    setMessage(invalidRows ? 'Se encontraron filas con errores. Revisá el detalle antes de continuar.' : 'Archivo validado correctamente.', !invalidRows);
  };

  const importRows = async () => {
    const rows = readyRows();
    if (!rows.length) return;
    const total = rows.length;
    if (!window.confirm(`Se importarán ${total} pregunta${total === 1 ? '' : 's'} como pendientes. Los posibles duplicados y las categorías no encontradas quedan excluidos. ¿Deseás continuar?`)) return;

    const button = byId('#csv-import-button');
    const compareButton = byId('#csv-compare-button');
    const status = byId('#csv-import-status');
    const progress = byId('#csv-import-progress');
    const summary = byId('#csv-import-summary');
    const details = byId('#csv-import-details');
    const results = { imported: [], skipped: [], errors: [] };
    button.disabled = true;
    compareButton.disabled = true;
    status.hidden = false;
    details.replaceChildren();
    details.hidden = true;
    setMessage('Importando preguntas…');

    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index];
      progress.textContent = `${index + 1} de ${total}`;
      const values = row.values;
      try {
        const { data, error } = await AdminAuth.client.rpc('importar_pregunta_admin', {
          p_codigo_origen: values.codigo_origen || null,
          p_categoria_id: row.comparison.category.id,
          p_texto: values.texto,
          p_pista: values.pista || null,
          p_explicacion: values.explicacion || null,
          p_dificultad: values.dificultad || 'media',
          p_fuente: values.fuente || null,
          p_url_fuente: values.url_fuente || null,
          p_respuesta_correcta: values.respuesta_correcta,
          p_respuesta_2: values.respuesta_2,
          p_respuesta_3: values.respuesta_3,
          p_respuesta_4: values.respuesta_4
        });
        if (error?.code === '23505') {
          row.comparison.status = 'omitida';
          results.skipped.push(row);
        } else if (error || !data?.ok) {
          results.errors.push({ rowNumber: row.rowNumber, message: error?.message || data?.mensaje || 'La RPC no confirmó la importación.' });
        } else {
          row.comparison.status = 'importada';
          results.imported.push(row);
        }
      } catch (_) {
        results.errors.push({ rowNumber: row.rowNumber, message: 'No fue posible comunicarse con Supabase.' });
      }
    }

    renderResults({ rows: state.rows, emptyRows: state.emptyRows });
    progress.textContent = `${total} de ${total}`;
    summary.textContent = `${total} preparadas · ${results.imported.length} importadas · ${results.skipped.length} omitidas · ${results.errors.length} errores`;
    results.errors.forEach((result) => {
      const paragraph = document.createElement('p');
      paragraph.textContent = `Fila ${result.rowNumber}: ${result.message}`;
      details.append(paragraph);
    });
    details.hidden = !results.errors.length;
    setMessage(results.errors.length ? 'La importación finalizó con errores por fila.' : 'Importación completada.', !results.errors.length);
    button.disabled = false;
    compareButton.disabled = false;
  };

  const init = () => {
    byId('#csv-file').addEventListener('change', (event) => {
      processFile(event.target.files[0]).catch(() => setMessage('No fue posible leer el archivo CSV.'));
    });
    byId('#csv-compare-button').addEventListener('click', () => {
      compareRows();
    });
    byId('#csv-import-button').addEventListener('click', () => {
      importRows();
    });
  };

  return { init };
})();

document.addEventListener('DOMContentLoaded', () => { AdminCsvImport.init(); });
