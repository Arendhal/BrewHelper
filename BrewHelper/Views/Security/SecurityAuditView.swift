import SwiftUI

// L'onglet d'audit : on décide quand l'audit part, on voit ce qu'il a réellement pu
// vérifier, et chaque paquet vulnérable est accompagné du chemin concret vers une
// version saine.

public struct SecurityAuditView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared

    @State private var selectedPackage: BrewPackage? = nil
    @State private var searchText: String = ""
    /// Les groupes rassurants sont repliés : l'œil va d'abord à ce qui demande une action.
    @State private var collapsed: Set<AuditGroup> = [.clean, .pending]

    public init() {}

    private var audited: [BrewPackage] {
        appState.packages
            .filter { !searchText.isEmpty ? $0.name.localizedCaseInsensitiveContains(searchText) : true }
            .sorted { security.riskScore(for: $0) > security.riskScore(for: $1) }
    }

    private var grouped: [(group: AuditGroup, packages: [BrewPackage])] {
        let all = audited
        return AuditGroup.allCases.compactMap { group in
            let members = all.filter { AuditGroup.classify($0, flaws: security.openFlaws(for: $0)) == group }
            return members.isEmpty ? nil : (group, members)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            AuditControlPanel()
                .padding(20)

            Divider()

            if !security.hasAuditResults && !security.isScanning {
                AuditEmptyState()
            } else {
                HStack(spacing: 0) {
                    auditList
                    Divider()
                    detailPane
                }
            }
        }
        .onChange(of: security.lastAuditDate) {
            if selectedPackage == nil { selectedPackage = grouped.first?.packages.first }
        }
    }

    private var auditList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedPackage) {
                ForEach(grouped, id: \.group) { entry in
                    Section(isExpanded: Binding(
                        get: { !collapsed.contains(entry.group) },
                        set: { expanded in
                            if expanded { collapsed.remove(entry.group) } else { collapsed.insert(entry.group) }
                        })) {
                        ForEach(entry.packages) { package in
                            AuditPackageRow(package: package)
                                .tag(package)
                                .padding(.vertical, 3)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Circle().fill(entry.group.tone.mark).frame(width: 8, height: 8)
                                Text("\(entry.group.title) — \(entry.packages.count)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Palette.text)
                            }
                            Text(entry.group.explanation)
                                .font(.system(size: 11))
                                .foregroundColor(Palette.textSecondary)
                                .textCase(nil)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 320, maxWidth: 380)
        .searchable(text: $searchText, prompt: "Filtrer les paquets audités...")
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selected = selectedPackage {
            PackageDetailView(package: selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selected.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 46))
                    .foregroundColor(.gray.opacity(0.4))
                Text("Sélectionnez un paquet pour consulter ses failles ouvertes et le plan de remédiation associé.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bar)
        }
    }
}

// MARK: - Panneau de contrôle

struct AuditControlPanel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared
    @State private var showsAPIKeyField: Bool = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 26))
                        .foregroundColor(headerColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Audit de Sécurité CVE")
                            .font(DesignSystem.Typography.sectionHeader)
                        Text(statusLine)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    controls
                }

                if security.isScanning {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(security.scannedCount), total: Double(max(security.totalToScan, 1)))
                            .tint(.blue)
                        Text("\(security.scannedCount) / \(security.totalToScan) — \(security.currentPackageScanned)")
                            .font(DesignSystem.Typography.monospace)
                            .foregroundColor(.secondary)
                    }
                }

                if security.isEnriching {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(security.enrichedCount), total: Double(max(security.totalToEnrich, 1)))
                            .tint(.purple)
                        HStack(spacing: 6) {
                            Text("Complément \(security.source.members.last?.shortLabel ?? "") en arrière-plan : \(security.enrichedCount) / \(security.totalToEnrich)")
                            if !security.currentEnrichmentPackage.isEmpty {
                                Text("— \(security.currentEnrichmentPackage)")
                            }
                            if security.enrichmentFailures > 0 {
                                Text("· \(security.enrichmentFailures) non interrogé(s)")
                                    .foregroundColor(.orange)
                            }
                        }
                        .font(DesignSystem.Typography.monospace)
                        .foregroundColor(.secondary)
                    }
                }

                sourceRow

                if security.hasAuditResults || security.isScanning {
                    AuditSummaryTiles()
                }
            }
        }
    }

    /// Vert seulement quand tout a été vérifié : un audit à trous n'est pas un audit sain.
    private var headerColor: Color {
        if security.vulnerableCount > 0 { return .orange }
        let unverified = security.untrackedPackages.count + security.scanFailures.count + security.inconclusiveCount
        return unverified > 0 ? .yellow : .green
    }

    private var statusLine: String {
        if security.isScanning { return "Audit en cours — les paquets sont interrogés en parallèle." }
        if security.isEnriching {
            return "Audit \(security.source.members.first?.shortLabel ?? "") terminé — \(security.source.members.last?.shortLabel ?? "") complète les résultats en arrière-plan."
        }
        guard let date = security.lastAuditDate else {
            return "Aucun audit effectué. L'analyse interroge une base distante paquet par paquet : elle se lance à la demande."
        }
        return "Dernier audit : \(Self.dateFormatter.string(from: date)) — source \(security.source.shortLabel)."
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            if security.isScanning || security.isEnriching {
                Button(role: .cancel) {
                    security.cancelAudit()
                } label: {
                    Label(security.isScanning ? "Interrompre" : "Interrompre le complément",
                          systemImage: "stop.circle.fill")
                }
                .buttonStyle(.bordered)
            } else {
                ActionButton(title: security.hasAuditResults ? "Relancer l'audit complet" : "Lancer l'audit de sécurité",
                             icon: "shield.lefthalf.filled",
                             gradient: DesignSystem.Colors.primaryGradient) {
                    appState.runSecurityAudit(force: true)
                }
                if security.hasAuditResults {
                    Button {
                        // N'interroge que ce qui n'a pas encore de verdict pour la version
                        // actuellement installée : idéal après une mise à jour.
                        appState.runSecurityAudit(force: false)
                    } label: {
                        Label("Compléter", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .help("Audite uniquement les paquets sans verdict pour leur version installée.")
                }
            }
        }
    }

    private var sourceRow: some View {
        HStack(spacing: 12) {
            Text("Base :")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Picker("", selection: Binding(
                get: { security.source },
                set: { security.switchSource(to: $0) }
            )) {
                ForEach(VulnDatabaseSource.allCases) { source in
                    Text(source.shortLabel).tag(source)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 270)
            .disabled(security.isScanning || security.isEnriching)

            Text(security.source.coverageNote)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if security.source.needsAPIKey {
                Button {
                    showsAPIKeyField.toggle()
                } label: {
                    Label(security.nvdAPIKey.isEmpty ? "Clé d'API NVD" : "Clé enregistrée",
                          systemImage: security.nvdAPIKey.isEmpty ? "key" : "key.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showsAPIKeyField) {
                    APIKeyEditor()
                }
            }
        }
    }
}

/// Sans clé, NIST plafonne à 5 requêtes par 30 s : un audit d'une centaine de paquets
/// dure une dizaine de minutes. La clé est gratuite et fait passer la limite à 50.
struct APIKeyEditor: View {
    @ObservedObject private var security: CVESecurityService = .shared
    @Environment(\.openURL) var openURL
    @State private var isChecking = false
    @State private var check: CVESecurityService.KeyCheck? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clé d'API NVD (NIST)")
                .font(.system(size: 14, weight: .bold))
            Text("Sans clé, NIST limite à 5 requêtes par 30 secondes et refuse les suivantes. Avec une clé — gratuite — la limite passe à 50, et l'audit interroge 4 paquets de front au lieu d'un seul.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Coller la clé ici", text: $security.nvdAPIKey)
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Typography.monospace)
            HStack(spacing: 8) {
                Button {
                    Task {
                        isChecking = true
                        check = await security.checkNVDKey()
                        isChecking = false
                    }
                } label: {
                    Label("Tester la clé", systemImage: "checkmark.seal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(security.nvdAPIKey.isEmpty || isChecking)
                if isChecking { ProgressView().controlSize(.small) }
                switch check {
                case .valid:
                    Label("Clé acceptée", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundColor(.green)
                case .rejected:
                    Label("Clé refusée par NIST", systemImage: "xmark.circle.fill")
                        .font(.system(size: 11)).foregroundColor(.red)
                case .unreachable(let reason):
                    Label(reason, systemImage: "wifi.exclamationmark")
                        .font(.system(size: 11)).foregroundColor(.orange)
                case nil:
                    EmptyView()
                }
            }
            .onChange(of: security.nvdAPIKey) { check = nil }
            HStack {
                Button("Demander une clé") {
                    if let url = URL(string: "https://nvd.nist.gov/developers/request-an-api-key") {
                        openURL(url)
                    }
                }
                .buttonStyle(.link)
                Spacer()
                if !security.nvdAPIKey.isEmpty {
                    Button("Retirer") { security.nvdAPIKey = "" }
                        .buttonStyle(.link)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

struct AuditSummaryTiles: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared

    private var unmaintainedCount: Int {
        appState.packages.filter { !$0.lifecycle.isMaintained }.count
    }

    /// Répartition des paquets installés : ce que l'audit a établi, et ce qu'il n'a pas pu établir.
    private var segments: [(label: String, count: Int, tone: Tone, filter: LibraryFilter)] {
        var touched = 0, inconclusive = 0, untracked = 0, unknown = 0, clean = 0
        for package in appState.packages {
            switch package.cveStatus {
            case .vulnerable: touched += 1
            case .inconclusive: inconclusive += 1
            case .notTracked: untracked += 1
            case .clean: clean += 1
            case .error, .unscanned, .scanning: unknown += 1
            }
        }
        return [
            ("touchés", touched, .danger, .vulnerable),
            ("non concluants", inconclusive, .warning, .inconclusive),
            ("non suivis", untracked, .neutral, .untracked),
            ("sans verdict", unknown, .info, .all),
            ("sains", clean, .success, .all)
        ].filter { $0.count > 0 }
    }

    var body: some View {
        let parts = segments
        let clean = parts.first { $0.label == "sains" }?.count ?? 0
        let others = appState.packages.count - clean
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(clean) paquet\(clean > 1 ? "s" : "") vérifié\(clean > 1 ? "s" : "") sain\(clean > 1 ? "s" : "").")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Palette.text)
                if others > 0 {
                    Text("Les \(others) autres ne le sont pas, pour des raisons différentes.")
                        .font(.system(size: 14))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.label) { part in
                        Rectangle()
                            .fill(part.tone.mark)
                            .frame(width: max(4, (proxy.size.width - CGFloat(parts.count - 1) * 2) * CGFloat(part.count) / CGFloat(max(appState.packages.count, 1))))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel(parts.map { "\($0.count) \($0.label)" }.joined(separator: ", "))

            HStack(spacing: 18) {
                ForEach(parts, id: \.label) { part in
                    Button {
                        if part.filter != .all { appState.showLibrary(part.filter) }
                    } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(part.tone.mark).frame(width: 10, height: 10)
                            Text("\(part.count) \(part.label)")
                                .font(.system(size: 12))
                                .foregroundColor(Palette.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(part.filter == .all ? "" : "Voir ces paquets dans la Bibliothèque")
                }
                Spacer()
                if security.knownExploitedCount > 0 {
                    Pill("\(security.knownExploitedCount) faille(s) exploitée(s) — catalogue KEV", tone: .danger, icon: "flame.fill")
                } else if security.hasAuditResults {
                    Pill("Aucune faille exploitée connue (KEV)", tone: .success, icon: "checkmark")
                }
                if unmaintainedCount > 0 {
                    Pill("\(unmaintainedCount) non maintenu(s)", tone: .warning, icon: "archivebox")
                }
            }
        }
        .padding(16)
        .background(Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AuditTile: View {
    let label: String
    let value: String
    let color: Color
    let icon: String
    var help: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.10))
        .cornerRadius(10)
        .help(help ?? label)
    }
}

struct AuditEmptyState: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 52))
                .foregroundColor(.blue.opacity(0.5))
            Text("Aucun audit en mémoire")
                .font(.system(size: 16, weight: .bold))
            Text("L'audit compare chaque paquet installé aux avis de sécurité publiés, puis n'affiche que les failles encore ouvertes pour la version présente sur ce Mac. Il n'est pas lancé automatiquement : le démarrage se contente d'actualiser Homebrew.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            ActionButton(title: "Lancer l'audit maintenant", icon: "play.fill",
                         gradient: DesignSystem.Colors.primaryGradient) {
                appState.runSecurityAudit(force: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

// MARK: - Ligne de la liste auditée

/// Ce que l'audit a établi pour un paquet, du plus grave au plus rassurant. Un paquet n'appartient
/// qu'à un groupe : une faille confirmée l'emporte sur un avis à trancher, qui l'emporte sur un
/// verdict non concluant.
enum AuditGroup: Int, CaseIterable, Hashable {
    case confirmed, toDecide, failed, inconclusive, untracked, pending, clean

    static func classify(_ package: BrewPackage, flaws: [CVEVulnerability]) -> AuditGroup {
        switch package.cveStatus {
        case .vulnerable:
            return flaws.contains { $0.isConfirmedAffected || $0.isKnownExploited } ? .confirmed : .toDecide
        case .inconclusive: return .inconclusive
        case .notTracked: return .untracked
        case .error: return .failed
        case .unscanned, .scanning: return .pending
        case .clean: return .clean
        }
    }

    var title: String {
        switch self {
        case .confirmed: return "Failles confirmées"
        case .toDecide: return "Avis à trancher"
        case .failed: return "Interrogations échouées"
        case .inconclusive: return "Non concluants"
        case .untracked: return "Non suivis"
        case .pending: return "En attente d'audit"
        case .clean: return "Sains"
        }
    }

    var explanation: String {
        switch self {
        case .confirmed: return "La version installée est dans la plage touchée."
        case .toDecide: return "Avis récents sans plage de versions : à vérifier."
        case .failed: return "Quota ou réseau : état inconnu, pas sain."
        case .inconclusive: return "Aucune faille confirmée, avis anciens non tranchés."
        case .untracked: return "Absents d'EUVD et de la NVD, même sous leur nom amont."
        case .pending: return "Pas encore comparés aux avis pour cette version."
        case .clean: return "Aucun avis ouvert pour la version installée."
        }
    }

    var tone: Tone {
        switch self {
        case .confirmed, .failed: return .danger
        case .toDecide, .inconclusive: return .warning
        case .untracked, .pending: return .neutral
        case .clean: return .success
        }
    }
}

struct AuditPackageRow: View {
    let package: BrewPackage
    @ObservedObject private var security: CVESecurityService = .shared

    private var flaws: [CVEVulnerability] { security.openFlaws(for: package) }

    /// Ce que l'audit a établi, en une ligne : la plage touchée, la gravité, ou la raison du doute.
    private var summary: String {
        let confirmed = flaws.filter { $0.isConfirmedAffected }
        if let range = confirmed.first?.affectedRangeSummary {
            let fix = package.isOutdated ? "corrigé en \(package.latestVersion)" : "pas de correctif publié"
            return "touche \(range) · \(fix)"
        }
        if !flaws.isEmpty {
            let score = flaws.compactMap { $0.cvssScore }.max()
                .map { " · jusqu'à " + $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR"))) } ?? ""
            return "\(flaws.count) avis sans plage\(score)"
        }
        switch package.cveStatus {
        case .inconclusive(let unresolved): return "\(unresolved) avis anciens non tranchés"
        case .error(let reason): return reason
        default: return package.installedVersion
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(DesignSystem.Typography.packageName)
                        .foregroundColor(Palette.text)
                    if flaws.contains(where: { $0.isKnownExploited }) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Palette.danger)
                            .help("Exploitation avérée (catalogue KEV de la CISA)")
                    }
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if security.pendingEnrichment.contains(package.name) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.textSecondary)
                    .help("Complément NVD en attente : ce verdict peut encore s'étoffer")
            }
            if case .scanning = package.cveStatus {
                ProgressView().controlSize(.small)
            } else {
                SecurityVerdictPill(package: package)
            }
        }
    }
}

// MARK: - Plan de remédiation

/// Ce qu'il faut faire du paquet, et ce qui empêche éventuellement de le faire.
public struct RemediationPlanCard: View {
    @EnvironmentObject var appState: AppState

    let package: BrewPackage
    let vulnerabilities: [CVEVulnerability]

    @State private var plan: RemediationPlan? = nil
    @State private var isBuilding: Bool = false

    public init(package: BrewPackage, vulnerabilities: [CVEVulnerability]) {
        self.package = package
        self.vulnerabilities = vulnerabilities
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundColor(.blue)
                Text("Que faire de ce paquet")
                    .font(DesignSystem.Typography.sectionHeader)
                Spacer()
                if isBuilding {
                    ProgressView().controlSize(.small)
                    Text("Analyse des dépendances installées...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if let plan = plan {
                planBody(plan)
            } else if !isBuilding {
                Text("Plan de remédiation non calculé.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(.secondary)
            }
        }
        .task(id: package.id) { await build() }
    }

    private func build() async {
        if let cached = RemediationService.shared.cachedPlan(for: package) {
            plan = cached
            return
        }
        isBuilding = true
        plan = await RemediationService.shared.plan(for: package, vulnerabilities: vulnerabilities)
        isBuilding = false
    }

    @ViewBuilder
    private func planBody(_ plan: RemediationPlan) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: plan.kind.icon)
                        .font(.system(size: 22))
                        .foregroundColor(plan.kind.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.headline)
                            .font(.system(size: 14, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(plan.rationale)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    StatusBadge(text: plan.kind.localizedTitle, color: plan.kind.accentColor, icon: plan.kind.icon)
                    if let fixedIn = plan.fixedInVersion {
                        StatusBadge(text: "Correctif en \(fixedIn)", color: .green, icon: "bandage.fill")
                    }
                    if let replacement = plan.replacement {
                        StatusBadge(text: "Cible : \(replacement)", color: .purple, icon: "arrow.right.circle.fill")
                    }
                    Spacer()
                }

                if !plan.blockers.isEmpty {
                    BlockersSection(blockers: plan.blockers, packageName: package.fullName)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Marche à suivre")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                        RemediationStepRow(index: index + 1, step: step)
                    }
                }
            }
        }
    }
}

struct RemediationStepRow: View {
    @EnvironmentObject var appState: AppState
    let index: Int
    let step: RemediationStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.blue.opacity(0.15)))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(step.detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = step.commandLine {
                    Text(line)
                        .font(DesignSystem.Typography.monospace)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            if step.command != nil {
                Button {
                    appState.runRemediationStep(step)
                } label: {
                    Label("Exécuter", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isCommandRunning)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

/// La question qui bloque en pratique : « je ne peux pas retirer la v1, telle autre
/// application la réclame ». La réponse dépend de chaque dépendant, pas du paquet.
struct BlockersSection: View {
    let blockers: [RemediationBlocker]
    let packageName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paquets installés qui dépendent encore de \(packageName)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)

            ForEach(blockers) { blocker in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: blocker.resolution == .stillRequiresOldVersion ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 11))
                        .foregroundColor(blocker.resolution == .stillRequiresOldVersion ? .red : .green)
                        .frame(width: 16)
                    Text(blocker.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text("— \(blocker.localizedVerdict)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }
}
