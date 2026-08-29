-- Contenido v0.4.0: reutiliza una imagen local ya atribuida para preguntas
-- directamente relacionadas con Ischigualasto. No modifica el esquema ni RPC.
update public.preguntas
set imagen = 'assets/images/ischigualasto-hero.jpg',
    imagen_alt = 'Formación rocosa de Ischigualasto'
where codigo_origen in ('q02', 'q21');
