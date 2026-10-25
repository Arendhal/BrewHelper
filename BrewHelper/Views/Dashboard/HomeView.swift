import SwiftUI

// L'Accueil répond à deux questions : dans quel état est ce Mac, et que faire en premier.
// La liste « À faire » est classée par risque réel : une faille exploitée passe devant une
// mise à jour de confort, un angle mort de l'audit devant un nettoyage.

public struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared

    public init() {}

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                statusCards
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        todoList.frame(minWidth: 480)
                        sideColumn.frame(width: 300)
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        todoList
                        sideColumn
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .background(Palette.background)
    }

    // MARK: En-tête

    private var requestedCount: Int { appState.packages.filter { $0.installedOnRequest }.count }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Votre Mac")
                    .font(DesignSystem.Typography.largeTitle)
                    .foregroundColor(Palette.text)
                Text(headerDetail)
                    .font(.system(size: 14))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Button {
                appState.synchronizeCatalog()
                appState.runSecurityAudit(force: false)
            } label: {
                Label("Tout vérifier", systemImage: "checkmark.shield")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(security.isScanning)
            .help("Actualise Homebrew et audite les paquets sans verdict pour leur version installée.")
        }
    }

    private var headerDetail: String {
        var parts = ["\(appState.packages.count) paquets — \(requestedCount) installés à votre demande, \(appState.packages.count - requestedCount) dépendances."]
        if let date = security.lastAuditDate {
            parts.append("Dernier audit : \(Self.dateFormatter.string(from: date)).")
        } else {
            parts.append("Aucun audit de sécurité en mémoire.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Cartes d'état

    private var statusCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
            StatusCard(label: "Sécurité", value: securityValue, detail: securityDetail, tone: securityTone) {
                appState.selectedTab = .security
            }
            StatusCard(label: "Couverture de l'audit", value: coverageValue, detail: coverageDetail, tone: coverageTone) {
                appState.selectedTab = .security
            }
            StatusCard(label: "Mises à jour",
                       value: appState.outdatedCount == 0 ? "Tout est à jour" : "\(appState.outdatedCount) disponible\(appState.outdatedCount > 1 ? "s" : "")",
                       detail: updatesDetail,
                       tone: appState.outdatedCount == 0 ? .success : .accent) {
                appState.showLibrary(appState.outdatedCount == 0 ? .all : .outdated)
            }
            StatusCard(label: "Activité", value: activityValue, detail: activityDetail,
                       tone: appState.pendingTaskCount > 0 ? .warning : .neutral) {
                appState.selectedTab = .activity
            }
        }
    }

    private var securityValue: String {
        guard security.hasAuditResults else { return "Non audité" }
        let count = security.vulnerableCount
        return count == 0 ? "Aucune faille ouverte" : "\(count) paquet\(count > 1 ? "s" : "") touché\(count > 1 ? "s" : "")"
    }

    private var securityDetail: String {
        guard security.hasAuditResults else { return "Lancez l'audit pour comparer vos versions aux avis publiés." }
        let exploited = security.knownExploitedCount
        if let worst = worstPackage {
            let flaws = security.openFlaws(for: worst).count
            let tail = exploited > 0 ? "\(exploited) faille(s) exploitée(s) connue(s)." : "Aucune n'est exploitée connue."
            return "\(worst.name) concentre \(flaws) avis. \(tail)"
        }
        return "Aucun avis ouvert pour les versions installées."
    }

    private var securityTone: Tone {
        guard security.hasAuditResults else { return .neutral }
        if security.knownExploitedCount > 0 || confirmedPackages.count > 0 { return .danger }
        return security.vulnerableCount > 0 ? .warning : .success
    }

    private var auditedCount: Int {
        appState.packages.filter {
            switch $0.cveStatus {
            case .clean, .vulnerable, .inconclusive: return true
            default: return false
            }
        }.count
    }

    private var coverageValue: String {
        guard security.hasAuditResults else { return "—" }
        return "\(auditedCount) sur \(appState.packages.count) vérifiés"
    }

    private var coverageDetail: String {
        guard security.hasAuditResults else { return "La couverture s'affichera après le premier audit." }
        var parts: [String] = []
        if !security.untrackedPackages.isEmpty { parts.append("\(security.untrackedPackages.count) suivis par aucune base") }
        if security.inconclusiveCount > 0 { parts.append("\(security.inconclusiveCount) non concluants") }
        if !security.scanFailures.isEmpty { parts.append("\(security.scanFailures.count) échecs d'interrogation") }
        return parts.isEmpty ? "Tous les paquets ont un verdict." : parts.joined(separator: ", ") + "."
    }

    private var coverageTone: Tone {
        guard security.hasAuditResults else { return .neutral }
        return auditedCount == appState.packages.count && security.inconclusiveCount == 0 ? .success : .warning
    }

    private var updatesDetail: String {
        if let date = appState.lastCatalogSync {
            return "Vérifié à \(Self.dateFormatter.string(from: date)) après brew update."
        }
        return appState.isSyncingCatalog ? "Actualisation de Homebrew en cours..." : "D'après le dernier index Homebrew."
    }

    private var activityValue: String {
        let pending = appState.pendingTaskCount
        return pending == 0 ? "Rien en cours" : "\(pending) tâche\(pending > 1 ? "s" : "") en file"
    }

    private var activityDetail: String {
        if let running = appState.runningTask { return running.lastLine ?? running.title }
        if let last = appState.tasks.last(where: { $0.status.isFinished }) { return "Dernière : \(last.title)" }
        return "Les commandes Homebrew s'exécutent ici, une à la fois."
    }

    // MARK: À faire

    private var confirmedPackages: [BrewPackage] {
        appState.packages.filter { package in security.openFlaws(for: package).contains { $0.isConfirmedAffected } }
    }

    private var worstPackage: BrewPackage? {
        appState.packages
            .filter { !security.openFlaws(for: $0).isEmpty }
            .max { security.riskScore(for: $0) < security.riskScore(for: $1) }
    }

    private var todos: [HomeTodo] {
        var items: [HomeTodo] = []
        let packages = appState.packages

        if !security.hasAuditResults && !security.isScanning {
            items.append(HomeTodo(tone: .accent, tag: "Audit", title: "Aucun audit de sécurité",
                                  detail: "Comparez les \(packages.count) paquets installés aux avis EUVD et NVD. L'audit tourne en arrière-plan.",
                                  actionLabel: "Lancer l'audit") { appState.runSecurityAudit(force: true) })
        }

        // Failles exploitées puis confirmées, par risque décroissant.
        let flawed = packages
            .filter { !security.openFlaws(for: $0).isEmpty }
            .sorted { security.riskScore(for: $0) > security.riskScore(for: $1) }
        for package in flawed {
            let flaws = security.openFlaws(for: package)
            let confirmed = flaws.filter { $0.isConfirmedAffected }
            let exploited = flaws.filter { $0.isKnownExploited }
            if !exploited.isEmpty || !confirmed.isEmpty {
                let fix = package.isOutdated
                let detail: String
                if fix {
                    detail = "La version \(package.latestVersion) est disponible dans Homebrew : la mise à jour referme ces failles."
                } else if let range = confirmed.first?.affectedRangeSummary {
                    detail = "Les avis visent \(range), et Homebrew ne publie pas encore de version corrigée."
                } else {
                    detail = "Homebrew ne publie pas encore de version corrigée."
                }
                let count = max(confirmed.count, exploited.count)
                items.append(HomeTodo(tone: .danger, tag: exploited.isEmpty ? "Faille" : "Exploitée",
                                      title: "\(package.name) \(package.installedVersion) — \(count) faille\(count > 1 ? "s" : "") confirmée\(count > 1 ? "s" : "")",
                                      detail: detail,
                                      actionLabel: fix ? "Mettre à jour" : "Voir les failles") {
                    if fix { appState.executePackageAction(package: package, action: .upgrade) } else { appState.selectedTab = .security }
                })
            } else {
                let scoreText = flaws.compactMap { $0.cvssScore }.max()
                    .map { " Noté jusqu'à " + $0.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR"))) + "." } ?? ""
                items.append(HomeTodo(tone: .warning, tag: "À trancher",
                                      title: "\(package.name) — \(flaws.count) avis sans plage de versions",
                                      detail: "Aucune base ne dit quelles versions sont touchées.\(scoreText) Vérification manuelle proposée.",
                                      actionLabel: "Vérifier") { appState.selectedTab = .security })
            }
        }

        let outdatedWithoutFlaws = packages.filter { $0.isOutdated && security.openFlaws(for: $0).isEmpty }
        if !outdatedWithoutFlaws.isEmpty {
            let names = outdatedWithoutFlaws.prefix(3).map { $0.name }.joined(separator: ", ")
            items.append(HomeTodo(tone: .accent, tag: "Mise à jour",
                                  title: "\(outdatedWithoutFlaws.count) mise\(outdatedWithoutFlaws.count > 1 ? "s" : "") à jour disponible\(outdatedWithoutFlaws.count > 1 ? "s" : "")",
                                  detail: names + (outdatedWithoutFlaws.count > 3 ? "…" : "."),
                                  actionLabel: "Tout mettre à jour") { appState.runMaintenance(command: .upgradeAll) })
        }

        if !security.scanFailures.isEmpty {
            items.append(HomeTodo(tone: .danger, tag: "Audit",
                                  title: "\(security.scanFailures.count) paquet(s) non interrogé(s)",
                                  detail: "Quota dépassé ou service indisponible : leur état est inconnu, pas sain.",
                                  actionLabel: "Compléter l'audit") { appState.runSecurityAudit(force: false) })
        }

        if !security.untrackedPackages.isEmpty {
            let apps = packages.filter { $0.type == .cask && security.untrackedPackages.contains($0.name) }.count
            let appText = apps > 0 ? " et \(apps) app\(apps > 1 ? "s" : "")" : ""
            items.append(HomeTodo(tone: .neutral, tag: "Angle mort",
                                  title: "\(security.untrackedPackages.count) paquets suivis par aucune base",
                                  detail: "Surtout des bibliothèques\(appText). L'absence de faille n'y prouve rien.",
                                  actionLabel: "Voir lesquels") { appState.showLibrary(.untracked) })
        }

        let unmaintained = packages.filter { !$0.lifecycle.isMaintained }
        if !unmaintained.isEmpty {
            items.append(HomeTodo(tone: .warning, tag: "Abandon",
                                  title: "\(unmaintained.count) paquet(s) déprécié(s) ou désactivé(s)",
                                  detail: unmaintained.prefix(3).map { $0.name }.joined(separator: ", ") + " ne recevront plus de correctif.",
                                  actionLabel: "Voir lesquels") { appState.showLibrary(.unmaintained) })
        }

        let thirdParty = packages.filter { $0.isThirdPartyTap }
        if let first = thirdParty.first {
            let title = thirdParty.count == 1 ? "\(first.name) vient d'un tap tiers" : "\(thirdParty.count) paquets viennent de taps tiers"
            items.append(HomeTodo(tone: .info, tag: "Confiance", title: title,
                                  detail: "\(first.tap ?? "") : ni la formule ni ses binaires ne sont relus par Homebrew.",
                                  actionLabel: "Comprendre") { appState.showLibrary(.unmaintained, selecting: first.id) })
        }

        let orphans = packages.filter { !$0.installedOnRequest && appState.dependents(of: $0).isEmpty }
        if !orphans.isEmpty {
            items.append(HomeTodo(tone: .neutral, tag: "Nettoyage",
                                  title: "\(orphans.count) dépendance\(orphans.count > 1 ? "s" : "") devenue\(orphans.count > 1 ? "s" : "") inutile\(orphans.count > 1 ? "s" : "")",
                                  detail: orphans.prefix(4).map { $0.name }.joined(separator: ", ") + " : plus aucun paquet installé ne les requiert.",
                                  actionLabel: "Retirer") { appState.enqueue("Retirer les dépendances inutiles", commands: [["autoremove"]]) })
        }
        return items
    }

    private var todoList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("À faire, dans l'ordre", subtitle: "classé par risque réel, pas par date")
            let items = todos
            if items.isEmpty {
                GlassCard {
                    Label("Rien à faire : tout est à jour, audité et sans faille ouverte.", systemImage: "checkmark.circle")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(Palette.success)
                }
            } else {
                ForEach(items) { item in
                    TodoRow(item: item)
                }
            }
        }
    }

    // MARK: Colonne de droite

    private var risingItems: [CatalogItem] {
        let sections = appState.discoverFeed?.sections ?? []
        return Array((sections.first { $0.kind == .rising } ?? sections.first)?.items.prefix(4) ?? [])
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Qui monte sur Homebrew").font(.system(size: 14, weight: .bold)).foregroundColor(Palette.text)
                        Spacer()
                        Button("Découvrir") { appState.selectedTab = .discover }
                            .buttonStyle(.link)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    if risingItems.isEmpty {
                        Text(appState.isLoadingDiscover ? "Lecture des tendances..." : "Tendances indisponibles.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(Palette.textSecondary)
                    }
                    ForEach(risingItems) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(DesignSystem.Typography.packageName).foregroundColor(Palette.text)
                                Text(item.desc).font(DesignSystem.Typography.caption).foregroundColor(Palette.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if let gain = item.rankGain {
                                Text("+\(gain) places").font(.system(size: 11, weight: .semibold)).foregroundColor(Palette.success)
                            }
                        }
                    }
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dernière activité").font(.system(size: 14, weight: .bold)).foregroundColor(Palette.text)
                    let recent = Array(appState.tasks.reversed().prefix(4))
                    if recent.isEmpty {
                        Text("Aucune commande depuis le lancement.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(Palette.textSecondary)
                    }
                    ForEach(recent) { task in
                        HStack(spacing: 8) {
                            Circle().fill(TaskStatusStyle.tone(task.status).mark).frame(width: 7, height: 7)
                            Text(task.title).font(.system(size: 12)).foregroundColor(Palette.text).lineLimit(1)
                            Spacer()
                            Text(TaskStatusStyle.label(task.status)).font(.system(size: 11)).foregroundColor(Palette.textSecondary)
                        }
                    }
                    Button("Tout le journal") { appState.selectedTab = .activity }
                        .buttonStyle(.link)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Éléments

struct HomeTodo: Identifiable {
    let id = UUID()
    let tone: Tone
    let tag: String
    let title: String
    let detail: String
    let actionLabel: String
    let action: () -> Void
}

struct TodoRow: View {
    let item: HomeTodo

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Pill(item.tag, tone: item.tone)
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.text)
                Text(item.detail)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(item.actionLabel, action: item.action)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

struct StatusCard: View {
    let label: String
    let value: String
    let detail: String
    let tone: Tone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle().fill(tone.mark).frame(width: 8, height: 8)
                    Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.textSecondary)
                }
                Text(value)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
