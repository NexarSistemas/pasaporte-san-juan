# Changelog

## v0.6.0

### Añadido

- Revisión semántica/editorial de preguntas desde administración.
- Clasificación de similitud para detectar duplicados claros y variantes posibles.
- Gestión de `concepto_id` y agrupación editorial de preguntas relacionadas.

### Mejorado

- Edición atómica de pregunta, respuestas y concepto.
- Protección contra acciones de similitud pertenecientes a otra pregunta.
- Agrupación de variantes cuando solo una de las preguntas ya tiene concepto.
- Workflow de GitHub Actions para validar la base de datos desde cero.

### Validación e infraestructura

- PostgreSQL 17 local en CI con migraciones, seed, suites SQL y checks de JavaScript y versión.

## v0.5.0

### Añadido

- Agrupamiento de variantes de preguntas mediante `concepto_id`.
- Prevención de preguntas semánticamente equivalentes dentro de una misma partida.
- Prioridad de preguntas y conceptos menos recientes para mejorar la rejugabilidad.

### Mejorado

- Selección de preguntas entre partidas.
- Tratamiento de bancos pequeños y variantes.
- Orden estable de partidas recientes cuando comparten timestamp.

### Corregido

- Colisiones entre identificadores de preguntas y conceptos.
- Repetición de combinaciones cuando existían variantes alternativas.
- Cálculo de recencia para preguntas sin concepto.
- Desempate de partidas recientes mediante `numero_partida`.
