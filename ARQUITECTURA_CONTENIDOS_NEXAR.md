# Arquitectura futura — Banco de Contenidos Educativos Nexar

> Documento fuente para la evolución de **Pasaporte San Juan** y futuros juegos educativos Nexar.
>
> Estado: visión aprobada / implementación incremental.
>
> Principio rector: **no construir ahora toda la plataforma futura**. El MVP actual sigue siendo Turismo, pero las decisiones nuevas deben evitar bloquear la evolución hacia un sistema reutilizable y comercializable.

## 1. Objetivo

Pasaporte San Juan nace como un juego educativo de Turismo para una presentación escolar, pero debe poder evolucionar sin rehacer su base hacia una plataforma donde distintas instituciones puedan aportar, revisar, administrar y publicar contenidos reutilizables en diferentes juegos.

La arquitectura futura debe separar claramente:

1. **Banco de contenidos**
2. **Administración editorial**
3. **Motor de juego / adaptadores**

El contenido educativo no debe quedar acoplado a una única modalidad de juego.

---

## 2. Caso inicial

La primera implementación estará centrada exclusivamente en **Turismo de San Juan**.

Un caso de uso prioritario es permitir que alumnos y docentes de una institución propongan:

- pregunta;
- respuesta;
- descripción o explicación;
- fuente, cuando corresponda;
- categoría o tema sugerido.

Ese contenido no se publica automáticamente.

Flujo previsto:

```text
Alumno / docente
      ↓
Contenido original
      ↓
Carga administrativa
      ↓
Pendiente de revisión
      ↓
Revisión y normalización con ChatGPT
      ↓
Verificación factual cuando corresponda
      ↓
Aprobación humana
      ↓
Publicación
      ↓
Juego
```

La revisión con IA es asistida, nunca una autorización automática para publicar.

---

## 3. Contenido original y contenido normalizado

Debe conservarse el aporte original y diferenciarlo de la versión editorial utilizada por el juego.

Ejemplo conceptual:

```text
pregunta_original
respuesta_original
descripcion_original

pregunta
respuesta
descripcion
```

Esto permite:

- conservar la autoría y trazabilidad;
- corregir ortografía y claridad sin perder el aporte inicial;
- revisar cambios editoriales;
- reutilizar el contenido en otros formatos;
- identificar errores o ambigüedades.

---

## 4. Modelo canónico de contenido

El banco debe almacenar una representación independiente del juego.

Campos conceptuales previstos:

```text
id
categoria_id
subcategoria
pregunta_original
respuesta_original
descripcion_original
pregunta
respuesta
descripcion
dificultad
nivel_educativo
autor_tipo
institucion
curso
estado
fuente
revision_ia
revision_notas
created_at
updated_at
published_at
```

No todos estos campos tienen que implementarse en la primera iteración.

### Estados editoriales sugeridos

```text
BORRADOR
PENDIENTE_REVISION
REVISADA_IA
APROBADA
PUBLICADA
RECHAZADA
```

---

## 5. Categorías y colecciones

Las categorías no deben depender de condicionales hardcodeados en la interfaz.

Ejemplos futuros:

- Turismo
- Historia
- Geografía
- Ciencia
- Cultura general
- Educación
- Medio ambiente
- Tecnología
- Arte
- Deportes
- Educación vial

También deben poder existir subcategorías.

Además se prevé el concepto de **colecciones**, independiente de las categorías.

Ejemplos:

- San Juan
- Semana del Turismo
- Sarmiento
- Nivel primario
- Escuela X
- Patrimonio
- Naturaleza

Una pregunta puede pertenecer a varias colecciones sin duplicarse.

---

## 6. Adaptadores de juego

El banco almacena contenido canónico. Cada juego puede transformarlo al formato que necesite.

Ejemplo:

```text
Contenido canónico
      ↓
┌──────────────┬───────────────┬──────────────┬─────────────┐
│ Trivia       │ Verdadero/Falso│ Completar    │ Asociación  │
└──────────────┴───────────────┴──────────────┴─────────────┘
```

Una misma pregunta puede originar distintos formatos sin duplicar la fuente editorial.

El motor actual de Pasaporte San Juan seguirá siendo el primer consumidor.

---

## 7. Revisión asistida por ChatGPT

Para el MVP no se integrará una API de IA dentro de producción.

Flujo preferido:

```text
Panel / herramienta administrativa
      ↓
Exportar pendientes (JSON o CSV)
      ↓
ChatGPT
      ↓
Revisar / normalizar / clasificar
      ↓
Archivo revisado
      ↓
Importar
      ↓
Aprobación humana
```

La revisión puede incluir:

- ortografía;
- claridad;
- ambigüedad;
- coherencia pregunta/respuesta/descripción;
- existencia de una respuesta objetivamente correcta;
- dificultad;
- nivel educativo;
- clasificación temática;
- duplicados;
- calidad de distractores;
- riesgos factuales;
- adaptación al formato del juego.

La verificación factual debe tratarse separadamente de la mera corrección de redacción.

---

## 8. Fuentes y calidad educativa

Cuando el contenido dependa de hechos históricos, científicos, turísticos o geográficos, debe poder asociarse una fuente.

Ejemplos:

- sitio oficial;
- publicación institucional;
- libro;
- material docente;
- otra referencia verificable.

No debe publicarse automáticamente un contenido solo porque la IA lo haya normalizado.

Principio:

```text
IA propone → humano aprueba
```

No:

```text
IA publica
```

---

## 9. Privacidad y participación escolar

Para reconocer aportes escolares no es necesario almacenar nombres de menores.

Preferir, cuando alcance:

```text
institucion
curso
division
autor_tipo = alumno | docente | institucional
```

Ejemplo visible:

> Pregunta aportada por estudiantes de 6.º A — Escuela X

Cualquier dato personal adicional deberá evaluarse antes de incorporarlo.

---

## 10. Evolución comercial

La arquitectura debe permitir que el producto pueda ofrecerse a:

- escuelas;
- institutos;
- municipios;
- organismos y secretarías de turismo;
- museos;
- centros culturales;
- organizaciones;
- empresas para capacitación.

Posibles niveles futuros:

### Producto cerrado
Nexar administra y publica el contenido.

### Producto institucional administrable
La institución cuenta con panel propio y flujo editorial.

### Plataforma multijuego
Un mismo banco alimenta distintas experiencias interactivas.

El juego inicial debe funcionar además como demostrador tecnológico y caso de éxito para presentar otros servicios del ecosistema Nexar.

---

## 11. Alcance MVP recomendado

No implementar todavía toda la visión.

Para la primera etapa administrativa, priorizar únicamente:

1. categorías administrables;
2. contenido original;
3. contenido normalizado;
4. estado editorial;
5. fuente opcional;
6. exportación de pendientes a JSON/CSV;
7. importación de revisión;
8. aprobación humana;
9. compatibilidad con el juego actual.

Dejar para iteraciones posteriores:

- autenticación institucional;
- múltiples organizaciones;
- paneles separados por cliente;
- integración directa con APIs de IA;
- generación automática de múltiples formatos;
- analítica institucional avanzada;
- roles complejos;
- facturación o modelo SaaS.

---

## 12. Restricciones del proyecto actual

Pasaporte San Juan mantiene actualmente:

```text
GitHub Pages
    ↓
RPC con publishable key
    ↓
Supabase
```

La aplicación pública no debe recibir `service_role`, secretos ni acceso directo inseguro a operaciones administrativas.

La funcionalidad administrativa futura deberá diseñarse respetando esta separación y sin degradar RLS, RPC existentes ni el flujo de partidas.

La implementación debe preservar:

- selección anti-repetición;
- historial de partidas;
- ocultamiento de respuesta correcta hasta contestar;
- cálculo de puntaje del lado confiable;
- funcionamiento estático del frontend público.

---

## 13. Principios de implementación

1. Mantener el MVP pequeño.
2. Reutilizar el esquema y convenciones existentes siempre que sea razonable.
3. No duplicar el banco de preguntas.
4. No acoplar contenido a una sola interfaz.
5. No exponer secretos en GitHub Pages.
6. Mantener RLS y operaciones sensibles del lado de Supabase.
7. Añadir migraciones incrementales y reversibles cuando sea posible.
8. Cubrir con pruebas las operaciones críticas.
9. Evitar romper el juego público mientras evoluciona la administración.
10. Implementar solo lo necesario para la siguiente versión aprobada.

---

## 14. Decisión arquitectónica

La dirección aprobada es:

```text
                    BANCO DE CONTENIDOS
                           │
             ┌─────────────┼─────────────┐
             │             │             │
          Turismo        Ciencia      Historia
             │             │             │
             └─────────────┼─────────────┘
                           │
                  CONTENIDO CANÓNICO
                           │
                    Adaptadores
             ┌─────────────┼─────────────┐
             │             │             │
           Trivia         V/F        Asociación
             │             │             │
             └─────────────┼─────────────┘
                           │
                         JUEGOS
```

**Pasaporte San Juan es la primera implementación de esta arquitectura, no el límite de la plataforma.**
