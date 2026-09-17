# Project Structure

## Organization Philosophy

Organización **feature-first**: el código se agrupa por funcionalidad (Spots, Escaneo de peces, Capturas, Perfil) en lugar de por tipo técnico (todas las Views juntas, todos los ViewModels juntos). Cada feature sigue internamente el patrón MVVM. El código compartido entre features (networking, modelos comunes, utilidades de UI) vive en carpetas propias a nivel raíz.

## Directory Patterns

### Features
**Location**: `/App/Features/<NombreFeature>/`  
**Purpose**: Todo lo relacionado con una funcionalidad concreta: sus Views, ViewModel(s) y modelos específicos de esa feature.  
**Example**: `/App/Features/FishScanner/FishScannerView.swift`, `/App/Features/FishScanner/FishScannerViewModel.swift`

### Core / Shared
**Location**: `/App/Core/`  
**Purpose**: Código reutilizado por varias features: cliente de red genérico, extensiones de Swift/SwiftUI, componentes de UI compartidos (botones, cards), utilidades (formateo de fechas, coordenadas).  
**Example**: `/App/Core/Networking/APIClient.swift`, `/App/Core/UI/PrimaryButton.swift`

### Services
**Location**: `/App/Services/`  
**Purpose**: Integraciones con servicios externos, encapsuladas detrás de un protocolo para poder testear con mocks. Aquí viven el cliente de Supabase y el cliente de la API de Fishial.ai.  
**Example**: `/App/Services/Supabase/SupabaseService.swift`, `/App/Services/FishID/FishialClient.swift`

### Models
**Location**: `/App/Models/`  
**Purpose**: Modelos de datos compartidos entre features (p. ej. `FishingSpot`, `Catch`, `Species`), normalmente `Codable` para mapear con Supabase o con la API de Fishial.ai.  
**Example**: `/App/Models/FishingSpot.swift`

### Resources
**Location**: `/App/Resources/`  
**Purpose**: Assets (imágenes, colores), `Localizable.strings`, y ficheros de configuración (claves de API por entorno, mediante `.xcconfig` o similar).  
**Example**: `/App/Resources/Assets.xcassets`, `/App/Resources/Localizable.strings`


## Naming Conventions

- **Files**: PascalCase, igual que el tipo principal que contienen (`FishingSpot.swift`, `SpotMapView.swift`)
- **Views (SwiftUI)**: sufijo `View` (`SpotDetailView`, `CatchLogView`)
- **ViewModels**: sufijo `ViewModel` (`SpotDetailViewModel`)
- **Servicios/Clientes**: sufijo descriptivo del rol (`FishialClient`, `SupabaseService`)
- **Funciones/variables**: camelCase, verbos para funciones (`fetchNearbySpots()`), sustantivos para propiedades (`nearbySpots`)


## Import Organization


```swift
// Frameworks del sistema primero
import SwiftUI
import CoreLocation

// Módulos/paquetes externos después
import Supabase

// Sin path aliases: Swift resuelve tipos por módulo/target,
// no por rutas de import como en TypeScript/JS
```

**Path Aliases**:
No aplica en Swift — la organización en carpetas es solo para navegación en Xcode; el compilador resuelve los tipos por nombre dentro del mismo target o vía `import <Módulo>` para dependencias externas (SPM).


## Code Organization Principles

- **MVVM por feature**: cada View tiene un ViewModel asociado (`@Observable` u `ObservableObject`) responsable de la lógica de presentación y las llamadas a Services; las Views no llaman directamente a APIs externas.
- **Services detrás de protocolos**: `SupabaseService` y `FishialClient` se definen con un protocolo (`SpotsRepository`, `FishIdentifying`) para poder inyectar mocks en tests, en lugar de depender de la implementación concreta.
- **Una dirección de dependencias**: Features → Services → Core. Los Services no conocen las Features, y Core no conoce ni Services ni Features.
- **Modelos como frontera**: los tipos que cruzan la red (Supabase, Fishial.ai) son `Codable` y viven en `/Models`, para que el mapeo de JSON esté centralizado y no repartido por las Views.

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
