-- Bucket público de imágenes editoriales y carga limitada a administradores.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'preguntas-imagenes',
  'preguntas-imagenes',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
);

create policy "admins_insert_preguntas_imagenes"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'preguntas-imagenes'
  and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
);
