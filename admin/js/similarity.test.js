const test = require('node:test');
const assert = require('node:assert/strict');
const SimilarityReview = require('./similarity.js');

const question = { id: 'actual', categoria_id: 'cat-a', texto: '¿Cuál es la capital de San Juan?', correctAnswer: 'San Juan' };

test('detecta una pregunta duplicada y excluye la propia', () => {
  const candidates = SimilarityReview.rankCandidates(question, [
    question,
    { id: 'duplicada', categoria_id: 'cat-a', estado_editorial: 'publicada', texto: 'Cual es la capital de San Juan', correctAnswer: 'San Juan' }
  ]);
  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].id, 'duplicada');
  assert.equal(candidates[0].score, 100);
  assert.equal(SimilarityReview.labelFor(candidates[0].score), 'Duplicado claro');
});

test('conserva una variante útil y descarta una pregunta sin coincidencias relevantes', () => {
  const candidates = SimilarityReview.rankCandidates(question, [
    { id: 'variante', categoria_id: 'cat-a', estado_editorial: 'publicada', texto: '¿Qué ciudad es la capital de la provincia de San Juan?', correctAnswer: 'Ciudad de San Juan' },
    { id: 'ajena', categoria_id: 'cat-b', estado_editorial: 'pendiente', texto: '¿Qué deporte se juega con una pelota naranja?', correctAnswer: 'Básquet' }
  ]);
  assert.deepEqual(candidates.map((candidate) => candidate.id), ['variante']);
  assert.ok(candidates[0].score >= 45 && candidates[0].score < 100);
});
