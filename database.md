# Base de datos y seguridad

## IMPLEMENTADO

El proyecto Supabase autorizado es `xffndejkcvsnvozeswbk` en `sa-east-1`. Las migraciones en `supabase/migrations/` definen el esquema deseado y deben aplicarse en orden; la presencia de una migración en `main` no demuestra por sí sola que esté desplegada en el proyecto remoto. Para afirmar el estado de producción, contrastá historial, columnas, firmas de RPC y permisos reales.

| Área | Tablas | Responsabilidad |
| --- | --- | --- |
| Contenido | `categorias`, `preguntas`, `respuestas` | Banco editorial y cuatro respuestas por pregunta. |
| Juego | `jugadores`, `partidas`, `partida_preguntas` | Token opaco, ciclos, respuestas e historial. |

`preguntas` conserva campos editoriales, incluido `estado_editorial` (`pendiente`, `en_revision`, `revisada`, `publicada`, `rechazada`) y `concepto_id` nullable. El juego filtra `activo` y `publicada`. Las respuestas exigen una correcta por pregunta mediante índice parcial; las RPC administrativas exigen exactamente cuatro, una correcta y textos distintos al publicar/editar.

### Superficie pública

El rol `anon` no recibe permisos de tablas. Puede ejecutar solamente `crear_partida(uuid)`, `responder_pregunta(uuid, uuid, uuid, uuid)`, `finalizar_partida(uuid, uuid)` y `listar_categorias_publicas()`. Estas funciones son `SECURITY DEFINER`, controlan el `search_path` y validan token, pertenencia y estado de partida cuando corresponde.

`crear_partida` usa grupos `concepto:<uuid>` para variantes y `pregunta:<uuid>` si falta concepto. Prioriza no vistas y reduce recencia sobre las últimas tres partidas, con orden determinista por `created_at DESC, numero_partida DESC` cuando identifica las recientes. La recencia ordena alternativas, no bloquea un banco pequeño.

### Administración

El panel requiere sesión autenticada y `app_metadata.role = 'admin'`. Las políticas permiten a administración leer categorías, preguntas y respuestas. Las RPC de escritura verifican de nuevo `auth.uid()` y el rol en `app_metadata`; `importar_pregunta_admin`, `actualizar_pregunta_admin`, `publicar_pregunta_pendiente_admin`, `asignar_concepto_pregunta_admin` y `agrupar_preguntas_por_concepto_admin` son los contratos usados por el panel.

No autorices con `user_metadata`: es modificable por el usuario. No concedas `EXECUTE` a `PUBLIC`/`anon` para RPC administrativas ni pongas `service_role` en clientes.

### Migraciones y remoto

GitHub Actions ejecuta pruebas de base, pero no despliega migraciones a Supabase. Una aplicación remota hecha por conector o proceso manual puede registrar una versión/timestamp distinto del nombre de archivo local; compará nombre, orden lógico y efecto resultante, no sólo el número de versión. Tras un despliegue autorizado, verificá al menos historial, esquema/RPC afectados, `GRANT`/`REVOKE` y advisors.

## PLANIFICADO / VISIÓN EVOLUTIVA

Los estados y campos conceptuales adicionales de `ARQUITECTURA_CONTENIDOS_NEXAR.md` no constituyen esquema aplicado salvo que figuren en migraciones. No existe una tabla de colecciones ni un flujo de IA en producción.

## FUERA DEL MVP

No hay acceso directo público a tablas, perfil público de jugador ni persistencia de identidad personal.
