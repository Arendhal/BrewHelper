import SwiftUI

// Palette ⌘K : un seul champ pour ouvrir un paquet installé, lancer une action ou chercher dans
// tout Homebrew, sans passer par les menus.

struct PaletteItem: Identifiable {
    enum Section: String { case packages = "Paquets", actions = "Actions" }

    let id: String
    let section: Section
    let title: String
    let subtitle: String
    let trailing: String
    let tone: Tone
    let action: () -> Void
}

public struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var highlighted: Int = 0
    @FocusState private var fieldFocused: Bool

    public init() {}

    private var items: [PaletteItem] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ text: String) -> Bool { needle.isEmpty || text.lowercased().contains(needle) }

        let packages = appState.packages
            .filter { needle.isEmpty ? $0.installedOnRequest : (matches($0.name) || matches($0.description)) }
            .sorted { lhs, rhs in
                // Le nom qui commence par la saisie passe devant celui qui la contient.
                let l = lhs.name.lowercased().hasPrefix(needle), r = rhs.name.lowercased().hasPrefix(needle)
                return l != r ? l : lhs.name < rhs.name
            }
            .prefix(needle.isEmpty ? 4 : 6)
            .map { package -> PaletteItem in
                let verdict = SecurityVerdictPill.verdict(for: package, flaws: security.openFlaws(for: package))
                return PaletteItem(id: "pkg-" + package.id, section: .packages, title: package.name,
                                   subtitle: "Installé · \(package.installedVersion) · \(verdict.label)",
                                   trailing: "Ouvrir", tone: verdict.tone == .success ? .neutral : verdict.tone) {
                    appState.showLibrary(.all, selecting: package.id)
                }
            }

        var actions: [PaletteItem] = [
            PaletteItem(id: "update", section: .actions, title: "Actualiser Homebrew", subtitle: "brew update", trailing: "Lancer", tone: .neutral) {
                appState.synchronizeCatalog()
            },
            PaletteItem(id: "upgrade", section: .actions, title: "Tout mettre à jour",
                        subtitle: appState.outdatedCount == 0 ? "Rien à mettre à jour pour l'instant" : "\(appState.outdatedCount) paquet(s) · brew upgrade",
                        trailing: "Lancer", tone: .neutral) {
                appState.runMaintenance(command: .upgradeAll)
            },
            PaletteItem(id: "audit", section: .actions, title: "Relancer l'audit de sécurité", subtitle: "EUVD + NVD, en arrière-plan", trailing: "Lancer", tone: .neutral) {
                appState.runSecurityAudit(force: true)
                appState.selectedTab = .security
            },
            PaletteItem(id: "untracked", section: .actions, title: "Afficher les paquets non suivis",
                        subtitle: "Bibliothèque, filtre « Non suivis » · \(security.untrackedPackages.count)", trailing: "Aller", tone: .neutral) {
                appState.showLibrary(.untracked)
            },
            PaletteItem(id: "cleanup", section: .actions, title: "Nettoyer les anciennes versions", subtitle: "brew cleanup", trailing: "Lancer", tone: .neutral) {
                appState.runMaintenance(command: .cleanup)
            },
            PaletteItem(id: "doctor", section: .actions, title: "Diagnostic Homebrew", subtitle: "brew doctor", trailing: "Lancer", tone: .neutral) {
                appState.runMaintenance(command: .doctor)
                appState.selectedTab = .activity
            }
        ]
        for appearance in AppAppearance.allCases where appearance != appState.appearance {
            actions.append(PaletteItem(id: "appearance-" + appearance.rawValue, section: .actions,
                                       title: "Apparence : \(appearance.label)",
                                       subtitle: appearance == .system ? "Suit le réglage de macOS" : "Réglage de l'application",
                                       trailing: "Basculer", tone: .neutral) {
                appState.appearance = appearance
            })
        }
        for tab in NavigationTab.allCases {
            actions.append(PaletteItem(id: "tab-" + tab.rawValue, section: .actions, title: "Aller à : \(tab.rawValue)",
                                       subtitle: "Navigation", trailing: "Aller", tone: .neutral) {
                appState.selectedTab = tab
            })
        }

        var result = packages + actions.filter { matches($0.title) || matches($0.subtitle) }
        if !needle.isEmpty {
            result.append(PaletteItem(id: "discover-search", section: .actions, title: "Chercher « \(query) » dans tout Homebrew",
                                      subtitle: "Découvrir", trailing: "Chercher", tone: .accent) {
                appState.pendingDiscoverQuery = query
                appState.selectedTab = .discover
            })
        }
        return result
    }

    public var body: some View {
        let list = items
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(Palette.textSecondary)
                TextField("Paquet, action, réglage…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($fieldFocused)
                    .onSubmit { run(list, at: highlighted) }
                    .onKeyPress(.downArrow) {
                        highlighted = min(highlighted + 1, max(list.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(highlighted - 1, 0)
                        return .handled
                    }
                Text("esc")
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.line, lineWidth: 1))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if list.isEmpty {
                            Text("Aucun résultat.")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(Palette.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || list[index - 1].section != item.section {
                                Text(item.section.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(0.6)
                                    .foregroundColor(Palette.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, index == 0 ? 4 : 10)
                                    .padding(.bottom, 2)
                            }
                            row(item, isHighlighted: index == highlighted)
                                .id(item.id)
                                .onTapGesture { run(list, at: index) }
                                .onHover { inside in if inside { highlighted = index } }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 360)
                .onChange(of: highlighted) {
                    if list.indices.contains(highlighted) { proxy.scrollTo(list[highlighted].id) }
                }
            }

            Divider()

            HStack(spacing: 16) {
                Text("↑↓ naviguer")
                Text("↵ ouvrir ou lancer")
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundColor(Palette.textSecondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: 620)
        .background(Palette.surface)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { highlighted = 0 }
        .onExitCommand { dismiss() }
    }

    private func row(_ item: PaletteItem, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold, design: item.section == .packages ? .monospaced : .default))
                    .foregroundColor(Palette.text)
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.trailing)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(item.tone == .neutral ? Palette.textSecondary : item.tone.foreground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isHighlighted ? Palette.accentBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
    }

    private func run(_ list: [PaletteItem], at index: Int) {
        guard list.indices.contains(index) else { return }
        let action = list[index].action
        dismiss()
        action()
    }
}
