# Taskly — Task Management App

**Taskly** es una aplicación multiplataforma de gestión de tareas personales y colaborativas, diseñada para organizar actividades, mejorar la productividad y mantener la información sincronizada entre dispositivos.

Desarrollada con un enfoque en rendimiento, simplicidad y una experiencia de usuario moderna.

## Características principales

- Gestión de tareas, subtareas y categorías.
- Organización de proyectos personales y colaborativos.
- Calendario y seguimiento de actividades.
- Estadísticas de productividad.
- Recordatorios y notificaciones.
- Sincronización entre Android y Web.
- Personalización de colores y apariencia.
- Modos Claro, Oscuro y AMOLED.
- Autenticación mediante Supabase.
- Almacenamiento en la nube.

## Tecnologías utilizadas

| Componente | Tecnología |
|---|---|
| Android | Flutter y Dart |
| Web | HTML, CSS y JavaScript |
| Base de datos | PostgreSQL |
| Backend | Supabase |
| Autenticación | Supabase Auth |
| Sincronización | Supabase Realtime |
| Hosting web | Vercel |
| Iconografía | Lucide Icons |

## Arquitectura

El proyecto mantiene dos aplicaciones que utilizan un mismo backend:

**Taskly Android** — Aplicación nativa desarrollada con Flutter.

**Taskly Web** — Aplicación web desplegada mediante Vercel.

Ambas versiones se conectan a Supabase para almacenar y sincronizar la información.

## Estructura del proyecto

```text
taskly/
├── flutter_app/       # Aplicación Android
├── web_simulator/     # Aplicación Web
├── supabase/          # Base de datos y migraciones
├── package.json       # Herramientas y scripts
└── vercel.json        # Configuración de Vercel
```

## Estado del proyecto

**Versión:** 1.0

**Estado:** En desarrollo y pruebas.

La aplicación Android cuenta con una compilación APK ARM64 optimizada. El proyecto continúa en proceso de pruebas y mejoras.

## Seguridad

Taskly utiliza autenticación mediante Supabase Auth y políticas Row Level Security (RLS) para controlar el acceso a la información.

Las credenciales administrativas y los archivos privados no deben incluirse en el repositorio.

## Autor

Desarrollado como proyecto personal de desarrollo Full Stack, con enfoque en aplicaciones multiplataforma, diseño UI/UX y servicios en la nube.
