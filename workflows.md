# Flujos operativos

## IMPLEMENTADO: juego público

1. La home consulta las categorías jugables.
2. El navegador recupera o crea el UUID local y llama `crear_partida`.
3. PostgreSQL crea la partida y devuelve preguntas/opciones sin revelar la correcta.
4. Cada respuesta se envía a `responder_pregunta`; sólo entonces se muestra corrección, puntaje y explicación.
5. `finalizar_partida` calcula el resultado desde `partida_preguntas` y cierra la partida.

No sustituir una RPC fallida con cálculo local ni revelar respuestas en el payload inicial.

## IMPLEMENTADO: CSV y revisión editorial

1. Un administrador inicia sesión y elige CSV UTF-8 con encabezados. Son obligatorios `categoria`, `texto`, `respuesta_correcta`, `respuesta_2`, `respuesta_3` y `respuesta_4`; los demás encabezados admitidos están en `admin/js/import-csv.js`.
2. El navegador analiza, valida estructura/dificultad/respuestas y muestra una previsualización: todavía no escribe datos.
3. La comparación consulta categorías y preguntas para detectar categoría inexistente y posibles duplicados por `codigo_origen` o texto normalizado. Es una ayuda, no una decisión editorial automática.
4. Tras confirmación, importa una fila a la vez mediante `importar_pregunta_admin`. Las filas listas quedan `pendiente`; errores y duplicados se informan por fila.
5. El administrador edita, puede revisar similitud y asignar/agrupar `concepto_id`, y publica explícitamente. Sólo la publicación habilita la pregunta para el juego.

Mantener comparación y escritura separadas. No agregar cargas masivas paralelas, categorías automáticas ni credenciales de privilegio.

## PLANIFICADO / VISIÓN EVOLUTIVA

La revisión asistida por IA indicada en `ARQUITECTURA_CONTENIDOS_NEXAR.md` es un flujo conceptual externo: no hay API ni aprobación automática implementada.

## FUERA DEL MVP

No hay autoservicio para alumnos/docentes, importación sin revisión humana ni publicación automática.
