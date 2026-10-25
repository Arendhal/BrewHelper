import SwiftUI

// La Bibliothèque remplace les onglets Tous / Formulae / Casks / Mises à jour : une seule liste,
// des filtres, et un inspecteur. Chaque ligne dit pourquoi le paquet est là — demandé,
// dépendance de quoi, ou dépendance que plus rien ne requiert.

public enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, requested, dependencies, apps, outdated, vulnerable, inconclusive, untracked, unmaintained

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "Tout"
        case .requested: return "Demandés"
        case .dependencies: return "Dépendances"
        case .apps: return "Apps"
        case .outdated: return "À mettre à jour"
        case .vulnerable: return "Vulnérables"
        case .inconclusive: return "Non concluants"
        case .untracked: return "Non suivis"
        case .unmaintained: return "Non maintenus"
        }
    }

    public func matches(_ package: BrewPackage) -> Bool {
        switch self {
        case .all: return true
        case .requested: return package.installedOnRequest
        case .dependencies: return !package.installedOnRequest
        case .apps: return package.type == .cask
        case .outdated: return package.isOutdated
        case .vulnerable:
            if case .vulnerable = package.cveStatus { return true }
            return false
        case .inconclusive:
            if case .inconclusive = package.cveStatus { return true }
            return false
        case .untracked:
            if case .notTracked = package.cveStatus { return true }
            return false
        case .unmaintained: return !package.lifecycle.isMaintained || package.isThirdPartyTap
        }
    }

    /// Les filtres d'état n'apparaissent que s'ils trient quelque chose.
    var alwaysShown: Bool {
        switch self {
        case .all, .requested, .dependencies, .apps: return true
        default: return false
        }
    }
}

public struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText: String = ""

    public init() {}

    private var rows: [BrewPackage] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return appState.packages
            .filter { appState.libraryFilter.matches($0) }
            .filter { query.isEmpty || $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query) }
    }

    private var selectedPackage: BrewPackage? {
        guard let id = appState.librarySelection else { return nil }
        return appState.packages.first { $0.id == id }
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                filters
                table
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            Group {
                if let package = selectedPackage {
                    PackageDetailView(package: package)
                        .id(package.id)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 28))
                            .foregroundColor(Palette.textSecondary)
                        Text("Sélectionnez un paquet pour voir pourquoi il est là, son état de sécurité et quoi en faire.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 420)
            .frame(maxHeight: .infinity)
            .background(Palette.bar)
        }
        .background(Palette.background)
        .onAppear {
            if appState.librarySelection == nil { appState.librarySelection = rows.first?.id }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Bibliothèque")
                .font(DesignSystem.Typography.title)
                .foregroundColor(Palette.text)
            Text(summary)
                .font(DesignSystem.Typography.body)
                .foregroundColor(Palette.textSecondary)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(Palette.textSecondary)
                TextField("Filtrer par nom ou description", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 240)
            .background(Palette.field)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var summary: String {
        let requested = appState.packages.filter { $0.installedOnRequest }.count
        return "\(appState.packages.count) paquets — \(requested) demandés, \(appState.packages.count - requested) dépendances"
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { filter in
                    let count = appState.packages.filter { filter.matches($0) }.count
                    if filter.alwaysShown || count > 0 || appState.libraryFilter == filter {
                        FilterChip(filter.label, count: count, isOn: appState.libraryFilter == filter) {
                            appState.libraryFilter = filter
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private var table: some View {
        if rows.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: appState.isLoading ? "hourglass" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 26))
                    .foregroundColor(Palette.textSecondary)
                Text(appState.isLoading ? "Lecture des paquets installés..." : "Aucun paquet pour ce filtre.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(rows, selection: $appState.librarySelection) {
                TableColumn("Paquet") { package in
                    HStack(spacing: 8) {
                        KindTag(package.type)
                        Text(package.name)
                            .font(DesignSystem.Typography.packageName)
                            .foregroundColor(Palette.text)
                        if appState.hasPendingTask(forPackage: package.id) {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                .width(min: 160, ideal: 210)
                TableColumn("Version") { package in
                    HStack(spacing: 4) {
                        Text(package.installedVersion)
                            .font(DesignSystem.Typography.monospace)
                            .foregroundColor(Palette.textSecondary)
                        if package.isOutdated {
                            Text("→ \(package.latestVersion)")
                                .font(DesignSystem.Typography.monospace)
                                .foregroundColor(Palette.accentText)
                        }
                    }
                }
                .width(min: 100, ideal: 150)
                TableColumn("Pourquoi il est là") { package in
                    Text(PackageOrigin.describe(package, dependents: appState.dependents(of: package)))
                        .font(.system(size: 12))
                        .foregroundColor(Palette.textTertiary)
                        .lineLimit(1)
                }
                .width(min: 160, ideal: 230)
                TableColumn("Sécurité") { package in
                    SecurityVerdictPill(package: package)
                }
                .width(min: 110, ideal: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.line, lineWidth: 1))
        }
    }
}

/// « Pourquoi il est là », en une phrase.
public enum PackageOrigin {
    public static func describe(_ package: BrewPackage, dependents: [String]) -> String {
        if package.isThirdPartyTap, let tap = package.tap { return "Tap tiers \(tap)" }
        if package.installedOnRequest { return "Installé à votre demande" }
        switch dependents.count {
        case 0: return "Dépendance devenue inutile"
        case 1: return "Dépendance de \(dependents[0])"
        case 2: return "Dépendance de \(dependents[0]) et \(dependents[1])"
        default: return "Dépendance de \(dependents[0]) et \(dependents.count - 1) autres"
        }
    }
}

/// Verdict de sécurité d'un paquet, en une pastille. Une faille confirmée (la version installée
/// est dans la plage touchée) se distingue d'un avis qu'aucune plage ne permet de trancher.
public struct SecurityVerdictPill: View {
    let package: BrewPackage
    @ObservedObject private var security: CVESecurityService = .shared

    public init(package: BrewPackage) { self.package = package }

    public var body: some View {
        let verdict = Self.verdict(for: package, flaws: security.openFlaws(for: package))
        Pill(verdict.label, tone: verdict.tone)
    }

    public static func verdict(for package: BrewPackage, flaws: [CVEVulnerability]) -> (label: String, tone: Tone) {
        switch package.cveStatus {
        case .vulnerable(let count, _):
            let confirmed = flaws.filter { $0.isConfirmedAffected }.count
            if confirmed > 0 { return ("\(confirmed) faille\(confirmed > 1 ? "s" : "")", .danger) }
            return ("\(count) à trancher", .warning)
        case .inconclusive: return ("Non concluant", .warning)
        case .notTracked: return ("Non suivi", .neutral)
        case .clean: return ("Sain", .success)
        case .error: return ("Échec", .danger)
        case .scanning: return ("Analyse…", .neutral)
        case .unscanned: return ("Non audité", .neutral)
        }
    }
}
