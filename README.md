# Taskly 1.0 — Gestión Personal y de Equipos (Web & Android + Supabase Free)

Aplicación multiplataforma (**Web** y **Android con Flutter/Dart**) optimizada para producción, respaldada exclusivamente por **Supabase Free** (PostgreSQL, Supabase Auth, Supabase Realtime y Supabase Storage), con iconografía vectorial local **Lucide Icons**, **Estudio de Diseño en Vivo** y motor de **Recordatorios y Notificaciones Interactivas**.

---

## 1. Arquitectura y Tecnologías (100% Plan Gratuito)

| Capa | Tecnología | Detalles de Producción |
| :--- | :--- | :--- |
| **Frontend Web** | HTML5 / CSS3 / JS + `@supabase/supabase-js` | SPA rápida, sin recargas, paquetes locales offline (`lucide.min.js` y `supabase.min.js`) |
| **Frontend Móvil** | Flutter 3.x & Dart (`supabase_flutter`, `lucide_icons`) | Preparado para Android Studio (`com.taskly.app`), Material 3 adaptable |
| **Base de Datos** | PostgreSQL en **Supabase Free** | 9 entidades normalizadas con claves UUID, índices compuestos y triggers |
| **Seguridad** | Row Level Security (**RLS**) + Supabase Auth | Políticas estrictas por `auth.uid()` y membresía de proyecto |
| **Sincronización** | **Supabase Realtime** + SSE Fallback | Sincronización instantánea entre Web y Android con caché local |
| **Notificaciones** | `flutter_local_notifications` + Web Notification API | Acciones rápidas (**Completar** y **Posponer +10m**), zonas horarias y deduplicación |
| **Hosting Web** | **Vercel** | Configurado mediante `vercel.json` con rutas SPA y cabeceras de seguridad |

---

## 2. Estructura del Proyecto

```text
pawd_403_task_manager/
├── .env.example                                  # Variables de entorno requeridas (SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY)
├── vercel.json                                   # Configuración de despliegue SPA y cabeceras para Vercel
├── package.json                                  # Scripts de inicio y pruebas obligatorias (npm start / npm test)
├── supabase/
│   ├── config.toml                               # Configuración de Supabase CLI y URLs de redirección Auth
│   └── migrations/
│       └── 20261114000000_taskly_schema_and_rls.sql # Migración SQL reproducible (9 tablas + RLS + Triggers + Storage)
├── web_simulator/
│   ├── index.html                                # Aplicación Web de producción (0 emojis, Lucide local, Estadísticas reales)
│   ├── server.js                                 # Servidor Node.js con autenticación real, aislamiento RLS y SSE Realtime
│   ├── test_phase15.js                           # Suite automatizada de pruebas obligatorias (Fase 15)
│   └── assets/
│       ├── lucide.min.js                         # Iconos vectoriales Lucide incluidos localmente (sin CDN)
│       └── supabase.min.js                       # Cliente oficial Supabase JS v2 incluido localmente
└── flutter_app/
    ├── pubspec.yaml                              # Dependencias Flutter (supabase_flutter, lucide_icons, local_notifications)
    ├── lib/
    │   ├── main.dart                             # Inicialización de Supabase PKCE, temas y notificaciones
    │   ├── models/task_model.dart                # Modelo de datos sincronizado con PostgreSQL (`public.tasks`)
    │   ├── providers/theme_provider.dart         # Proveedor del Estudio de Diseño (Oscuro, AMOLED, Claro, Auto, Bordes, Densidad)
    │   ├── services/database_service.dart        # CRUD PostgreSQL, Auth real, Realtime stream y borrado de cuenta
    │   ├── services/notification_service.dart    # Recordatorios locales programados en Android con acciones rápidas
    │   ├── screens/home_screen.dart              # Interfaz principal con LucideIcons y estadísticas reales
    │   └── widgets/task_form_sheet.dart          # Formulario de creación/edición con validación
    └── android/
        ├── key.properties.example                # Plantilla de firma release para APK / AAB
        └── app/
            ├── build.gradle                      # Configuración `com.taskly.app`, SDK 34, firma release y desugaring
            └── src/main/
                ├── AndroidManifest.xml           # Permisos de alarma exacta, notificaciones y deep link Supabase Auth
                └── res/                          # Icono adaptativo (`ic_launcher.xml`) y Splash (`launch_background.xml`)
```

---

## 3. Configuración de Supabase Free (Paso a Paso)

1. Crea un proyecto gratuito en [Supabase](https://supabase.com/).
2. Abre el **SQL Editor** en el panel de Supabase, pega el contenido completo de [`supabase/migrations/20261114000000_taskly_schema_and_rls.sql`](./supabase/migrations/20261114000000_taskly_schema_and_rls.sql) y pulsa **Run**.
   - Esto creará automáticamente las **9 tablas normalizadas** (`profiles`, `user_preferences`, `categories`, `projects`, `project_members`, `tasks`, `subtasks`, `reminders`, `task_assignments`), sus índices, triggers, políticas **RLS**, bucket `avatars` en Storage y la publicación `supabase_realtime`.
3. En **Authentication → URL Configuration**, configura:
   - **Site URL**: `https://tu-dominio.vercel.app` (o `http://localhost:3403` en desarrollo).
   - **Redirect URLs**:
     - `http://localhost:3403/**`
     - `https://*.vercel.app/**`
     - `io.supabase.taskly://login-callback/`
4. Copia `.env.example` a `.env` y coloca tus credenciales públicas desde **Project Settings → API**:
   ```env
   SUPABASE_URL=https://tu-proyecto-id.supabase.co
   SUPABASE_PUBLISHABLE_KEY=tu_anon_public_key
   GOOGLE_OAUTH_ENABLED=false
   ```

---

## 4. Ejecución Local y Pruebas Obligatorias (Fase 15)

### Iniciar la Aplicación Web
```bash
node web_simulator/server.js
```
Abre **`http://localhost:3403`** en tu navegador.

### Ejecutar la Suite de Pruebas Obligatorias (Fase 15)
```bash
node web_simulator/test_phase15.js
```
Verifica automáticamente:
- Cero emojis Unicode y carga offline de Lucide Icons (`/assets/lucide.min.js`).
- Cero dependencias de Firebase y presencia de las 9 tablas + RLS en la migración SQL.
- Registro de dos cuentas distintas (**Usuario A** y **Usuario B**) iniciando con **0 tareas ficticias**.
- Inicio de sesión, verificación de correo, recuperación de contraseña y eliminación de cuenta/datos personales.
- Creación, edición, completado, subtareas, categorías, tareas recurrentes y posposición de recordatorios.
- **Aislamiento de seguridad RLS**: comprueba que el Usuario B recibe `HTTP 403 Forbidden` al intentar editar o eliminar tareas o categorías del Usuario A.

---

## 5. Despliegue Web en Vercel (Fase 13)

### Opción A — Desplegar la Aplicación Web incluida en el repositorio
1. Sube el repositorio a GitHub/GitLab o ejecuta `vercel` desde la raíz del proyecto.
2. El archivo [`vercel.json`](./vercel.json) ya configura las rutas SPA y el caché de `/assets/*`.
3. En **Vercel Project Settings → Environment Variables**, agrega `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY`.

### Opción B — Compilar Flutter Web para Vercel
```bash
cd flutter_app
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL=https://tu-proyecto-id.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=tu_anon_public_key
```
Configura `flutter_app/build/web` como **Output Directory** en Vercel.

---

## 6. Compilación de APK / AAB para Android Studio (Fase 14)

1. Abre la carpeta `flutter_app` en **Android Studio** (con el SDK de Flutter instalado).
2. Para firmar el lanzamiento en producción, copia `flutter_app/android/key.properties.example` a `flutter_app/android/key.properties` con los datos de tu keystore `.jks`.
3. Ejecuta desde la terminal en `flutter_app/`:
   ```bash
   flutter pub get

   # Generar APK Release de prueba
   flutter build apk --release \
     --dart-define=SUPABASE_URL=https://tu-proyecto-id.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=tu_anon_public_key

   # Generar Android App Bundle (AAB) para Google Play
   flutter build appbundle --release \
     --dart-define=SUPABASE_URL=https://tu-proyecto-id.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=tu_anon_public_key
   ```
4. El APK firmado se generará en `flutter_app/build/app/outputs/flutter-apk/app-release.apk`.
