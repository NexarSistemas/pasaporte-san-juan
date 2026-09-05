# Contexto operativo — Pasaporte San Juan

Leé primero [architecture.md](architecture.md), [database.md](database.md), [workflows.md](workflows.md), [conventions.md](conventions.md) y [checklists.md](checklists.md). Para cambios propios del producto, usá la skill local `.agents/skills/pasaporte-san-juan/SKILL.md`.

## Límites del producto

- Es un sitio estático vanilla publicado en GitHub Pages. El juego público consume sólo RPC de Supabase; no agregues accesos directos a tablas ni claves secretas al navegador.
- El panel `/admin/` es otra superficie estática: requiere sesión de Supabase y `app_metadata.role = 'admin'`. Las validaciones de interfaz no sustituyen RLS ni las validaciones de las RPC.
- La selección, la corrección, el puntaje y el historial son responsabilidad de PostgreSQL. No reimplementes ni desincronices esas reglas en `js/`.
- `js/questions.js` es fixture editorial para generar el seed; la producción usa el banco remoto. No mezclar ambos flujos.
- `ARQUITECTURA_CONTENIDOS_NEXAR.md` es visión evolutiva, no especificación de funcionalidades activas.

## Cambios de base y contenidos

- Inspeccioná la última definición de cada RPC en las migraciones, no una versión histórica del mismo archivo.
- Conservá `SECURITY DEFINER`, la comprobación de `auth.uid()`/`app_metadata.role`, `search_path` controlado y los `GRANT`/`REVOKE` existentes. Nunca uses `service_role` en frontend.
- Las preguntas jugables son activas y `publicada`. El importador sólo crea pendientes; publicar es una decisión explícita de administración.
- Antes de modificar migraciones, admin o SQL, ejecutá las pruebas de base según `checklists.md`. No aplicar cambios a Supabase remoto sin autorización expresa.

## Git y entregas

`main` es la rama estable. No desarrollar funcionalidades nuevas directamente en ella: usar `feature/*`, `fix/*`, `docs/*` o `chore/*`. Integrar sólo tras revisión APROBABLE; tags y releases sólo después de integrar y validar `main` y con autorización expresa.
