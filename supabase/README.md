# Supabase — Pasaporte San Juan

Proyecto autorizado: `xffndejkcvsnvozeswbk` (`Pasaporte San Juan`, `sa-east-1`). No operar contra otro proyecto.

Las migraciones crean las tablas, RLS, índices y RPC. `anon` no tiene permisos sobre tablas: las RPC `SECURITY DEFINER` validan el UUID opaco y la pertenencia de cada partida, fijan el `search_path` y revocan `EXECUTE` a `PUBLIC` antes de concederlo explícitamente a `anon`.

`seed.sql` es idempotente y migra la fixture editorial. Para regenerarlo: `node scripts/generate-seed.mjs`. No almacenar claves secretas en el repositorio.
