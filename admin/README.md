# Mini administración de Pasaporte San Juan

Portal estático para revisar y editar el contenido editorial de `preguntas`. Se publica de forma independiente bajo `/admin/` y no modifica la interfaz pública del juego.

## Configuración

La configuración está en `js/config.js` e incluye solamente la URL del proyecto Supabase y una **publishable key**. Ambos son datos públicos previstos para una aplicación web. El acceso efectivo depende de Supabase Auth, `app_metadata.role = "admin"` y las políticas RLS del proyecto.

Nunca agregues ni expongas una secret key ni una `service_role` key en este directorio, GitHub Pages o cualquier otro frontend.

## Desarrollo local

Desde la raíz del repositorio:

```bash
python3 -m http.server 8080
```

Abrí `http://localhost:8080/admin/`. El portal usa Supabase JS desde CDN y no requiere dependencias ni un build step.

## GitHub Pages

GitHub Pages publica los archivos estáticos respetando el directorio. Tras desplegar la rama configurada, la administración queda disponible en `https://<organizacion>.github.io/<repositorio>/admin/` o en `/admin/` si se usa un dominio personalizado.

La URL final debe estar permitida en la configuración de redirect URLs de Supabase Auth. No se realizan cambios de Supabase desde este proyecto.
