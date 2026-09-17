# Guía Maestra de Desarrollo y Arquitectura: Cómo Añadir Nuevas Funcionalidades en Woosh

Esta guía contiene la arquitectura completa, la ubicación exacta de cada archivo clave y el procedimiento paso a paso para que cualquier desarrollador o asistente de IA pueda crear e integrar una nueva funcionalidad en **Woosh** de manera directa, sin perder tiempo explorando la estructura del proyecto.

---

## 1. Visión General del Proyecto

- **Nombre de la App:** Woosh (anteriormente Vorssaint).
- **Módulo Swift:** `Vorssaint` (ubicado en `Sources/Vorssaint/`).
- **Tecnología:** Swift nativo + SwiftUI + AppKit + CoreGraphics / SkyLight. Sin dependencias externas pesadas.
- **Sistema de Compilación:**
  - Build normal: `./build.sh` (genera el bundle firmado en `build/stage/Woosh.app`).
  - Tests: `swift test`.
  - Nota: Al compilar en entornos con sandbox, el compilador requiere acceso a `/var/folders` para las cachés de módulos de clang/swift.

---

## 2. Mapa de Directorios y Archivos Clave

```text
Sources/Vorssaint/
├── Core/
│   ├── FeatureCatalog.swift         <-- Registro central del enum AppFeature, grupos y metadatos
│   ├── Defaults.swift               <-- Claves de UserDefaults y valores por defecto
│   └── FeaturePresets.swift         <-- Perfiles de instalación inicial (Essential, Windows, etc.)
│
├── App/
│   ├── FeatureRuntime.swift         <-- Orquestador del ciclo de vida y bindings activos
│   ├── AppDelegate.swift            <-- Ciclo de vida de la app de macOS y observadores globales
│   └── Permissions.swift            <-- Monitor reactivo de permisos del sistema (Accesibilidad, etc.)
│
├── Services/                        <-- Lógica de fondo, daemons, event taps y APIs privadas
│   └── [TuServicio]/                <-- Subcarpeta dedicada a la lógica interna de tu feature
│
└── UI/
    └── Settings/
        ├── FeatureVisibilitySupport.swift <-- Enum SettingsPage y router de navegación
        ├── SettingsDirectory.swift        <-- Secciones de la barra lateral, títulos, iconos y palabras clave
        ├── SettingsView.swift             <-- Switch principal que asocia cada SettingsPage con su vista
        └── [TuFeatureSettings].swift      <-- Vista en SwiftUI del panel de ajustes de tu feature
```

---

## 3. Flujo Paso a Paso para Implementar una Nueva Característica

Sigue estos 7 pasos en este orden exacto. La arquitectura del proyecto está tipada exhaustivamente, por lo que el compilador te guiará si falta algún paso.

### Paso 1: Registrar la Característica en el Catálogo
**Archivo:** `Sources/Vorssaint/Core/FeatureCatalog.swift`
1. Añade tu caso al enum `AppFeature`:
   ```swift
   enum AppFeature: String, CaseIterable {
       // ...
       case miFeature = "mi_feature"
   }
   ```
   *Regla:* El `rawValue` es persistente y define la clave de disponibilidad interna (`featureAvailable.mi_feature`). No debe cambiarse una vez publicado.
2. Asígnalo a un grupo en `var group: FeatureGroup`:
   - Grupos disponibles: `.windowsDock`, `.mouseKeyboard`, `.clipboardFiles`, `.sound`, `.energyDisplay`, `.tools`, `.monitor`.
3. Declara sus permisos requeridos en `var requiredPermissions: [AppPermission]` (por ejemplo: `[.accessibility]`).

---

### Paso 2: Registrar Claves y Valores por Defecto en UserDefaults
**Archivo:** `Sources/Vorssaint/Core/Defaults.swift`
1. Declara la clave en `enum DefaultsKey`:
   ```swift
   static let miFeatureEnabled = "mi_feature_enabled"
   static let miFeatureOpcionSecundaria = "mi_feature_opcion_secundaria"
   ```
2. Registra los valores iniciales en `Defaults.registerDefaults()`:
   ```swift
   DefaultsKey.miFeatureEnabled: true,
   DefaultsKey.miFeatureOpcionSecundaria: 100,
   ```

---

### Paso 3: Crear el Servicio de Fondo (Backend Logic)
**Directorio:** `Sources/Vorssaint/Services/[MiFeature]/MiFeatureService.swift`
Estructura estándar de un servicio en Woosh:
```swift
import AppKit
import Foundation

final class MiFeatureService: ObservableObject {
    static let shared = MiFeatureService()

    @Published private(set) var isRunning = false

    private init() {}

    /// Método obligatorio llamado por FeatureRuntime al cambiar preferencias o disponibilidad
    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = AppFeature.miFeature.isAvailable 
            && defaults.bool(forKey: DefaultsKey.miFeatureEnabled)

        if wanted, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard !isRunning else { return }
        // Inicializar event taps, timers o listeners
        isRunning = true
    }

    private func stop() {
        guard isRunning else { return }
        // Destruir recursos, remover event taps
        isRunning = false
    }
}
```

---

### Paso 4: Enlazar el Servicio al Ciclo de Vida del Runtime
**Archivo:** `Sources/Vorssaint/App/FeatureRuntime.swift`
En el diccionario `private static let bindings: [AppFeature: () -> Void]`:
```swift
.miFeature: { MiFeatureService.shared.syncWithPreferences() },
```
*Efecto:* Cuando el usuario active o desactive la característica desde el Hub de Woosh o desde los Ajustes, `FeatureRuntime` ejecutará este bloque inmediatamente para encender o apagar el servicio sin reiniciar la app.

---

### Paso 5: Registrar la Navegación y Destino de Ajustes
**Archivo:** `Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift`
1. Añade la página al enum `SettingsPage`:
   ```swift
   enum SettingsPage: Hashable {
       // ...
       case miFeature
   }
   ```
2. Mapea la característica en la extensión `AppFeature.settingsDestination`:
   ```swift
   case .miFeature: return FeatureSettingsDestination(.miFeature)
   ```

---

### Paso 6: Registrar la Página en la Barra Lateral de Ajustes
**Archivo:** `Sources/Vorssaint/UI/Settings/SettingsDirectory.swift`
En `SettingsDirectory.sections(...)`, añade el ítem en la categoría adecuada:
```swift
SettingsDirectoryItem(
    page: .miFeature,
    title: "Mi Feature",
    icon: "sparkles", // SF Symbol
    keywords: ["mi", "feature", "palabras", "clave"]
)
```

---

### Paso 7: Crear y Enlazar la Vista de Ajustes (UI)
1. **Crear la vista:** `Sources/Vorssaint/UI/Settings/MiFeatureSettings.swift`
   ```swift
   import SwiftUI

   struct MiFeatureSettings: View {
       @ObservedObject private var permissions = Permissions.shared
       @ObservedObject private var service = MiFeatureService.shared

       @AppStorage(DefaultsKey.miFeatureEnabled) private var enabled = true

       var body: some View {
           Form {
               Section {
                   Toggle("Activar Mi Feature", isOn: $enabled)
                       .onChange(of: enabled) { _, _ in
                           MiFeatureService.shared.syncWithPreferences()
                       }
               }

               if !permissions.accessibility {
                   Section("Permiso requerido") {
                       PermissionRow(kind: .accessibility)
                   }
               }
           }
           .formStyle(.grouped)
       }
   }
   ```
2. **Enlazar el router:** `Sources/Vorssaint/UI/Settings/SettingsView.swift`
   En el `switch page`:
   ```swift
   case .miFeature: MiFeatureSettings()
   ```

---

## 4. Lecciones Críticas y Errores Comunes Aprendidos

### A. Ejecución de Comandos Shell / Terminal
- **Prohibido:** `Darwin.system(cmd)`. En Swift en macOS/Darwin, `system()` está marcado explícitamente como `unavailable` por Apple y fallará la compilación.
- **Forma Correcta:** Utilizar siempre `Process()` / `NSTask` de forma asíncrona:
  ```swift
  DispatchQueue.global(qos: .userInitiated).async {
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: "/bin/sh")
      proc.arguments = ["-c", commandString]
      try? proc.run()
  }
  ```

### B. Elementos en la Barra de Menú (`NSStatusItem`)
- **Evitar bucles infinitos de clics:** Si usas un `NSStatusItem` con menú desplegable, **NUNCA** hagas:
  ```swift
  // ¡INCORRECTO! Genera recursión infinita y cuelga la app con EXC_BAD_ACCESS
  button.action = #selector(clicked)
  @objc func clicked() {
      button.menu = menu
      button.performClick(nil) // Llama de nuevo a clicked() infinitamente
  }
  ```
- **Forma Correcta:** Haz que tu clase conforme a `NSObject, NSMenuDelegate`, asigna `statusItem.menu = menu` una sola vez y puebla los ítems dinámicamente con `menuNeedsUpdate(_ menu: NSMenu)`.

### C. Visibilidad del Cursor y Servidor de Ventanas (WindowServer)
- Si tu función realiza cambios rápidos de escritorio, espacios o inyecciones de gestos sintéticos (`kIOHIDEventTypeDockSwipe`), WindowServer puede ocultar u "obscurecer" el cursor y olvidar restaurarlo si las transiciones se traslapan.
- **Solución:**
  1. Enlazar `CGSUnobscureCursor` y `CGSShowCursor` vía `dlsym` desde SkyLight.
  2. Ejecutar `CGWarpMouseCursorPosition(loc)` sobre la posición actual del cursor (un *warp* de distancia cero obliga al compositor de hardware de WindowServer a regenerar la superficie del cursor).
  3. Despachar un evento inofensivo de `mouseMoved` para forzar la actualización.

### D. Enlace Dinámico con APIs Privadas de macOS (CGS / SLS)
- Si necesitas usar APIs privadas del WindowServer de macOS (como `CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`, etc.), no las enlaces estáticamente: cárgalas dinámicamente con `dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SymbolName")`. Esto garantiza que la app no falle al iniciar en versiones futuras o distintas de macOS donde los símbolos cambien de nombre.

### E. Actualización de Pruebas Unitarias al Añadir Características
**Archivo:** `Tests/MetricsTests.swift`
- El proyecto cuenta con una suite de pruebas estricta que valida el catálogo completo.
- En la línea ~8983 hay una aserción estricta del número total de características:
  ```swift
  expect(AppFeature.allCases.count == 54, "feature catalog has 54 features")
  ```
- Al añadir una nueva característica, incrementa este contador (ej. a 55) y añade el `rawValue` de tu nueva característica en el arreglo de validación `expect(AppFeature.allCases.map(\.rawValue) == [ ... ])`. De lo contrario, `swift test` reportará un fallo de conteo.

---

## 5. Resumen del Ciclo de Verificación

Una vez implementada la herramienta:
1. Compila la app para verificar enlaces y firmas:
   ```bash
   ./build.sh
   ```
2. Ejecuta los tests:
   ```bash
   swift test
   ```
3. Verifica la presencia del bundle listo para usar en:
   `build/stage/Woosh.app`
