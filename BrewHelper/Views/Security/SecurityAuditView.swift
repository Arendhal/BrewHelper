import SwiftUI

// L'onglet d'audit : on décide quand l'audit part, on voit ce qu'il a réellement pu
// vérifier, et chaque paquet vulnérable est accompagné du chemin concret vers une
// version saine.

public struct SecurityAuditView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared

    @State private var selectedPackage: BrewPackage? = nil
    @State private var searchText: String = ""

    public init() {}

    private var audited: [BrewPackage] {
        appState.packages
            .filter { !searchText.isEmpty ? $0.name.localizedCaseInsensitiveContains(searchText) : true }
            .sorted { security.riskScore(for: $0) > security.riskScore(for: $1) }
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
            if selectedPackage == nil { selectedPackage = audited.first }
        }
    }

    private var auditList: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(audited, selection: $selectedPackage) { package in
                AuditPackageRow(package: package)
                    .tag(package)
                    .padding(.vertical, 3)
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 300, maxWidth: 360)
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
            .background(Color(NSColor.underPageBackgroundColor).opacity(0.4))
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
                        .foregroundColor(security.vulnerableCount > 0 ? .orange : .green)

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

                sourceRow

                if security.hasAuditResults || security.isScanning {
                    AuditSummaryTiles()
                }
            }
        }
    }

    private var statusLine: String {
        if security.isScanning { return "Audit en cours — les paquets sont interrogés en parallèle." }
        guard let date = security.lastAuditDate else {
            return "Aucun audit effectué. L'analyse interroge une base distante paquet par paquet : elle se lance à la demande."
        }
        return "Dernier audit : \(Self.dateFormatter.string(from: date)) — source \(security.source.shortLabel)."
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            if security.isScanning {
                Button(role: .cancel) {
                    security.cancelAudit()
                } label: {
                    Label("Interrompre", systemImage: "stop.circle.fill")
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
            .frame(width: 150)
            .disabled(security.isScanning)

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

    private var openFlawCount: Int {
        security.packageVulnerabilities.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        HStack(spacing: 10) {
            AuditTile(label: "Paquets vulnérables", value: "\(security.vulnerableCount)",
                      color: security.vulnerableCount > 0 ? .orange : .green, icon: "shippingbox.fill")
            AuditTile(label: "Failles ouvertes", value: "\(openFlawCount)",
                      color: openFlawCount > 0 ? .orange : .green, icon: "exclamationmark.triangle.fill")
            AuditTile(label: "Exploitation avérée", value: "\(security.knownExploitedCount)",
                      color: security.knownExploitedCount > 0 ? .red : .green, icon: "flame.fill",
                      help: "Failles inscrites au catalogue KEV de la CISA : leur exploitation en conditions réelles est documentée.")
            AuditTile(label: "Non répertoriés", value: "\(security.untrackedPackages.count)",
                      color: .secondary, icon: "questionmark.circle.fill",
                      help: "Paquets absents de la base interrogée : l'absence de résultat n'y prouve rien.")
            AuditTile(label: "Interrogations échouées", value: "\(security.scanFailures.count)",
                      color: security.scanFailures.isEmpty ? .secondary : .red, icon: "wifi.exclamationmark",
                      help: "Quota dépassé ou service indisponible : ces paquets n'ont pas été vérifiés.")
        }
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
        .background(Color(NSColor.underPageBackgroundColor).opacity(0.3))
    }
}

// MARK: - Ligne de la liste auditée

struct AuditPackageRow: View {
    let package: BrewPackage
    @ObservedObject private var security: CVESecurityService = .shared

    private var flaws: [CVEVulnerability] { security.openFlaws(for: package) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.system(size: 13, weight: .bold))
                    if flaws.contains(where: { $0.isKnownExploited }) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .help("Exploitation avérée (catalogue KEV de la CISA)")
                    }
                }
                Text("v\(package.installedVersion)")
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch package.cveStatus {
        case .vulnerable(let count, let severity):
            StatusBadge(text: "\(count)", color: severity.color, icon: "exclamationmark.triangle.fill")
        case .scanning:
            ProgressView().controlSize(.small)
        case .clean:
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
        case .notTracked:
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary)
                .help("Produit absent de la base interrogée")
        case .error(let reason):
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.red)
                .help(reason)
        case .unscanned:
            Image(systemName: "circle.dashed")
                .foregroundColor(.secondary.opacity(0.5))
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
