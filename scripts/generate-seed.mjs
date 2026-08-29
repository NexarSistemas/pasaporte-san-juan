import fs from 'node:fs';
import vm from 'node:vm';

const context = {};
vm.createContext(context);
vm.runInContext(`${fs.readFileSync('js/questions.js', 'utf8')}; globalThis.questions = QUESTIONS;`, context);

const escapeSql = (value) => value == null ? 'null' : `'${String(value).replaceAll("'", "''")}'`;
const categories = {
  Destinos: ['destinos', '🗺️', 1],
  Naturaleza: ['naturaleza', '🌄', 2],
  Aventura: ['aventura', '🧭', 3],
  Cultura: ['cultura', '🎭', 4],
  Historia: ['historia', '🏛️', 5],
  'Identidad sanjuanina': ['identidad-sanjuanina', '☀️', 6],
  Argentinismos: ['argentinismos', '💬', 7]
};

const lines = ['-- Datos editoriales iniciales migrados desde js/questions.js.'];
for (const [name, [slug, icon, order]] of Object.entries(categories)) {
  lines.push(`insert into public.categorias (nombre, slug, icono, orden) values (${escapeSql(name)}, ${escapeSql(slug)}, ${escapeSql(icon)}, ${order}) on conflict (slug) do update set nombre = excluded.nombre, icono = excluded.icono, orden = excluded.orden;`);
}
for (const question of context.questions) {
  const [slug] = categories[question.category];
  lines.push(`insert into public.preguntas (codigo_origen, categoria_id, texto, pista, explicacion, imagen, imagen_alt, fuente, url_fuente, fecha_revision, dificultad) select ${escapeSql(question.id)}, c.id, ${escapeSql(question.text)}, ${escapeSql(question.hint)}, ${escapeSql(question.explanation)}, ${escapeSql(question.image)}, ${escapeSql(question.imageAlt)}, ${escapeSql(question.source)}, ${escapeSql(question.urlFuente)}, ${escapeSql(question.fechaRevision)}, 'media' from public.categorias c where c.slug = ${escapeSql(slug)} on conflict (codigo_origen) do update set categoria_id = excluded.categoria_id, texto = excluded.texto, pista = excluded.pista, explicacion = excluded.explicacion, imagen = excluded.imagen, imagen_alt = excluded.imagen_alt, fuente = excluded.fuente, url_fuente = excluded.url_fuente, fecha_revision = excluded.fecha_revision, dificultad = excluded.dificultad;`);
  for (const answer of question.answers) {
    lines.push(`insert into public.respuestas (pregunta_id, texto, es_correcta) select p.id, ${escapeSql(answer.text)}, ${answer.id === question.correctAnswer} from public.preguntas p where p.codigo_origen = ${escapeSql(question.id)} on conflict (pregunta_id, texto) do update set es_correcta = excluded.es_correcta;`);
  }
}
process.stdout.write(`${lines.join('\n')}\n`);
