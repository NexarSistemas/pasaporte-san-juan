-- Permite a administradores limpiar objetos propios del bucket editorial.
create policy "admins_select_preguntas_imagenes"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'preguntas-imagenes'
  and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
);

create policy "admins_delete_preguntas_imagenes"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'preguntas-imagenes'
  and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
);
