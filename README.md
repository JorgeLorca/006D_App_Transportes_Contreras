# Sistema de Digitalización y Gestión de Fletes Logísticos — Transportes Contreras

## Descripción del Proyecto
Plataforma multiplataforma (aplicación móvil Android y panel administrativo web) desarrollada para la empresa **Transportes Contreras**, ubicada en la Región Metropolitana de Santiago y con operaciones logísticas intercomunales e interregionales a lo largo de Chile.

**¿Qué problema resuelve?**
Sustituye los registros manuales en papel y canales informales (llamadas y mensajería dispersa) por un ecosistema digital centralizado. Permite gestionar la asignación y ejecución de viajes, el control de asistencia georreferenciada, el registro y auditoría de cargas de combustible, el reporte de incidentes en ruta y la consolidación automática de planillas bajo el ciclo contable de la empresa (del día 21 al día 20 del mes siguiente). Además, garantiza la continuidad operativa en carreteras y zonas rurales sin cobertura celular mediante una arquitectura **Offline-First**.

**¿A quién va dirigido?**
* **Conductores de Flota (App Móvil Android):** Para consultar rutas asignadas, marcar asistencia en base, reportar estados de viaje, registrar combustible e incidentes en ruta (incluso sin conexión) y revisar su cartola o planilla por ciclo.
* **Personal Administrativo y de Finanzas (Panel Web):** Para gestionar flota, conductores, clientes (con tarifas diferenciadas para camión simple y rampla) y consignatarios, asignar viajes, monitorear cumplimiento operativo (Día, Semana y Ciclo) y auditar asistencias, gastos y planillas.

---

## Tecnologías Utilizadas
* **Frontend Multiplataforma:** Flutter SDK & Dart (base de código unificada para App Móvil Android y Panel Web).
* **Backend & Cloud (BaaS):** Supabase (PostgreSQL 15+, GoTrue Auth, PostgREST, Cloud Storage y Edge Functions).
* **Persistencia Local (Offline-First):** SQLite (`sqflite`) + detección de red (`connectivity_plus`) bajo el patrón *Store-and-Forward*.
* **Despliegue Web:** Firebase Hosting (CDN global, HTTPS/TLS y soporte SPA).
* **Control de Versiones y Gestión:** Git, GitHub y Jira.

---

## Instrucciones para ejecutar el proyecto localmente
**Requisitos Previos**
* Flutter SDK y Dart SDK instalados y configurados en el PATH del sistema.
* Visual Studio Code (con extensiones de Flutter y Dart) o Android Studio.
* Android SDK y un emulador Android configurado o dispositivo físico con depuración USB habilitada.
* Navegador web (Google Chrome) para la ejecución del panel administrativo.

**Pasos de Instalación y Ejecución**
* **1. Clonar el repositorio:**
* git clone https://github.com/JorgeLorca/006D_App_Transportes_Contreras.git
* cd 006D_App_Transportes_Contreras
  (Ubicarse en la carpeta correspondiente al proyecto Flutter)

* **2. Verificar el entorno:**
* flutter doctor

* **3. Instalar dependencias**
* flutter pub get

* **4. Configurar credenciales de Supabase:**
* Verificar que la inicialización del cliente en main.dart / supabase_init.dart cuente con la URL y anonKey del proyecto activo en Supabase.

* **5. Ejecutar la aplicación**
* En dispositivo o emulador Android: flutter run
* En navegador Web (Panel Administrativo): flutter run -d chrome

* **6. Generar compilaciones de producción (opcional):**
* APK Android: flutter build apk --release
* Web: flutter build web --release

---

## Integrantes del Equipo y Roles

* Jorge Lorca — Scrum Master & Lead Developer (Arquitectura Offline-First, sincronización SQLite/Supabase, seguridad RLS y Edge Functions).
* Lucas Contreras — Product Owner & Full-Stack Developer (Levantamiento con stakeholders, reglas de negocio logístico/contable, desarrollo frontend y backend).
* Valentina Cisterna — Frontend Developer & QA/UX Engineer (Diseño de interfaces adaptativas en Flutter móvil/web, experiencia de usuario y pruebas funcionales).

---

## Metodología de Trabajo
El proyecto se desarrolló bajo el marco de trabajo ágil Scrum, organizado en iteraciones de dos semanas (5 Sprints más una semana de estabilización técnica y pruebas). El seguimiento de las 16 Historias de Usuario, criterios de aceptación y Definition of Done se gestionó mediante Jira, mientras que el control de versiones colaborativo se llevó a cabo en GitHub utilizando ramas de trabajo e integración continua

---

## Arquitectura de la Solución
El sistema implementa una **Arquitectura en Cuatro Capas Lógicas** desacopladas[cite: 6]:

1. **Capa 1 — Presentación:** Interfaces responsivas en Flutter para Web (`AdminShell`, dashboards, CRUDs y mapas) y Android (`ConductorHome`, `MisViajesScreen`, `IncidentesScreen`, `VerIncidentesScreen`, `PlanillaScreen`, asistencia y combustible), desplegadas en Firebase Hosting y paquete APK respectivamente[cite: 4, 6].
2. **Capa 2 — Aplicación:** Reglas de negocio logístico, validaciones de formato (RUT chileno, patentes, prevención de traslapes horarios), cálculo de ciclos (21 al 20) y motor de sincronización `SyncHelper`[cite: 4, 6].
3. **Capa 3 — Acceso a Datos:** Repositorios y helpers (`DatabaseHelper`, `supabase_flutter`) que abstraen el consumo de APIs RESTful (PostgREST) y la lectura/escritura en SQLite local[cite: 6].
4. **Capa 4 — Persistencia y Seguridad:** Base de datos relacional normalizada en PostgreSQL (Supabase) protegida mediante políticas **Row-Level Security (RLS)** y almacenamiento local embebido en SQLite[cite: 6].

```text
[ Panel Web (Flutter Web / Firebase Hosting) ]       [ App Móvil (Flutter Android APK) ]
                      │                                              │
                      ▼                                              ▼
         [ Capa de Aplicación y Reglas ]               [ Capa de Aplicación + SyncHelper ]
                      │                                     │                 │
                      ▼                                     ▼                 ▼
          [ Supabase (PostgreSQL + RLS) ] ◄─── Sync ─── [ SQLite Local (Offline-First) ]
