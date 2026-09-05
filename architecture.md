# Arquitectura actual

## IMPLEMENTADO

Pasaporte San Juan es un juego educativo estático en HTML, CSS y JavaScript vanilla. GitHub Pages sirve la interfaz pública y el subdirectorio independiente `/admin/`; no hay backend propio, framework ni paso de compilación.

```text
Navegador público ──RPC con publishable key──> Supabase/PostgreSQL
Navegador admin ──Auth + RLS/RPC────────────> Supabase/PostgreSQL
```

La home carga categorías mediante `listar_categorias_publicas`. Al iniciar, `crear_partida` selecciona y devuelve preguntas sin respuesta correcta. `responder_pregunta` registra la opción y revela resultado/explicación; `finalizar_partida` reconstruye las estadísticas en el servidor. `js/game-engine.js` representa el estado recibido, pero no decide reglas sensibles.

El token anónimo del jugador es un UUID v4 persistido sólo en `localStorage`; no se solicitan cuentas públicas ni datos personales. La administración usa Supabase Auth con correo/contraseña y separa login (`admin/index.html`) de edición (`admin/admin.html`).

## LÍMITES IMPLEMENTADOS

- El frontend público no lee tablas de Supabase y no conoce claves secretas.
- Producción no carga `js/questions.js`: esa fixture alimenta `scripts/generate-seed.mjs`.
- Sólo preguntas activas y `publicada` entran al juego. Una partida contiene hasta diez grupos de preguntas y evita variantes del mismo concepto en la misma partida.
- El panel administra preguntas y categorías existentes; no modifica la interfaz pública.

## PLANIFICADO

No hay una arquitectura futura implementada adicional a la documentada como visión. No inferir endpoints, pantallas, tablas ni automatizaciones futuras.

## VISIÓN EVOLUTIVA

[ARQUITECTURA_CONTENIDOS_NEXAR.md](ARQUITECTURA_CONTENIDOS_NEXAR.md) propone un banco de contenidos reutilizable, colecciones y revisión asistida. Es deliberadamente prospectiva; no describe contratos vigentes.

## FUERA DEL MVP

No están implementados un CMS genérico multiinstitución, integración productiva con IA, publicación automática, perfiles públicos o adaptadores para otros tipos de juego.
