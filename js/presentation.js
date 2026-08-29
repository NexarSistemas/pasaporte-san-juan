/* Presentación independiente del motor y del backend. */
const getSeasonalMessage = (date = new Date()) => {
  const month = date.getMonth() + 1;
  const day = date.getDate();
  return PRESENTATION_CONFIG.specialEvents[`${month}-${day}`] || PRESENTATION_CONFIG.monthEvents[month]?.[0] || PRESENTATION_CONFIG.defaultBadge;
};
const renderPresentation = () => {
  document.querySelector('#seasonal-badge').textContent = `☀️ ${getSeasonalMessage()}`;
  document.querySelector('#app-version').textContent = GAME_CONFIG.version;
};
