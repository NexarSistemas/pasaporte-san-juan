# Checklists

## Implementación

- [ ] Leer `AGENTS.md` y los documentos de contexto relevantes.
- [ ] Confirmar árbol Git limpio, rama/upstream y cambios remotos antes de editar.
- [ ] Localizar la última migración que define cada RPC/tabla afectada.
- [ ] Distinguir validación local de despliegue remoto: un merge de GitHub no aplica migraciones en Supabase.
- [ ] Mantener separado el cliente público (RPC) del panel autenticado (RLS/RPC).
- [ ] Si toca contenido, preservar que importar no publica y que similitud no decide.
- [ ] Si toca base, crear migración nueva, conservar autorizaciones explícitas y revisar el impacto en migraciones/seed/tests.

## Revisión

- [ ] Revisar el diff completo, incluidos permisos `GRANT`/`REVOKE`, RLS y `search_path` si hay SQL.
- [ ] Ejecutar `git diff --check`.
- [ ] Ejecutar `node --check` en JavaScript modificado y `node scripts/check-version.mjs` si corresponde.
- [ ] Ejecutar `node --test admin/js/similarity.test.js` si cambia la lógica de similitud.
- [ ] Para cambios Supabase, aplicar desde cero localmente y correr `supabase/tests/v030_rpc_tests.sql` y `supabase/tests/v050_revision_semantica_admin_tests.sql` con `psql`.
- [ ] Si el alcance incluye producción, comparar antes el historial/esquema remoto con el repo y aplicar sólo lo pendiente con autorización explícita.
- [ ] Después de un despliegue remoto, verificar migraciones registradas, columnas/RPC afectadas, permisos y advisors.
- [ ] Probar el flujo afectado en servidor estático: inicio, respuesta, transición y resultado para juego; login, previsualización, comparación, importación y publicación para admin según alcance.

## Cierre

- [ ] Informar pruebas ejecutadas y límites no verificados, sin inventar resultados.
- [ ] Si una migración quedó mergeada pero no desplegada, declararlo explícitamente como pendiente.
- [ ] Confirmar que documentación distingue IMPLEMENTADO, PLANIFICADO, VISIÓN EVOLUTIVA y FUERA DEL MVP cuando el tema lo requiere.
- [ ] Crear un commit único y coherente si fue solicitado.
- [ ] Antes de push/PR, verificar `git status`, upstream, diff contra base y que no haya cambios ajenos.
- [ ] No mergear, crear tag ni release sin autorización explícita.
