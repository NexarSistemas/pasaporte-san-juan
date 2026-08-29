/* Presentación independiente del motor y del backend. */
const getSeasonalMessage = (date = new Date()) => {
  const month = date.getMonth() + 1;
  const day = date.getDate();
  const specialEvent = PRESENTATION_CONFIG.specialEvents[`${month}-${day}`];
  if (specialEvent) return specialEvent;
  const monthlyEvents = PRESENTATION_CONFIG.monthEvents[month];
  if (monthlyEvents?.length) return monthlyEvents[(day - 1) % monthlyEvents.length];
  return PRESENTATION_CONFIG.defaultBadge;
};
const renderPresentation = () => {
  document.querySelector('#seasonal-badge').textContent = `☀️ ${getSeasonalMessage()}`;
  document.querySelector('#app-version').textContent = GAME_CONFIG.version;
};
