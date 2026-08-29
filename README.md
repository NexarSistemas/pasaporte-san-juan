# Pasaporte San Juan

Juego educativo de preguntas y respuestas para descubrir la provincia de San Juan. Cada partida propone 10 preguntas al azar, puntaje, rachas y explicaciones breves para aprender durante el recorrido.

## Tecnologías

HTML, CSS y JavaScript vanilla. No requiere dependencias, backend ni APIs externas, por lo que puede publicarse directamente en GitHub Pages.

## Ejecutar localmente

Abrí `index.html` con un navegador o serví esta carpeta con cualquier servidor estático. Las rutas son relativas y también funcionan desde el subpath de GitHub Pages.

## Estructura

- `index.html`: estructura accesible de las pantallas.
- `css/app.css`: estilo responsive y estados visuales.
- `js/config.js`: identidad del juego, puntuación y niveles de resultado.
- `js/questions.js`: banco temporal local de preguntas.
- `js/game-engine.js`: motor reutilizable e independiente del contenido.
- `js/app.js`: coordinación de interfaz, eventos y renderizado.

## Motor genérico

El motor selecciona preguntas sin repetición dentro de una partida, mezcla preguntas y respuestas, controla puntaje, rachas, bonus, progreso y finalización. No conoce San Juan ni categorías concretas: otra experiencia educativa puede reutilizarlo entregándole una configuración y un banco de preguntas con el mismo formato.

`questions.js` contiene contenido temporal de desarrollo. En una versión posterior, su origen podrá reemplazarse por Supabase sin cambiar sustancialmente el motor.

## Próximas versiones

La evolución prevista contempla Supabase PostgreSQL, categorías y banco de preguntas dinámicos, fuentes, jugadores, partidas, historial, anti-repetición entre partidas y administración de contenido. Ninguna de esas capacidades forma parte de v0.1.0.

## Documentación legal

- [Acuerdo de Licencia de Usuario Final](EULA.md)
- [Política de Privacidad](PRIVACY.md)
- [Licencia propietaria](LICENSE)
