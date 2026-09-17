import SwiftUI

@main
struct BetterFishingApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "BetterFishing",
                systemImage: "fish",
                description: Text("Próximamente: escáner de peces, puntos de pesca y registro de capturas.")
            )
            .navigationTitle("BetterFishing")
        }
    }
}

#Preview {
    RootView()
}