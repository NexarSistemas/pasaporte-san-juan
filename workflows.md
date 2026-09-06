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
5. El administrador edita y puede asignar/agrupar `concepto_id` mientras la pregunta está `pendiente`, `en_revision`, `revisada` o `publicada`. Una rechazada se conserva y debe reabrirse antes de editarse.
6. El estado cambia exclusivamente mediante la RPC administrativa: `pendiente → en_revision | rechazada`; `en_revision → revisada | rechazada`; `revisada → publicada | en_revision | rechazada`; `publicada → en_revision`; `rechazada → en_revision`. Publicar valida cuatro respuestas distintas y una sola correcta. Sólo la publicación habilita la pregunta para el juego.

Mantener comparación y escritura separadas. No agregar cargas masivas paralelas, categorías automáticas ni credenciales de privilegio.

## OPERACIÓN: migraciones Supabase

La CI de GitHub valida la base local, pero no despliega cambios al proyecto remoto. Cuando una tarea incluya producción, primero compará el estado remoto con `supabase/migrations/`; después de una autorización explícita, aplicá sólo las migraciones pendientes en su orden lógico y verificá esquema, firmas RPC, permisos e informes de advisors. Si el cambio queda sólo en el repo, declaralo como pendiente de despliegue.

## PLANIFICADO / VISIÓN EVOLUTIVA

La revisión asistida por IA indicada en `ARQUITECTURA_CONTENIDOS_NEXAR.md` es un flujo conceptual externo: no hay API ni aprobación automática implementada.

## FUERA DEL MVP

No hay autoservicio para alumnos/docentes, importación sin revisión humana ni publicación automática.
