# Aurea

Aurea es una app Flutter de finanzas personales para iOS y Android. La base incluye autenticación Firebase por estrategias, Firestore offline-first, Storage, Remote Config, App Check, Cloud Functions, FCM, Crashlytics, Performance, Analytics opt-in y bloqueo biométrico local.

## Funcionalidad implementada

- Onboarding ilustrado con estado persistente y acceso directo para usuarios autenticados.
- Inicio de sesión por correo, Google y Apple mediante Strategy Pattern.
- Cuentas creadas por el usuario, edición de nombre/tipo y archivado seguro.
- Registro de ingresos, gastos y transferencias con categorías.
- Historial con búsqueda y filtros por tipo de movimiento.
- Inicio e Insights calculados desde datos reales, sin cifras de demostración.
- Plan financiero para presupuestos, metas y movimientos recurrentes.
- Tema claro, oscuro o del sistema persistido entre sesiones.
- Bloqueo con Face ID/Touch ID al abrir o tras un minuto real en segundo plano.
- Formularios adaptados a iOS y Android con cierre global del teclado.

## Arquitectura

- `lib/app`: router, tema y shell.
- `lib/core`: Firebase, dinero exacto y seguridad local.
- `lib/features`: autenticación, onboarding, cuentas, movimientos, inicio, plan, insights y ajustes.
- `functions`: Cloud Functions 2nd gen en TypeScript.
- `firestore.rules`, `storage.rules` e índices: seguridad versionada deny-by-default.

Los importes se guardan como enteros en unidad menor (`amountMinor`). Remote Config contiene solo flags y parámetros públicos; los secretos de Functions deben declararse en Secret Manager.

Las operaciones de la aplicación no dependen de Cloud Functions ni de Artifact
Registry: saldos, presupuestos, metas, resúmenes y recurrentes se actualizan
desde el cliente mediante transacciones de Firestore. La carpeta `functions`
se conserva como referencia opcional y no forma parte del despliegue configurado
por Firebase CLI.

## Configuración Firebase

1. Usa proyectos separados para `dev`, `staging` y `prod`.
2. Ejecuta `flutterfire configure` para cada flavor o reemplaza de forma segura:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
3. En Firebase Authentication habilita Email/Password, Google y Apple.
4. Los archivos nativos incluidos ya contienen los clientes OAuth de Google para Android e iOS del proyecto `finance-app-b84c1`.
5. En Apple Developer habilita Sign in with Apple para `pe.ask.financeApp` y sincroniza el provisioning profile.
6. Las huellas SHA-1/SHA-256 del keystore de debug ya están registradas. Antes de publicar, registra también las huellas del keystore de release/Play App Signing para Google Sign-In, Play Integrity y App Check.
7. Configura App Attest/DeviceCheck en iOS y Play Integrity en Android; usa tokens debug solo en desarrollo.
8. Publica backend y configuración:

```sh
npm --prefix functions install
npm --prefix functions run build
firebase deploy --only firestore:rules,firestore:indexes,storage,functions,remoteconfig
```

App Check está marcado como obligatorio en callables sensibles. Antes de activarlo en producción, valida métricas y registra todos los builds legítimos.

## Desarrollo

```sh
flutter pub get
flutter analyze
flutter test
firebase emulators:start
flutter run
```

Para usar emuladores, conecta `FirebaseAuth`, Firestore, Storage y Functions mediante una configuración de bootstrap exclusiva de debug antes de realizar operaciones.

## Privacidad operativa

- Analytics empieza desactivado y solo guarda eventos genéricos si el usuario acepta.
- Crashlytics no recibe montos, saldos, descripciones ni nombres financieros.
- Las notificaciones se solicitan de forma opt-in y sus previews deben ser genéricos.
- La biometría protege el reingreso local; Firebase Authentication sigue siendo la identidad remota. Face ID se solicita al abrir Aurea o tras un minuto real en segundo plano, no por diálogos ni permisos del sistema.
- Los formularios cierran el teclado al tocar fuera o al desplazar su contenido, incluido el teclado numérico de iOS.
- Exportación y borrado de cuenta se ejecutan server-side mediante callables con App Check.

## Pendientes de consola para producción

El código y los archivos desplegables están listos, pero estas acciones requieren acceso al proyecto/tiendas y no pueden resolverse solo desde el repositorio:

- Habilitar y terminar de configurar los proveedores Email/Password, Google y Apple en Authentication; los clientes OAuth nativos ya están declarados.
- Registrar proveedores de App Check y activar enforcement gradualmente.
- Configurar APNs para FCM.
- Definir presupuestos/alertas GCP, backups y retención.
- Crear credenciales de firma y perfiles de Apple/Android.
- Integrar los tests de reglas de Firestore y Storage en CI antes del primer deploy.
