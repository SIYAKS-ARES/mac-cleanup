import SwiftUI

/// Full-window colour field behind the native macOS chrome.
struct AppBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Theme.Palette.canvasGradient
            RadialGradient(colors: [Theme.Palette.aqua.opacity(0.07), Color.clear], center: isDrifting ? .topTrailing : .topLeading, startRadius: 10, endRadius: 520)
                .blur(radius: 28)
        }
        .ignoresSafeArea()
        .onAppear {
            guard reduceMotion == false else { return }
            withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) { isDrifting = true }
        }
    }
}
