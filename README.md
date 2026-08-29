# Pasaporte San Juan v0.3.0

Juego educativo de preguntas sobre San Juan. La interfaz conserva HTML, CSS y JavaScript vanilla en GitHub Pages; Supabase aporta historial y lógica sensible.

## Arquitectura

`GitHub Pages → RPC con publishable key → Supabase xffndejkcvsnvozeswbk (sa-east-1)`

El proyecto usa PostgreSQL, RLS y las RPC `crear_partida`, `responder_pregunta` y `finalizar_partida`. El navegador solo conoce URL y publishable key en `js/config.js`; nunca contiene service_role ni secret keys y no consulta tablas directamente.

## Flujo y anti-repetición

El navegador crea un UUID v4 con `crypto.randomUUID()` y lo guarda como `pasaporte-san-juan.player-token.v1` en `localStorage`. No se solicitan cuentas ni datos personales.

La selección sucede en PostgreSQL: primero preguntas activas nunca vistas; luego las menos recientes y menos usadas en las últimas tres partidas, con aleatoriedad. Se evita duplicar dentro de una partida y, si hay alternativa, repetir exactamente un conjunto anterior. Al agotar las preguntas activas inicia un ciclo nuevo sin borrar historial. Las preguntas agregadas después se priorizan como nunca vistas.

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
