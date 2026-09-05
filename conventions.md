# Convenciones del repositorio

## IMPLEMENTADO

- JavaScript vanilla y CSS estático. Respetar los módulos globales existentes y evitar dependencias o build tools salvo necesidad demostrada.
- `VERSION` es la fuente documental de versión; `GAME_CONFIG.version` debe coincidir. Ejecutar `node scripts/check-version.mjs` cuando se toque alguno.
- Usar migraciones nuevas y fechadas para cambios de base. No editar migraciones aplicadas ni deducir la definición vigente de una versión vieja de una RPC.
- `supabase/seed.sql` es idempotente. Si cambia la fixture, regenerarlo con `node scripts/generate-seed.mjs` y revisar el diff.
- Commits en español, breves y con prefijo convencional: `feat:`, `fix:`, `docs:`, `test:`, `refactor:` o `chore:`.
- Trabajar en ramas `feature/*`, `fix/*`, `docs/*` o `chore/*`; `main` es estable.

## VALIDACIÓN LOCAL

El sitio se sirve con `python3 -m http.server 8080`. Para sintaxis: `node --check <archivo>`. El test unitario actual es `node --test admin/js/similarity.test.js`.

Para una suite SQL completa, iniciar Supabase local, obtener la URL sin comillas con `supabase status --output json | jq -r '.DB_URL'` y ejecutar cada archivo con `psql "$DB_URL" -v ON_ERROR_STOP=1 -f ...`. La CI muestra la secuencia vigente en `.github/workflows/database-tests.yml`.

## DESPLIEGUE SUPABASE

- `.github/workflows/database-tests.yml` valida; no despliega producción.
- No asumir que `main` y Supabase están sincronizados. Antes de un cambio remoto, comparar historial y objetos afectados.
- Un proceso remoto puede registrar un timestamp de migración distinto del archivo local. Comparar nombre, orden lógico y efecto en esquema/RPC, no sólo la versión numérica.
- Aplicar migraciones remotas únicamente con autorización explícita. Después, verificar historial, firmas de funciones, permisos y advisors; si no se desplegó, informarlo expresamente.

## RIESGOS QUE NO DEBEN ASUMIRSE

- Que una publishable key otorgue privilegios: la autorización depende de RLS/RPC.
- Que una coincidencia de similitud pruebe equivalencia semántica: la decisión sigue siendo humana.
- Que todos los campos/estados de la arquitectura futura estén disponibles en la base real.
- Que un banco tenga diez grupos: la RPC reduce el objetivo al contenido disponible.

## PLANIFICADO / FUERA DEL MVP

No hay gestor de paquetes para el sitio ni contrato para una API de IA, CMS genérico o nuevos roles editoriales.
