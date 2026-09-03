# Changelog

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
