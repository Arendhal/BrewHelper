import SwiftUI

/// Fiche d'un paquet : inspecteur de la Bibliothèque, feuille de Découvrir. Pensée pour une
/// colonne étroite : l'essentiel (pourquoi il est là, sécurité, actions) avant le détail technique.
public struct PackageDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) var openURL

    let package: BrewPackage

    public init(package: BrewPackage) {
        self.package = package
    }

    private var isInstalled: Bool { appState.isPackageInstalled(name: package.fullName) || appState.isPackageInstalled(name: package.name) }
    private var dependents: [String] { appState.dependents(of: package) }
    private var isPending: Bool { appState.hasPendingTask(forPackage: package.id) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                facts
                actions
                PackageSecuritySection(package: package)
                technicalDetails
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(package.type == .cask ? "APPLICATION (CASK)" : "OUTIL EN LIGNE DE COMMANDE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundColor(Palette.textSecondary)
            Text(package.name)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(Palette.text)
                .textSelection(.enabled)
            Text(package.description)
                .font(DesignSystem.Typography.body)
                .foregroundColor(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                fact("Installé", isInstalled ? package.installedVersion : "Non installé", mono: isInstalled)
                fact("Dernière version", package.isOutdated ? package.latestVersion : (isInstalled ? "À jour" : package.latestVersion),
                     mono: package.isOutdated || !isInstalled, tone: package.isOutdated ? .accent : nil)
            }
            if isInstalled {
                GridRow {
                    fact("Pourquoi il est là", PackageOrigin.describe(package, dependents: dependents))
                        .gridCellColumns(2)
                }
                if !dependents.isEmpty && package.installedOnRequest {
                    GridRow {
                        fact("Requis aussi par", dependents.joined(separator: ", "))
                            .gridCellColumns(2)
                    }
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String, mono: Bool = false, tone: Tone? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundColor(Palette.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: mono ? .monospaced : .default))
                .foregroundColor(tone?.foreground ?? Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isPending {
                Label("Une commande pour ce paquet est en file — voir l'Activité", systemImage: "hourglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.accentText)
            }
            if !isInstalled {
                Button {
                    appState.executePackageAction(package: package, action: .install)
                } label: {
                    Label("Installer", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isPending)
            } else if package.isOutdated {
                Button {
                    appState.executePackageAction(package: package, action: .upgrade)
                } label: {
                    Label("Mettre à jour vers \(package.latestVersion)", systemImage: "arrow.up.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isPending)
            }
            HStack(spacing: 8) {
                if isInstalled {
                    Button("Réinstaller") { appState.executePackageAction(package: package, action: .reinstall) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(isPending)
                }
                if let url = URL(string: package.homepage), package.homepage != "https://brew.sh" {
                    Button("Site du projet") { openURL(url) }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                if isInstalled {
                    Button("Désinstaller") { appState.executePackageAction(package: package, action: .uninstall) }
                        .buttonStyle(SecondaryButtonStyle(destructive: true))
                        .disabled(isPending)
                }
            }
            if isInstalled {
                Text(uninstallNote)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Ce qu'une désinstallation casserait, dit avant qu'on clique.
    private var uninstallNote: String {
        if dependents.isEmpty { return "Aucun autre paquet installé ne dépend de \(package.name)." }
        return "Requis par \(dependents.joined(separator: ", ")) : Homebrew refusera de le désinstaller tant qu'ils sont là."
    }

    @ViewBuilder
    private var technicalDetails: some View {
        if !package.dependencies.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Dépendances", subtitle: "\(package.dependencies.count)")
                Text(package.dependencies.joined(separator: "  ·  "))
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        if let caveats = package.caveats, !caveats.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Avertissements Homebrew")
                Text(caveats)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(Palette.text)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.warningBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .textSelection(.enabled)
            }
        }
        if package.type == .formula && !package.bottleArchitectures.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Binaires précompilés")
                Text(package.bottleArchitectures.joined(separator: "  ·  "))
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


// MARK: - Section sécurité de la fiche paquet
//
// Rien n'est interrogé à l'ouverture de la fiche : on montre le verdict du dernier audit,
// et l'analyse d'un paquet isolé reste une action explicite.
struct PackageSecuritySection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared

    let package: BrewPackage
    @State private var isChecking: Bool = false

    private var vulnerabilities: [CVEVulnerability] {
        security.cachedVulnerabilities(for: package) ?? []
    }

    private var hasVerdict: Bool {
        security.cachedVulnerabilities(for: package) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let warning = maintenanceWarning {
                verdictCard(icon: "archivebox.fill", color: .orange, title: warning.title, message: warning.message)
            }

            if let failure = security.scanFailures[package.name] {
                verdictCard(icon: "wifi.exclamationmark", color: .red,
                            title: "Vérification impossible",
                            message: "\(failure). Ce paquet n'a pas été comparé aux avis de sécurité : son état est inconnu, pas sain.")
            } else if !hasVerdict {
                verdictCard(icon: "circle.dashed", color: .secondary,
                            title: "Paquet non audité",
                            message: "Aucun verdict en mémoire pour la v\(package.installedVersion). Lancez l'analyse pour comparer cette version aux avis publiés.")
            } else if security.untrackedPackages.contains(package.name) {
                verdictCard(icon: "questionmark.circle.fill", color: .secondary,
                            title: "Produit absent de la base \(security.source.shortLabel)",
                            message: (security.source == .hybrid
                                ? "Ni EUVD ni la NVD ne suivent ce logiciel sous ce nom : l'absence de résultat n'y prouve rien."
                                : "La base interrogée ne suit pas ce logiciel : l'absence de résultat n'y prouve rien. Essayez une autre base depuis l'onglet Audit de Sécurité.")
                                + triedNamesNote)
                ManualVerificationView(package: package)
            } else if vulnerabilities.isEmpty, let unresolved = security.unresolvedAdvisories[package.name] {
                verdictCard(icon: "questionmark.diamond.fill", color: .yellow,
                            title: "Verdict non concluant",
                            message: "Aucune faille confirmée pour la v\(package.installedVersion), mais \(unresolved.count) avis rattaché(s) à ce logiciel ne publient aucune plage de versions : ils n'ont pu être ni confirmés ni écartés. Anciens, ils sont probablement corrigés depuis — à vérifier dans les notes de version du projet.")
                UnresolvedAdvisoriesView(identifiers: unresolved)
                ManualVerificationView(package: package)
            } else if vulnerabilities.isEmpty {
                verdictCard(icon: "checkmark.shield.fill", color: .green,
                            title: "Aucune faille non corrigée pour la version installée",
                            message: "L'audit \(security.source.fullDescription) n'a relevé aucune CVE encore ouverte pour \(package.name) v\(package.installedVersion). Les failles déjà corrigées par cette version ne sont pas listées.")
            } else {
                vulnerabilityList
            }

            if let rejected = security.rejectedAdvisories[package.name], !rejected.isEmpty {
                RejectedAdvisoriesView(advisories: rejected)
            }

            if !vulnerabilities.isEmpty {
                RemediationPlanCard(package: package, vulnerabilities: vulnerabilities)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(vulnerabilities.isEmpty ? .green : .red)
            Text("Audit de Sécurité & Failles CVE (\(security.source.shortLabel))")
                .font(DesignSystem.Typography.sectionHeader)
            Spacer()
            if isChecking {
                ProgressView().controlSize(.small)
                Text("Interrogation de \(security.source.members.first?.shortLabel ?? "")...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                if security.pendingEnrichment.contains(package.name) {
                    ProgressView().controlSize(.small)
                    Text("\(security.source.members.last?.shortLabel ?? "") complète le résultat...")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                }
                Button(hasVerdict ? "Revérifier ce paquet" : "Analyser ce paquet") {
                    Task {
                        isChecking = true
                        _ = await security.checkSinglePackageNow(package: package, force: true)
                        isChecking = false
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    /// Noms amont essayés en plus du nom du paquet : dire ce qui a été cherché rend le « non suivi » vérifiable.
    private var triedNamesNote: String {
        let aliases = ProductAliases.upstreamNames(for: package)
        guard !aliases.isEmpty else { return "" }
        return " Noms amont également interrogés : \(aliases.joined(separator: ", "))."
    }

    /// Ce que Homebrew sait de la maintenance vaut quel que soit le verdict des bases — et pèse
    /// d'autant plus qu'aucune base ne suit le paquet.
    private var maintenanceWarning: (title: String, message: String)? {
        let reason: (String?) -> String = { $0.map { " Motif déclaré par Homebrew : \($0.replacingOccurrences(of: "_", with: " "))." } ?? "" }
        switch package.lifecycle {
        case .disabled(let why):
            return ("Paquet désactivé par Homebrew",
                    "Homebrew ne le construit plus et ne le mettra plus à jour : aucune faille future ne sera corrigée.\(reason(why)) Cherchez un remplaçant.")
        case .deprecated(let why):
            return ("Paquet déprécié par Homebrew",
                    "Il sera désactivé à terme et ne suivra plus les correctifs amont.\(reason(why))")
        case .maintained:
            guard package.isThirdPartyTap, let tap = package.tap else { return nil }
            return ("Formule d'un tap tiers (\(tap))",
                    "Ni la formule ni ses binaires ne sont relus par Homebrew : la confiance repose sur l'auteur du tap.")
        }
    }

    private func verdictCard(icon: String, color: Color, title: String, message: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color == .secondary ? .primary : color)
                    Text(message)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var vulnerabilityList: some View {
        VStack(spacing: 12) {
            Text("\(vulnerabilities.count) faille(s) encore ouverte(s) sur la v\(package.installedVersion), classées par urgence réelle : l'exploitation avérée prime sur le score.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(vulnerabilities) { vulnerability in
                VulnerabilityCard(vulnerability: vulnerability)
            }
        }
    }
}

/// Une faille, avec ce qui permet de décider s'il faut agir aujourd'hui.
struct VulnerabilityCard: View {
    @Environment(\.openURL) var openURL
    let vulnerability: CVEVulnerability

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    StatusBadge(text: vulnerability.id, color: vulnerability.severity.color, icon: "exclamationmark.triangle.fill")
                    StatusBadge(text: "Sévérité : \(vulnerability.severity.localizedLabel)", color: vulnerability.severity.color)
                    if let score = vulnerability.cvssScore {
                        StatusBadge(text: "CVSS : \(String(format: "%.1f", score))", color: vulnerability.severity.color)
                    }
                    Spacer()
                    Text("Publié le : \(vulnerability.publishedDate)")
                        .font(DesignSystem.Typography.monospace)
                        .foregroundColor(.secondary)
                }

                // Renseignement d'exploitation : ce qui distingue une faille théorique
                // d'une faille dont on se sert aujourd'hui.
                if vulnerability.isKnownExploited || vulnerability.epssScore != nil {
                    HStack(spacing: 8) {
                        if vulnerability.isKnownExploited {
                            StatusBadge(text: "Exploitation avérée (CISA KEV)", color: .red, icon: "flame.fill")
                        }
                        if vulnerability.usedByRansomware {
                            StatusBadge(text: "Employée par des rançongiciels", color: .red, icon: "lock.trianglebadge.exclamationmark.fill")
                        }
                        if let epss = vulnerability.epssLabel {
                            StatusBadge(text: "\(epss) de risque d'exploitation à 30 j",
                                        color: (vulnerability.epssScore ?? 0) > 0.1 ? .orange : .secondary,
                                        icon: "chart.line.uptrend.xyaxis")
                        }
                        Spacer()
                    }
                }

                HStack(spacing: 8) {
                    if vulnerability.isConfirmedAffected {
                        StatusBadge(text: vulnerability.verdict.localizedLabel, color: .red, icon: "xmark.shield.fill")
                    } else {
                        StatusBadge(text: vulnerability.verdict.localizedLabel, color: .gray, icon: "questionmark.circle.fill")
                    }
                    if let range = vulnerability.affectedRangeSummary {
                        StatusBadge(text: "Versions affectées : \(range)", color: .secondary)
                    }
                    Spacer()
                }

                Text(vulnerability.description)
                    .font(DesignSystem.Typography.body)
                    .fixedSize(horizontal: false, vertical: true)

                // Pourquoi cet avis a été rattaché à ce paquet : le rapprochement doit être vérifiable.
                if let identity = vulnerability.identity {
                    IdentityBadge(identity: identity)
                }

                // Quelle base a relevé la faille, et la page officielle de chacune.
                HStack(spacing: 8) {
                    Label("Relevée par", systemImage: "externaldrive.connected.to.line.below")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    ForEach(vulnerability.references, id: \.source) { reference in
                        SourceTag(reference: reference)
                    }
                    Spacer()
                }
            }
        }
    }
}

/// Étiquette cliquable d'une base : ouvre la page officielle de la faille chez elle.
struct SourceTag: View {
    @Environment(\.openURL) var openURL
    let reference: VulnReference

    private var color: Color {
        switch reference.source {
        case "EUVD": return .blue
        case "NVD": return .purple
        default: return .gray
        }
    }

    var body: some View {
        Button {
            if let url = URL(string: reference.url) { openURL(url) }
        } label: {
            HStack(spacing: 4) {
                Text(reference.source)
                    .font(.system(size: 11, weight: .bold))
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help("Ouvrir la page \(reference.source) de cette faille : \(reference.url)")
    }
}

/// Le produit publié par la base, la confiance du rapprochement et les indices qui la fondent.
struct IdentityBadge: View {
    let identity: ProductIdentity

    private var color: Color {
        switch identity.confidence {
        case .strong: return .green
        case .probable: return .orange
        case .weak: return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: identity.confidence == .strong ? "checkmark.seal.fill" : "questionmark.diamond.fill")
                .font(.system(size: 11))
                .foregroundColor(color)
            Text("Produit de l'avis : \(identity.summary) — correspondance \(identity.confidence.localizedLabel)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
        .help(identity.reasons.map { "• \($0)" }.joined(separator: "\n"))
    }
}

/// Les avis écartés et pourquoi : ce qui n'est pas retenu doit pouvoir se justifier.
/// Quand aucune base ne tranche, l'utilisateur doit pouvoir vérifier lui-même — sans retaper le
/// nom du paquet dans quatre sites différents.
struct ManualVerificationView: View {
    let package: BrewPackage
    @Environment(\.openURL) private var openURL

    private var links: [(label: String, url: URL)] {
        let names = [ProductNameMatcher.normalize(package.fullName.split(separator: "/").last.map(String.init) ?? package.name)]
            + ProductAliases.upstreamNames(for: package)
        let query = names.first ?? package.name
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var result: [(String, String)] = [
            ("NVD", "https://nvd.nist.gov/vuln/search#/nvd/home?keyword=\(encoded)&resultType=records"),
            ("EUVD", "https://euvd.enisa.europa.eu/search?product=\(encoded)"),
            ("OSV", "https://osv.dev/list?q=\(encoded)"),
        ]
        for candidate in [package.sourceURL, package.homepage].compactMap({ $0 }) {
            guard let url = URL(string: candidate), url.host?.lowercased() == "github.com" else { continue }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2 else { continue }
            result.append(("Avis du dépôt GitHub", "https://github.com/\(parts[0])/\(parts[1])/security/advisories"))
            break
        }
        if let homepage = URL(string: package.homepage), package.homepage != "https://brew.sh" {
            result.append(("Site du projet", homepage.absoluteString))
        }
        return result.compactMap { label, raw in URL(string: raw).map { (label, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Vérification manuelle", systemImage: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                ForEach(links, id: \.label) { link in
                    Button(link.label) { openURL(link.url) }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
                Spacer()
            }
        }
    }
}

/// Avis rattachés au paquet sans plage de versions, que l'audit n'a pu trancher.
struct UnresolvedAdvisoriesView: View {
    let identifiers: [String]
    @Environment(\.openURL) private var openURL
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(identifiers, id: \.self) { identifier in
                    Button(identifier) {
                        let page = identifier.hasPrefix("EUVD-")
                            ? "https://euvd.enisa.europa.eu/vulnerability/\(identifier)"
                            : "https://nvd.nist.gov/vuln/detail/\(identifier)"
                        if let url = URL(string: page) { openURL(url) }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .padding(.top, 6)
        } label: {
            Label("\(identifiers.count) avis non tranché(s)", systemImage: "questionmark.diamond")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
}

struct RejectedAdvisoriesView: View {
    let advisories: [RejectedAdvisory]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(advisories) { advisory in
                    HStack(alignment: .top, spacing: 8) {
                        Text(advisory.advisoryID)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text(advisory.source)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                        Text("« \(advisory.product) » — \(advisory.reason)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label("\(advisories.count) avis écarté(s) : homonyme, extension ou autre plateforme", systemImage: "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
}
