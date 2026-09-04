# Pasaporte San Juan v0.6.1

Juego educativo de preguntas sobre San Juan, construido con HTML, CSS y JavaScript vanilla y publicado en [GitHub Pages](https://pasaporte.nexarsistemas.com.ar). Supabase aporta historial y lógica sensible.

El juego consume un banco dinámico de preguntas y categorías, con historial de partidas, selección anti-repetición, efemérides dinámicas e imágenes licenciadas. El footer identifica a Nexar Sistemas y muestra la versión activa.

`VERSION` es la referencia documental principal de cada release; `scripts/check-version.mjs` comprueba que coincida con `GAME_CONFIG.version` en el frontend.

## Arquitectura

La evolución futura del banco reutilizable de contenidos está descrita en [ARQUITECTURA_CONTENIDOS_NEXAR.md](ARQUITECTURA_CONTENIDOS_NEXAR.md).

`GitHub Pages → RPC con publishable key → Supabase xffndejkcvsnvozeswbk (sa-east-1)`

El proyecto usa PostgreSQL, RLS y las RPC `crear_partida`, `listar_categorias_publicas`, `responder_pregunta` y `finalizar_partida`. El navegador solo conoce URL y publishable key en `js/config.js`; nunca contiene service_role ni secret keys y no consulta tablas directamente.

## Flujo y anti-repetición

El navegador crea un UUID v4 con `crypto.randomUUID()` y lo guarda como `pasaporte-san-juan.player-token.v1` en `localStorage`. No se solicitan cuentas ni datos personales.

La selección sucede en PostgreSQL: agrupa variantes por `concepto_id` y evita dos preguntas semánticamente equivalentes dentro de una partida. Entre partidas prioriza grupos y preguntas menos recientes en las últimas tres partidas, sin bloquear bancos reducidos. Se evita duplicar dentro de una partida y, si hay alternativa, repetir exactamente un conjunto anterior. Al agotar las preguntas activas inicia un ciclo nuevo sin borrar historial.

La opción correcta y la explicación solo se devuelven después de contestar. Al finalizar, la base reconstruye el puntaje, aciertos y racha desde el historial.

## Base de datos y pruebas

- `supabase/migrations/`: esquema, RLS, RPC, índices y seed aplicable desde cero.
- `supabase/seed.sql`: seed editorial idempotente.
- `supabase/tests/v030_rpc_tests.sql`: suite transaccional, incluida la simulación de 100 preguntas en diez partidas sin repetición.
- `scripts/generate-seed.mjs`: regenera el SQL desde la fixture `js/questions.js`.

El seed migra 24 preguntas, 96 respuestas y 7 categorías. `questions.js` queda como fixture editorial; producción no lo carga ni mezcla datos locales/remotos.

## Ejecutar localmente

```bash
python3 -m http.server 8080
```

No hay dependencias de Node para ejecutar el sitio. Consultá [supabase/README.md](supabase/README.md), [PRIVACY.md](PRIVACY.md), [EULA.md](EULA.md) y [THIRD_PARTY.md](THIRD_PARTY.md).
