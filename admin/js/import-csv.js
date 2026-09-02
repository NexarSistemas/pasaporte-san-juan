const AdminCsvImport = (() => {
  const expectedColumns = [
    'codigo_origen', 'categoria', 'texto', 'respuesta_correcta', 'respuesta_2',
    'respuesta_3', 'respuesta_4', 'pista', 'explicacion', 'dificultad', 'fuente', 'url_fuente'
  ];
  const requiredColumns = ['categoria', 'texto', 'respuesta_correcta', 'respuesta_2', 'respuesta_3', 'respuesta_4'];
  const validDifficulties = new Set(['facil', 'media', 'dificil']);

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

    validRows.forEach((row) => {
      const values = row.values;
      const tableRow = document.createElement('tr');
      tableRow.append(
        createCell(String(row.rowNumber)),
        createCell(values.categoria),
        createCell(values.texto, 'question-cell'),
        createCell(values.respuesta_correcta),
        createCell([values.respuesta_2, values.respuesta_3, values.respuesta_4].join(' · '), 'import-other-answers'),
        createCell(values.dificultad),
        createCell(values.fuente),
        createCell('Válida', 'import-preview-valid')
      );
      preview.append(tableRow);
    });
  };

  const processFile = async (file) => {
    byId('#csv-results').hidden = true;
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
    renderResults({ rows, emptyRows });
    const invalidRows = rows.filter((row) => row.errors.length).length;
    setMessage(invalidRows ? 'Se encontraron filas con errores. Revisá el detalle antes de continuar.' : 'Archivo validado correctamente.', !invalidRows);
  };

  const init = () => {
    byId('#csv-file').addEventListener('change', (event) => {
      processFile(event.target.files[0]).catch(() => setMessage('No fue posible leer el archivo CSV.'));
    });
  };

  return { init };
})();

document.addEventListener('DOMContentLoaded', () => { AdminCsvImport.init(); });
