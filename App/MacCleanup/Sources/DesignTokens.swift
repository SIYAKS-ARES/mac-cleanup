import SwiftUI

/// Single source of truth for the app's visual language.
/// One palette ("Neon Mint") drives every surface: chrome, charts, badges and states.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum Layout {
        static let sidebarIdealWidth: CGFloat = 260
        static let sidebarMinWidth: CGFloat = 240
        static let sidebarMaxWidth: CGFloat = 320
        static let detailMinWidth: CGFloat = 640
        static let windowMinHeight: CGFloat = 560
        static let donutHeight: CGFloat = 168
        static let inspectorListWidth: CGFloat = 220
        static let inspectorDetailWidth: CGFloat = 380
        static let settingsWidth: CGFloat = 420
        /// Horizontal inset inside Tahoe toolbar glass for tight controls (badge, Unique).
        static let toolbarGlassHorizontalInset: CGFloat = Spacing.s
        /// Vertical inset paired with `toolbarGlassHorizontalInset`.
        static let toolbarGlassVerticalInset: CGFloat = Spacing.xs
    }

    enum Surface {
        case raised
        case well
        case overlay

        var cornerRadius: CGFloat {
            switch self {
            case .raised: return Theme.Radius.medium
            case .well: return Theme.Radius.small
            case .overlay: return Theme.Radius.large
            }
        }

        var allowsMaterial: Bool { self != .overlay }
    }

    /// Neon Mint. Every colour in the app resolves through here.
    enum Palette {
        // Base ramp
        static let deep = Color(red: 0.051, green: 0.106, blue: 0.165)      // #0d1b2a
        static let forest = Color(red: 0.106, green: 0.263, blue: 0.196)    // #1b4332
        static let mint = Color(red: 0.176, green: 0.831, blue: 0.659)      // #2dd4a8
        static let glow = Color(red: 0.451, green: 1.000, blue: 0.722)      // #73ffb8
        static let teal = Color(red: 0.086, green: 0.541, blue: 0.510)      // #168a82
        static let aqua = Color(red: 0.361, green: 0.902, blue: 0.859)      // #5ce6db
        static let onColor = Color.white

        // Semantic roles
        static let accent = mint
        static let accentSoft = aqua
        static let accentStrong = teal
        static let positive = glow
        static let caution = Color(red: 0.949, green: 0.769, blue: 0.325)   // warm amber, used sparingly
        static let critical = Color(red: 0.937, green: 0.451, blue: 0.404)
        static let info = aqua

        // Legacy aliases kept so older call sites stay on the single palette.
        static let violet = mint
        static let pink = glow
        static let cyan = aqua
        static let amber = caution
        static let blue = teal

        static let canvasGradient = LinearGradient(
            colors: [deep.opacity(0.16), forest.opacity(0.12), mint.opacity(0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let heroGradient = LinearGradient(
            colors: [forest, teal, mint],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let coolGradient = LinearGradient(
            colors: [teal, mint, aqua],
            startPoint: .leading,
            endPoint: .trailing
        )

        static let successGradient = LinearGradient(
            colors: [mint, glow],
            startPoint: .leading,
            endPoint: .trailing
        )

        private static let ramp: [Color] = [
            teal, mint, aqua, glow,
            Color(red: 0.216, green: 0.678, blue: 0.596),
            Color(red: 0.353, green: 0.780, blue: 0.639),
            Color(red: 0.145, green: 0.435, blue: 0.435),
            Color(red: 0.541, green: 0.949, blue: 0.784)
        ]

        static func category(_ name: String) -> Color {
            switch name {
            case "Documents": return ramp[0]
            case "Images": return ramp[1]
            case "Videos": return ramp[2]
            case "Audio": return ramp[3]
            case "Spreadsheets": return ramp[4]
            case "Databases": return ramp[5]
            case "Installers": return ramp[6]
            case "Archives": return ramp[7]
            case "Logs": return ramp[4]
            default:
                let index = abs(name.hashValue) % ramp.count
                return ramp[index]
            }
        }
    }

    static func decisionTint(_ decision: RowDecisionTint) -> Color {
        switch decision {
        case .keep: return Palette.mint
        case .discard: return Palette.caution
        case .skip: return .secondary
        }
    }
}

enum RowDecisionTint {
    case keep
    case discard
    case skip
}

extension Font {
    static let themeSectionTitle = Font.subheadline.weight(.semibold)
    static let themeStatValue = Font.title3.weight(.bold).monospacedDigit()
    static let themeRowLabel = Font.body
    static let themeCaption = Font.caption
}

private struct ThemeSurfaceModifier: ViewModifier {
    let surface: Theme.Surface
    let showsStroke: Bool

    @Environment(\.themeSettings) private var settings

    func body(content: Content) -> some View {
        content
            .background {
                ChromeFill(
                    cornerRadius: surface.cornerRadius,
                    showsStroke: showsStroke,
                    allowsMaterial: surface.allowsMaterial && settings.material.allowsMaterial
                )
            }
            .background {
                if settings.material == .thick && surface.allowsMaterial {
                    RoundedRectangle(cornerRadius: surface.cornerRadius, style: .continuous)
                        .fill(Theme.Palette.forest.opacity(0.10))
                }
            }
            .overlay {
                if surface != .overlay {
                    RoundedRectangle(cornerRadius: surface.cornerRadius, style: .continuous)
                        .stroke(Theme.Palette.mint.opacity(settings.material == .plain ? 0.12 : 0.20), lineWidth: 1)
                }
            }
    }
}

extension View {
    func themeSurface(_ surface: Theme.Surface, showsStroke: Bool = true) -> some View {
        modifier(ThemeSurfaceModifier(surface: surface, showsStroke: showsStroke))
    }

    func themeCard(_ surface: Theme.Surface = .raised, padding: CGFloat = Theme.Spacing.m) -> some View {
        self.padding(padding).themeSurface(surface)
    }

    func spectrumCard(_ tint: Color = Theme.Palette.mint) -> some View {
        self
            .padding(Theme.Spacing.m)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .fill(LinearGradient(
                                colors: [tint.opacity(0.16), Theme.Palette.forest.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .stroke(tint.opacity(0.26), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.12), radius: 12, y: 5)
    }

    func themeNumeric() -> some View {
        self
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .multilineTextAlignment(.trailing)
    }
}
