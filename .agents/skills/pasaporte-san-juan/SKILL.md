---
name: pasaporte-san-juan
description: Trabajar de forma segura en Pasaporte San Juan, un juego estático con Supabase, RPC públicas y administración editorial CSV.
---

# Pasaporte San Juan

Usá esta skill para cambios en el juego, `/admin/`, contenido editorial, Supabase o documentación operativa de este repositorio.

## Antes de actuar

Leé `AGENTS.md` y la referencia que corresponda:

- [architecture.md](../../../architecture.md): límites del frontend, juego y administración.
- [database.md](../../../database.md): modelo, RPC, Auth y RLS.
- [workflows.md](../../../workflows.md): juego, CSV y revisión editorial.
- [conventions.md](../../../conventions.md): estilos, versionado y migraciones.
- [checklists.md](../../../checklists.md): validación y cierre.

## Invariantes

- El cliente público llama RPC y no consulta tablas. La respuesta correcta, el puntaje y la selección se resuelven en PostgreSQL.
- No exponer claves secretas ni usar `service_role` en el sitio o `/admin/`.
- `app_metadata.role = 'admin'` habilita el panel, pero las RPC administrativas también deben verificarlo. No sustituirlo por `user_metadata`.
- El CSV se previsualiza y compara antes de persistir; la importación es secuencial por fila y sólo crea preguntas pendientes. La similitud orienta una decisión humana.
- `concepto_id` es nullable. Los grupos de juego usan claves tipadas `concepto:<uuid>` o `pregunta:<uuid>`; no cambiar ese contrato sin pruebas de regresión.

## Límites de alcance

`ARQUITECTURA_CONTENIDOS_NEXAR.md` describe evolución futura. No implementes API de IA, colecciones, nuevas entidades o publicación automática sólo porque figuren allí. Para cambios de esquema, creá una migración nueva; no reescribas migraciones aplicadas.
