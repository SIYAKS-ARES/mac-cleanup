import SwiftUI

/// User-facing appearance options. Values are persisted with @AppStorage and read
/// back into a single `ThemeSettings` value that travels through the environment.
enum ThemeStorageKey {
    static let appearance = "theme.appearance"
    static let accent = "theme.accent"
    static let density = "theme.density"
    static let material = "theme.material"
}

enum AppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// System colors only: no hard-coded hex, so contrast settings keep working.
enum AccentOption: String, CaseIterable, Identifiable {
    case system
    case blue
    case teal
    case purple
    case graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .blue: return "Blue"
        case .teal: return "Teal"
        case .purple: return "Purple"
        case .graphite: return "Graphite"
        }
    }

    /// `nil` means: do not override the user's macOS accent color.
    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return .blue
        case .teal: return .teal
        case .purple: return .purple
        case .graphite: return .gray
        }
    }

    var swatch: Color {
        color ?? .accentColor
    }
}

enum DensityOption: String, CaseIterable, Identifiable {
    case comfortable
    case compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .compact: return "Compact"
        }
    }

    /// Extra vertical padding applied to table rows and stacked chrome.
    var rowPadding: CGFloat {
        switch self {
        case .comfortable: return 4
        case .compact: return 0
        }
    }

    var stackSpacing: CGFloat {
        switch self {
        case .comfortable: return Theme.Spacing.m
        case .compact: return Theme.Spacing.s
        }
    }

    var controlSize: ControlSize {
        switch self {
        case .comfortable: return .regular
        case .compact: return .small
        }
    }
}

enum MaterialOption: String, CaseIterable, Identifiable {
    case regular
    case thick
    case plain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular: return "Regular"
        case .thick: return "Thick"
        case .plain: return "Plain"
        }
    }

    var detail: String {
        switch self {
        case .regular: return "Standard translucency for cards and wells."
        case .thick: return "Denser, more opaque chrome."
        case .plain: return "Solid fills only, like Reduce Transparency."
        }
    }

    var allowsMaterial: Bool {
        self != .plain
    }
}

struct ThemeSettings: Equatable {
    var appearance: AppearanceOption = .system
    var accent: AccentOption = .system
    var density: DensityOption = .comfortable
    var material: MaterialOption = .regular

    static let `default` = ThemeSettings()
}

private struct ThemeSettingsKey: EnvironmentKey {
    static let defaultValue = ThemeSettings.default
}

extension EnvironmentValues {
    var themeSettings: ThemeSettings {
        get { self[ThemeSettingsKey.self] }
        set { self[ThemeSettingsKey.self] = newValue }
    }
}

/// Reads the stored preferences once and applies them to a scene's root view.
struct ThemeChrome: ViewModifier {
    @AppStorage(ThemeStorageKey.appearance) private var appearanceRaw = AppearanceOption.system.rawValue
    @AppStorage(ThemeStorageKey.accent) private var accentRaw = AccentOption.system.rawValue
    @AppStorage(ThemeStorageKey.density) private var densityRaw = DensityOption.comfortable.rawValue
    @AppStorage(ThemeStorageKey.material) private var materialRaw = MaterialOption.regular.rawValue

    private var settings: ThemeSettings {
        ThemeSettings(
            appearance: AppearanceOption(rawValue: appearanceRaw) ?? .system,
            accent: AccentOption(rawValue: accentRaw) ?? .system,
            density: DensityOption(rawValue: densityRaw) ?? .comfortable,
            material: MaterialOption(rawValue: materialRaw) ?? .regular
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(\.themeSettings, settings)
            .preferredColorScheme(settings.appearance.colorScheme)
            .tint(settings.accent.color)
    }
}

extension View {
    func themeChrome() -> some View {
        modifier(ThemeChrome())
    }
}
