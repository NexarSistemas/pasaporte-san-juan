const SimilarityReview = (() => {
  const STOP_WORDS = new Set(['a', 'al', 'ante', 'con', 'cual', 'como', 'de', 'del', 'el', 'en', 'es', 'la', 'las', 'lo', 'los', 'para', 'por', 'que', 'se', 'su', 'un', 'una', 'y']);

  const normalize = (value) => String(value || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('es-AR').replace(/[^a-z0-9]+/g, ' ').trim();

  const significantTokens = (value) => new Set(normalize(value).split(' ')
    .filter((token) => token.length >= 3 && !STOP_WORDS.has(token)));

  const overlap = (left, right) => {
    if (!left.size || !right.size) return 0;
    let shared = 0;
    left.forEach((token) => { if (right.has(token)) shared += 1; });
    return shared / new Set([...left, ...right]).size;
  };

  const scoreCandidate = (question, candidate) => {
    const sameText = normalize(question.texto) === normalize(candidate.texto);
    const textScore = sameText ? 1 : overlap(significantTokens(question.texto), significantTokens(candidate.texto));
    const answerScore = overlap(significantTokens(question.correctAnswer), significantTokens(candidate.correctAnswer));
    return Math.round((textScore * 0.8 + answerScore * 0.2) * 100);
  };

  const rankCandidates = (question, candidates, limit = 5) => candidates
    .filter((candidate) => candidate.id !== question.id)
    .map((candidate) => ({ ...candidate, score: scoreCandidate(question, candidate) }))
    .filter((candidate) => candidate.score >= 20)
    .sort((left, right) => right.score - left.score
      || Number(right.estado_editorial === 'publicada') - Number(left.estado_editorial === 'publicada')
      || Number(right.categoria_id === question.categoria_id) - Number(left.categoria_id === question.categoria_id)
      || left.texto.localeCompare(right.texto, 'es-AR'))
    .slice(0, limit);

  const labelFor = (score) => score >= 90 ? 'Duplicado claro' : score >= 45 ? 'Variante posible' : 'Coincidencia baja';
  const isCurrentReview = (reviewedQuestionId, selectedQuestionId) => reviewedQuestionId === selectedQuestionId;

  return { isCurrentReview, labelFor, normalize, rankCandidates, scoreCandidate };
})();

if (typeof module !== 'undefined') module.exports = SimilarityReview;
