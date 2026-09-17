# Technology Stack

## Architecture

App iOS nativa con arquitectura cliente-servidor. El cliente (Swift/SwiftUI) consume un backend gestionado (Supabase) para datos, autenticación y almacenamiento, y llama a una API externa de terceros para la identificación de especies por imagen.

## Core Technologies

- **Language**: Swift
- **Framework**: SwiftUI
- **Runtime**: iOS 17+
- **Backend**: Supabase (Postgres + PostGIS, Auth, Storage)

## Key Libraries

- **Supabase Swift SDK** — cliente para auth, base de datos y storage
- **MapKit** — visualización de spots de pesca en mapa
- **CoreLocation** — ubicación del usuario para buscar spots cercanos
- Cliente HTTP (URLSession) para consumir la API de Fishial.ai (identificación de especies)


## Development Standards

### Type Safety
Swift en modo estricto por defecto (uso de `Optional` explícito, evitar force-unwrap `!` salvo casos justificados).

### Code Quality
SwiftLint con reglas por defecto o ligeramente ajustadas; convenciones de naming de Swift API Design Guidelines.

### Testing
XCTest para lógica de negocio (parsing de respuestas de API, modelos); pruebas de UI puntuales con XCTest UI para flujos críticos (escaneo de pez, búsqueda de spots).

## Development Environment

### Required Tools
- Xcode (última versión estable)
- Cuenta y proyecto de Supabase configurado
- API key de Fishial.ai
### Common Commands
```bash
# Dev: abrir el .xcodeproj/.xcworkspace en Xcode y ejecutar (Cmd+R)
# Build: xcodebuild -scheme <NombreScheme> build
# Test: xcodebuild -scheme <NombreScheme> test
```

## Key Technical Decisions

- **Solo iOS nativo (Swift/SwiftUI)**: se descarta multiplataforma (React Native/Flutter) para priorizar rendimiento e integración directa con cámara/mapas de Apple, asumiendo que no hay versión Android por ahora.
- **Supabase como backend**: evita montar auth, base de datos y storage desde cero; Postgres + PostGIS facilita las consultas geográficas de spots ("spots cerca de mí").
- **Identificación de especies vía API externa**: se delega el modelo de reconocimiento a un proveedor especializado en lugar de entrenar/mantener un modelo propio, reduciendo complejidad inicial.
- **Normativa/talla mínima por especie — pendiente de decidir fuente**: Fishial.ai identifica la especie pero no incluye datos regulatorios. Esta información tendrá que salir de otra fuente (p. ej. datos abiertos de administración pesquera por región) o mantenerse manualmente en la base de datos propia (tabla en Supabase), actualizándola por especie/zona. A definir antes de implementar esta capability.
---
_Document standards and patterns, not every dependency_
