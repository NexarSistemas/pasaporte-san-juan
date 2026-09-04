-- Superficie pública mínima para la home: sólo las categorías jugables.
create or replace function public.listar_categorias_publicas()
returns table(nombre text, icono text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.nombre, c.icono
  from public.categorias c
  where c.activo
    and exists (
      select 1
      from public.preguntas q
      where q.categoria_id = c.id
        and q.activo
        and q.estado_editorial = 'publicada'
    )
  order by c.orden, c.nombre;
$$;

revoke all on function public.listar_categorias_publicas() from public, authenticated;
grant execute on function public.listar_categorias_publicas() to anon;
