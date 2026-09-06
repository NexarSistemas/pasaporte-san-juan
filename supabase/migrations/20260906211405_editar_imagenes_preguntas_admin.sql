-- Permite editar la imagen y su texto alternativo sin cambiar el flujo editorial.
-- La firma anterior se conserva para consumidores administrativos existentes.
create or replace function public.actualizar_pregunta_admin(
  p_pregunta_id uuid, p_categoria_id uuid, p_texto text, p_pista text,
  p_explicacion text, p_dificultad text, p_fuente text, p_url_fuente text,
  p_observaciones_revision text, p_respuesta_correcta_id uuid, p_respuesta_correcta text,
  p_respuesta_2_id uuid, p_respuesta_2 text, p_respuesta_3_id uuid,
  p_respuesta_3 text, p_respuesta_4_id uuid, p_respuesta_4 text, p_concepto_id uuid,
  p_imagen text, p_imagen_alt text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resultado jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Se requiere una sesión autenticada.' using errcode = '42501';
  end if;
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then
    raise exception 'La cuenta no tiene permisos de administración.' using errcode = '42501';
  end if;

  v_resultado := public.actualizar_pregunta_admin(
    p_pregunta_id, p_categoria_id, p_texto, p_pista, p_explicacion,
    p_dificultad, p_fuente, p_url_fuente, p_observaciones_revision,
    p_respuesta_correcta_id, p_respuesta_correcta, p_respuesta_2_id,
    p_respuesta_2, p_respuesta_3_id, p_respuesta_3, p_respuesta_4_id,
    p_respuesta_4, p_concepto_id
  );

  update public.preguntas
  set imagen = nullif(pg_catalog.btrim(coalesce(p_imagen, '')), ''),
      imagen_alt = nullif(pg_catalog.btrim(coalesce(p_imagen_alt, '')), '')
  where id = p_pregunta_id;

  return v_resultado;
end;
$$;

revoke all on function public.actualizar_pregunta_admin(
  uuid, uuid, text, text, text, text, text, text, text, uuid, text,
  uuid, text, uuid, text, uuid, text, uuid, text, text
) from public, anon;
grant execute on function public.actualizar_pregunta_admin(
  uuid, uuid, text, text, text, text, text, text, text, uuid, text,
  uuid, text, uuid, text, uuid, text, uuid, text, text
) to authenticated;
