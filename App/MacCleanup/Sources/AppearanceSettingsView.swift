import SwiftUI

/// Settings scene (Cmd+,). Appearance only: nothing here changes scan behaviour,
/// decisions, or the apply plan.
struct AppearanceSettingsView: View {
    @AppStorage(ThemeStorageKey.appearance) private var appearanceRaw = AppearanceOption.system.rawValue
    @AppStorage(ThemeStorageKey.accent) private var accentRaw = AccentOption.system.rawValue
    @AppStorage(ThemeStorageKey.density) private var densityRaw = DensityOption.comfortable.rawValue
    @AppStorage(ThemeStorageKey.material) private var materialRaw = MaterialOption.regular.rawValue

    private var material: MaterialOption {
        MaterialOption(rawValue: materialRaw) ?? .regular
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppearanceOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Accent", selection: $accentRaw) {
                    ForEach(AccentOption.allCases) { option in
                        Label {
                            Text(option.displayName)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(option.swatch)
                        }
                        .tag(option.rawValue)
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("System follows your macOS appearance and accent color.")
                    .font(.themeCaption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Density", selection: $densityRaw) {
                    ForEach(DensityOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Material", selection: $materialRaw) {
                    ForEach(MaterialOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                Text(material.detail)
                    .font(.themeCaption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Layout")
            } footer: {
                Text("Reduce Transparency and Reduce Motion in System Settings always win over these choices.")
                    .font(.themeCaption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Defaults") {
                    appearanceRaw = AppearanceOption.system.rawValue
                    accentRaw = AccentOption.system.rawValue
                    densityRaw = DensityOption.comfortable.rawValue
                    materialRaw = MaterialOption.regular.rawValue
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Theme.Layout.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}
