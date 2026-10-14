import Foundation
import Combine
import SwiftUI

// Audit de sécurité des paquets installés.
//
// L'audit ne part plus tout seul au lancement : interroger une base de vulnérabilités
// pour chaque paquet installé prend du temps, consomme du quota d'API et n'a d'intérêt
// que quand on le demande. Le lancement se contente désormais d'actualiser Homebrew ;
// l'audit est déclenché explicitement, et son résultat survit à la fermeture de
// l'application.

/// Ce qu'une interrogation de la base a réellement produit pour un paquet. La distinction
/// compte : une base qui ne connaît pas un produit ne dit pas qu'il est sain, et une
/// requête refusée pour dépassement de quota ne dit rien du tout — les deux ressemblaient
/// pourtant à « aucune faille » dans la version précédente.
public enum ScanOutcome: Sendable {
    case found([CVEVulnerability])
    case notTracked
    case failed(String)
}

/// Ce qu'**une** base a répondu, avant tout filtrage : les avis encore ouverts comme ceux que
/// la version installée corrige déjà. Le tri n'a lieu qu'une fois les bases recoupées, car
/// c'est le recoupement qui départage deux bases en désaccord.
public enum SourceOutcome: Sendable {
    case assessed([CVEVulnerability])
    case notTracked
    case failed(String)
}

/// File de travail à deux niveaux de priorité, alimentée pendant qu'on la consomme : EUVD y
/// verse les paquets au fur et à mesure et la NVD les en retire à son rythme, ceux qu'EUVD ne
/// connaît pas en tête.
actor PriorityWorkQueue<Element: Sendable> {
    private var urgent: [Element] = []
    private var regular: [Element] = []
    private var waiters: [CheckedContinuation<Element?, Never>] = []
    private var closed = false

    func push(_ element: Element, urgent isUrgent: Bool = false) {
        guard !closed else { return }
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: element)
        } else if isUrgent {
            urgent.append(element)
        } else {
            regular.append(element)
        }
    }

    /// Plus rien à venir : les consommateurs en attente repartent les mains vides.
    func close() {
        closed = true
        for waiter in waiters { waiter.resume(returning: nil) }
        waiters.removeAll()
    }

    /// Ferme et jette ce qui n'a pas été pris.
    func cancel() {
        urgent.removeAll()
        regular.removeAll()
        close()
    }

    /// Prend un élément s'il y en a un, sans attendre.
    func take() -> Element? {
        if !urgent.isEmpty { return urgent.removeFirst() }
        if !regular.isEmpty { return regular.removeFirst() }
        return nil
    }

    /// Prend un élément, en attendant qu'il en arrive un tant que la file n'est pas close.
    func next() async -> Element? {
        if let element = take() { return element }
        if closed { return nil }
        return await withCheckedContinuation { waiters.append($0) }
    }
}

@MainActor
public class CVESecurityService: ObservableObject {
    public static let shared = CVESecurityService()

    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var currentPackageScanned: String = ""
    @Published public private(set) var totalToScan: Int = 0
    @Published public private(set) var scannedCount: Int = 0
    @Published public private(set) var source: VulnDatabaseSource
    /// Fin du dernier audit, restaurée depuis le disque au démarrage.
    @Published public private(set) var lastAuditDate: Date? = nil
    /// Paquets dont l'interrogation a échoué, avec le motif : ils ne sont ni sains ni
    /// vulnérables, ils sont inconnus.
    @Published public private(set) var scanFailures: [String: String] = [:]
    /// Paquets absents de la base interrogée.
    @Published public private(set) var untrackedPackages: Set<String> = []

    // Le complément (NVD en mode hybride) tourne sur sa propre file, après et pendant
    // l'audit principal : il a sa progression, et ses échecs n'invalident pas un résultat
    // que l'autre base a déjà fourni.
    @Published public private(set) var isEnriching: Bool = false
    @Published public private(set) var enrichedCount: Int = 0
    @Published public private(set) var totalToEnrich: Int = 0
    @Published public private(set) var currentEnrichmentPackage: String = ""
    /// Paquets que la base de complément n'a pas pu interroger (quota, réseau...).
    @Published public private(set) var enrichmentFailures: Int = 0
    /// Paquets dont le complément est encore attendu : leur verdict peut encore s'étoffer.
    @Published public private(set) var pendingEnrichment: Set<String> = []

    /// Failles encore ouvertes sur la version installée, par paquet. Ce que la version
    /// installée corrige déjà est écarté au moment du scan.
    @Published public var packageVulnerabilities: [String: [CVEVulnerability]] = [:]
    /// Version contre laquelle chaque résultat a été calculé : une mise à jour l'invalide.
    @Published public private(set) var scannedVersions: [String: String] = [:]

    /// Clé d'API NVD. Sans elle NIST limite à 5 requêtes par 30 s ; avec elle, à 50.
    @Published public var nvdAPIKey: String {
        didSet { UserDefaults.standard.set(nvdAPIKey, forKey: Self.apiKeyDefaultsKey) }
    }

    public var vulnerableCount: Int {
        packageVulnerabilities.values.filter { !$0.isEmpty }.count
    }

    /// Failles ouvertes dont l'exploitation est avérée : le sous-ensemble à traiter en premier.
    public var knownExploitedCount: Int {
        packageVulnerabilities.values.flatMap { $0 }.filter { $0.isKnownExploited }.count
    }

    public var hasAuditResults: Bool { lastAuditDate != nil }

    private var scanTask: Task<Void, Never>? = nil
    private var enrichTask: Task<Void, Never>? = nil
    private var primaryQueue: PriorityWorkQueue<BrewPackage>? = nil
    private var enrichmentQueue: PriorityWorkQueue<BrewPackage>? = nil
    /// Réponse de chaque base, par paquet, pour recouper dès qu'une nouvelle arrive. Seul le
    /// résultat recoupé est conservé sur disque.
    private var sourceOutcomes: [String: [VulnDatabaseSource: SourceOutcome]] = [:]
    private static let sourceDefaultsKey = "BrewHelper.VulnDatabaseSource"
    private static let apiKeyDefaultsKey = "BrewHelper.NVDAPIKey"
    private static let cacheFileName = "audit-cache.json"

    public init() {
        if let saved = UserDefaults.standard.string(forKey: Self.sourceDefaultsKey),
           let restored = VulnDatabaseSource(rawValue: saved) {
            self.source = restored
        } else {
            self.source = .hybrid
        }
        self.nvdAPIKey = UserDefaults.standard.string(forKey: Self.apiKeyDefaultsKey) ?? ""
        loadFromDisk()
    }

    /// Résultat mémorisé, tant qu'il a été calculé contre la version présente sur le disque.
    public func cachedVulnerabilities(for package: BrewPackage) -> [CVEVulnerability]? {
        guard scannedVersions[package.name] == package.installedVersion else { return nil }
        return packageVulnerabilities[package.name]
    }

    /// Statut à afficher pour un paquet d'après l'audit mémorisé.
    public func status(for package: BrewPackage) -> PackageCVEStatus {
        if let reason = scanFailures[package.name] { return .error(reason) }
        guard let flaws = cachedVulnerabilities(for: package) else { return .unscanned }
        if untrackedPackages.contains(package.name) { return .notTracked }
        guard let worst = flaws.map({ $0.severity }).max() else { return .clean }
        return .vulnerable(cveCount: flaws.count, highestSeverity: worst)
    }

    /// Risque agrégé d'un paquet : celui de sa faille la plus urgente. Les paquets sans
    /// résultat passent derrière, les échecs d'interrogation devant eux — un audit
    /// incomplet mérite plus d'attention qu'un paquet sain.
    public func riskScore(for package: BrewPackage) -> Double {
        if let flaws = packageVulnerabilities[package.name], !flaws.isEmpty {
            return flaws.map { $0.riskScore }.max() ?? 0
        }
        return scanFailures[package.name] != nil ? -1 : -2
    }

    /// Failles ouvertes d'un paquet, classées de la plus urgente à la moins urgente.
    public func openFlaws(for package: BrewPackage) -> [CVEVulnerability] {
        packageVulnerabilities[package.name] ?? []
    }

    // MARK: - Sélection de la base

    /// Change la base interrogée. Les résultats ne sont pas comparables d'une base à
    /// l'autre : ils sont effacés, et l'audit est à relancer.
    public func switchSource(to newSource: VulnDatabaseSource) {
        guard newSource != source else { return }
        stopWorkers()
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: Self.sourceDefaultsKey)
        clearResults()
    }

    public func clearResults() {
        packageVulnerabilities.removeAll()
        scannedVersions.removeAll()
        scanFailures.removeAll()
        untrackedPackages.removeAll()
        sourceOutcomes.removeAll()
        pendingEnrichment.removeAll()
        scannedCount = 0
        totalToScan = 0
        enrichedCount = 0
        totalToEnrich = 0
        enrichmentFailures = 0
        lastAuditDate = nil
        isScanning = false
        isEnriching = false
        saveToDisk()
    }

    // MARK: - Audit

    public func cancelAudit() {
        stopWorkers()
        isScanning = false
        isEnriching = false
        pendingEnrichment.removeAll()
        currentPackageScanned = "Audit interrompu"
        saveToDisk()
    }

    private func stopWorkers() {
        scanTask?.cancel()
        enrichTask?.cancel()
        scanTask = nil
        enrichTask = nil
        // Les consommateurs bloqués sur une file vide ne verraient jamais l'annulation.
        let queues = [primaryQueue, enrichmentQueue].compactMap { $0 }
        primaryQueue = nil
        enrichmentQueue = nil
        Task { for queue in queues { await queue.cancel() } }
    }

    /// Lance l'audit. `force` réexamine aussi les paquets déjà audités contre la même version.
    ///
    /// La première base de `source.members` porte l'audit. Les suivantes (la NVD en mode
    /// hybride) tournent en parallèle sur leur propre file, avec leur propre cadence : une
    /// base lente ne ralentit jamais la première.
    public func startAudit(for packages: [BrewPackage],
                           force: Bool = false,
                           onUpdate: @escaping (String, PackageCVEStatus) -> Void) {
        stopWorkers()
        isEnriching = false
        pendingEnrichment.removeAll()

        let toScan = force ? packages : packages.filter { cachedVulnerabilities(for: $0) == nil }
        guard !toScan.isEmpty else {
            lastAuditDate = Date()
            saveToDisk()
            return
        }

        for package in toScan {
            sourceOutcomes.removeValue(forKey: package.name)
            if force {
                packageVulnerabilities.removeValue(forKey: package.name)
                scannedVersions.removeValue(forKey: package.name)
                scanFailures.removeValue(forKey: package.name)
                untrackedPackages.remove(package.name)
                onUpdate(package.id, .unscanned)
            }
        }

        let members = source.members
        let primary = members[0]
        let secondary = members.count > 1 ? members[1] : nil

        isScanning = true
        totalToScan = toScan.count
        scannedCount = 0
        currentPackageScanned = ""

        let primaryWork = PriorityWorkQueue<BrewPackage>()
        primaryQueue = primaryWork
        var enrichmentWork: PriorityWorkQueue<BrewPackage>? = nil

        if let secondary = secondary {
            let queue = PriorityWorkQueue<BrewPackage>()
            enrichmentWork = queue
            enrichmentQueue = queue
            isEnriching = true
            enrichedCount = 0
            totalToEnrich = toScan.count
            enrichmentFailures = 0
            currentEnrichmentPackage = ""
            pendingEnrichment = Set(toScan.map { $0.name })

            enrichTask = Task { [weak self] in
                guard let self = self else { return }
                await self.runPool(source: secondary, queue: queue, onStart: { _ in }) { package, outcome in
                    self.enrichedCount += 1
                    self.currentEnrichmentPackage = package.name
                    self.pendingEnrichment.remove(package.name)
                    if case .failed = outcome { self.enrichmentFailures += 1 }
                    self.record(outcome, from: secondary, for: package, onUpdate: onUpdate)
                }
                if !Task.isCancelled {
                    await self.applyThreatIntel()
                    self.lastAuditDate = Date()
                    self.pendingEnrichment.removeAll()
                    self.currentEnrichmentPackage = "Complément \(secondary.shortLabel) terminé"
                    RemediationService.shared.invalidate()
                    self.isEnriching = false
                    self.saveToDisk()
                }
            }
        }

        scanTask = Task { [weak self] in
            guard let self = self else { return }

            // Rempli ici, dans l'ordre et avant la fermeture : des envois lancés en tâches
            // séparées pouvaient se faire doubler par `close()` et être perdus.
            for package in toScan { await primaryWork.push(package) }
            await primaryWork.close()

            // Le catalogue KEV sert à hiérarchiser tout le reste : il est chargé d'abord.
            await ThreatIntelService.shared.refreshKnownExploitedIfNeeded()

            await self.runPool(source: primary, queue: primaryWork, onStart: { package in
                onUpdate(package.id, .scanning)
            }) { package, outcome in
                self.scannedCount += 1
                self.currentPackageScanned = package.name
                self.record(outcome, from: primary, for: package, onUpdate: onUpdate)
                // La base de complément prend la suite : les paquets qu'EUVD ne connaît pas
                // (ou n'a pas pu lire) sont ceux où elle sert le plus, elle les traite d'abord.
                if let queue = enrichmentWork {
                    let needsHelp: Bool
                    switch outcome {
                    case .assessed: needsHelp = false
                    case .notTracked, .failed: needsHelp = true
                    }
                    await queue.push(package, urgent: needsHelp)
                }
            }

            if let queue = enrichmentWork { await queue.close() }

            if !Task.isCancelled {
                await self.applyThreatIntel()
                self.lastAuditDate = Date()
                self.currentPackageScanned = secondary == nil ? "Audit terminé" : "Audit \(primary.shortLabel) terminé"
                RemediationService.shared.invalidate()
            }
            self.isScanning = false
            self.saveToDisk()
        }
    }

    /// Fait travailler une base sur sa file : plusieurs paquets de front dans la limite qu'elle
    /// tolère, sans jamais rester bloqué sur une file vide tant qu'un résultat est en vol.
    private func runPool(source: VulnDatabaseSource,
                         queue: PriorityWorkQueue<BrewPackage>,
                         onStart: @escaping (BrewPackage) -> Void,
                         onResult: @escaping (BrewPackage, SourceOutcome) async -> Void) async {
        let fetcher = VulnerabilityFetcher(source: source, apiKey: nvdAPIKey)
        let concurrency = max(1, fetcher.maxConcurrentRequests)

        await withTaskGroup(of: (BrewPackage, SourceOutcome).self) { group in
            var inFlight = 0

            func launch(_ package: BrewPackage) {
                onStart(package)
                group.addTask { (package, await fetcher.fetchAssessed(for: package)) }
                inFlight += 1
            }

            while !Task.isCancelled {
                while inFlight < concurrency, let package = await queue.take() { launch(package) }

                if inFlight == 0 {
                    // Rien en vol : on peut attendre le prochain paquet sans rien retarder.
                    guard let package = await queue.next() else { break }
                    launch(package)
                    continue
                }
                guard let (package, outcome) = await group.next() else { break }
                inFlight -= 1
                if Task.isCancelled { break }
                await onResult(package, outcome)
            }
            group.cancelAll()
        }
    }

    /// Enregistre la réponse d'une base et recoupe avec celles déjà reçues pour ce paquet.
    private func record(_ outcome: SourceOutcome,
                        from source: VulnDatabaseSource,
                        for package: BrewPackage,
                        onUpdate: @escaping (String, PackageCVEStatus) -> Void) {
        sourceOutcomes[package.name, default: [:]][source] = outcome
        let combined = Self.combine(Array(sourceOutcomes[package.name, default: [:]].values))
        apply(combined, to: package, onUpdate: onUpdate)
    }

    /// Recoupe les réponses des bases. Une base en panne ne masque pas ce que l'autre a
    /// trouvé ; si aucune n'a rien trouvé, une panne l'emporte sur « non suivi » (un audit
    /// incomplet n'est pas un audit négatif).
    nonisolated static func combine(_ outcomes: [SourceOutcome]) -> ScanOutcome {
        var assessed: [CVEVulnerability] = []
        var answered = false
        var failure: String? = nil
        for outcome in outcomes {
            switch outcome {
            case .assessed(let flaws):
                answered = true
                assessed.append(contentsOf: flaws)
            case .notTracked:
                break
            case .failed(let reason):
                failure = failure ?? reason
            }
        }
        if answered { return .found(openFlawsNewestFirst(assessed)) }
        if let failure = failure { return .failed(failure) }
        return .notTracked
    }

    private func apply(_ outcome: ScanOutcome,
                       to package: BrewPackage,
                       onUpdate: @escaping (String, PackageCVEStatus) -> Void) {
        switch outcome {
        case .failed(let reason):
            scanFailures[package.name] = reason
            onUpdate(package.id, .error(reason))
        case .notTracked:
            scanFailures.removeValue(forKey: package.name)
            untrackedPackages.insert(package.name)
            store([], for: package)
            onUpdate(package.id, .notTracked)
        case .found(let found):
            scanFailures.removeValue(forKey: package.name)
            untrackedPackages.remove(package.name)
            // Le renseignement déjà connu (KEV, EPSS) est rejoué : un complément tardif ne
            // doit pas faire perdre le drapeau « exploité » aux failles fusionnées.
            let flaws = ThreatIntelService.shared.enrich(found).sorted { $0.riskScore > $1.riskScore }
            store(flaws, for: package)
            if flaws.isEmpty {
                onUpdate(package.id, .clean)
            } else {
                let worst = flaws.map { $0.severity }.max() ?? .low
                onUpdate(package.id, .vulnerable(cveCount: flaws.count, highestSeverity: worst))
            }
        }
    }

    /// Ajoute aux failles retenues l'exploitation avérée (KEV) et la probabilité
    /// d'exploitation (EPSS), en une poignée de requêtes pour tout l'audit.
    private func applyThreatIntel() async {
        await ThreatIntelService.shared.refreshKnownExploitedIfNeeded()
        let identifiers = packageVulnerabilities.values.flatMap { $0 }.map { $0.id }
        guard !identifiers.isEmpty else { return }
        await ThreatIntelService.shared.fetchEPSS(for: identifiers)
        for (name, flaws) in packageVulnerabilities {
            let enriched = ThreatIntelService.shared.enrich(flaws)
            packageVulnerabilities[name] = enriched.sorted { $0.riskScore > $1.riskScore }
        }
    }

    /// Analyse un paquet isolé. La première base répond avant le retour ; les suivantes
    /// complètent le résultat en arrière-plan, comme pendant un audit complet.
    public func checkSinglePackageNow(package: BrewPackage, force: Bool = false) async -> [CVEVulnerability] {
        if !force, let cached = cachedVulnerabilities(for: package) { return cached }

        let members = source.members
        sourceOutcomes.removeValue(forKey: package.name)
        await ThreatIntelService.shared.refreshKnownExploitedIfNeeded()

        let apiKey = nvdAPIKey
        let primaryOutcome = await VulnerabilityFetcher(source: members[0], apiKey: apiKey).fetchAssessed(for: package)
        record(primaryOutcome, from: members[0], for: package) { _, _ in }
        await refreshThreatIntel(forPackage: package)

        if members.count > 1 {
            let secondary = members[1]
            pendingEnrichment.insert(package.name)
            Task { [weak self] in
                let outcome = await VulnerabilityFetcher(source: secondary, apiKey: apiKey).fetchAssessed(for: package)
                guard let self = self else { return }
                self.pendingEnrichment.remove(package.name)
                self.record(outcome, from: secondary, for: package) { _, _ in }
                await self.refreshThreatIntel(forPackage: package)
            }
        }

        if lastAuditDate == nil { lastAuditDate = Date() }
        saveToDisk()
        return packageVulnerabilities[package.name] ?? []
    }

    private func refreshThreatIntel(forPackage package: BrewPackage) async {
        guard let flaws = packageVulnerabilities[package.name], !flaws.isEmpty else { return }
        await ThreatIntelService.shared.fetchEPSS(for: flaws.map { $0.id })
        packageVulnerabilities[package.name] = ThreatIntelService.shared.enrich(flaws).sorted { $0.riskScore > $1.riskScore }
        saveToDisk()
    }

    private func store(_ vulnerabilities: [CVEVulnerability], for package: BrewPackage) {
        packageVulnerabilities[package.name] = vulnerabilities
        scannedVersions[package.name] = package.installedVersion
    }

    // MARK: - Persistance
    //
    // Un audit complet coûte plusieurs minutes de requêtes : le perdre à chaque fermeture
    // de l'application le rendrait inutilisable maintenant qu'il est déclenché à la main.

    /// Bump whenever the matching / version logic changes: verdicts computed by an older engine
    /// would otherwise survive in the cache and keep showing the old (wrong) results.
    private static let engineVersion = 3

    private struct AuditSnapshot: Codable {
        var engine: Int? = nil
        let source: String
        let date: Date
        let versions: [String: String]
        let vulnerabilities: [String: [CVEVulnerability]]
        let untracked: [String]
    }

    private func saveToDisk() {
        guard let url = BrewHelperStorage.fileURL(named: Self.cacheFileName) else { return }
        guard let date = lastAuditDate else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let snapshot = AuditSnapshot(engine: Self.engineVersion,
                                     source: source.rawValue,
                                     date: date,
                                     versions: scannedVersions,
                                     vulnerabilities: packageVulnerabilities,
                                     untracked: Array(untrackedPackages))
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadFromDisk() {
        guard let url = BrewHelperStorage.fileURL(named: Self.cacheFileName),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(AuditSnapshot.self, from: data),
              // Un audit mené contre une autre base n'est pas comparable au réglage courant.
              snapshot.source == source.rawValue,
              snapshot.engine == Self.engineVersion else { return }
        scannedVersions = snapshot.versions
        packageVulnerabilities = snapshot.vulnerabilities
        untrackedPackages = Set(snapshot.untracked)
        lastAuditDate = snapshot.date
    }

    // MARK: - Tri et dédoublonnage des avis

    /// Recoupe les relevés d'une même faille (une base peut la citer deux fois, deux bases
    /// la citer chacune), écarte ce que la version installée corrige déjà, puis ordonne du
    /// plus récent au plus ancien (la sévérité ne départage que les entrées du même jour).
    ///
    /// Le recoupement précède le filtre : si la NVD établit que la version est corrigée alors
    /// que le texte libre d'EUVD la dit touchée, c'est le verdict le plus fiable qui compte.
    public nonisolated static func openFlawsNewestFirst(_ assessed: [CVEVulnerability]) -> [CVEVulnerability] {
        var merged: [String: CVEVulnerability] = [:]
        for vulnerability in assessed {
            if let existing = merged[vulnerability.id] {
                merged[vulnerability.id] = existing.merged(with: vulnerability)
            } else {
                merged[vulnerability.id] = vulnerability
            }
        }

        return merged.values.filter { $0.isStillOpen() }.sorted { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.id > rhs.id
        }
    }
}

// MARK: - Interrogation des bases
//
// Détaché de l'interface : le travail réseau et l'analyse JSON n'ont aucune raison de
// s'exécuter sur l'acteur principal, et l'audit interroge plusieurs paquets à la fois.

public struct VulnerabilityFetcher: Sendable {
    let source: VulnDatabaseSource
    let apiKey: String
    private let pacer: RequestPacer

    public init(source: VulnDatabaseSource, apiKey: String) {
        self.source = source
        self.apiKey = apiKey
        self.pacer = RequestPacer(interval: source.requestInterval(hasAPIKey: !apiKey.isEmpty))
    }

    var maxConcurrentRequests: Int {
        source.maxConcurrentRequests(hasAPIKey: !apiKey.isEmpty)
    }

    public func fetchAssessed(for package: BrewPackage) async -> SourceOutcome {
        switch source {
        case .nvd: return await fetchNVD(for: package)
        case .euvd, .hybrid: return await fetchEUVD(for: package)
        }
    }

    /// Nom du produit tel que les bases le désignent : sans suffixe de branche Homebrew.
    private func productName(for package: BrewPackage) -> String {
        // A tap formula is "user/tap/name": only the last component names the software.
        let leaf = package.fullName.split(separator: "/").last.map(String.init) ?? package.fullName
        let base = leaf.components(separatedBy: "@").first ?? leaf
        return base.lowercased()
    }

    // MARK: NVD
    //
    // La recherche par mot-clé renvoyait des milliers d'entrées triées de la plus ancienne
    // à la plus récente, dont l'écrasante majorité concernait d'autres logiciels.
    // `virtualMatchString` interroge le dictionnaire CPE en y injectant la version
    // installée : NIST fait lui-même le recoupement de plage et ne renvoie que ce qui vise
    // réellement ce produit dans cette version — 35 entrées pour curl 8.1.0 au lieu de
    // plusieurs milliers. Le verdict local reste appliqué ensuite, pour afficher la plage
    // exacte et écarter ce que la version corrige déjà.

    private static let pageSize = 200

    private func fetchNVD(for package: BrewPackage) async -> SourceOutcome {
        let product = productName(for: package)
        guard let encodedProduct = product.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            return .notTracked
        }
        let version = package.upstreamInstalledVersion
        let encodedVersion = version.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? version
        let base = "https://services.nvd.nist.gov/rest/json/cves/2.0"
        let matchWithVersion = "cpe:2.3:a:*:\(encodedProduct):\(encodedVersion):*:*:*:*:*:*:*"

        let first: NVDCVEResponse
        switch await request(NVDCVEResponse.self,
                             urlString: "\(base)?virtualMatchString=\(matchWithVersion)&resultsPerPage=\(Self.pageSize)") {
        case .failure(let reason): return .failed(reason)
        case .success(let response): first = response
        }

        var items = first.vulnerabilities ?? []
        if let total = first.totalResults, total > Self.pageSize {
            // NIST sert les résultats du plus ancien au plus récent : la dernière page
            // porte les failles récentes, les seules susceptibles d'être encore ouvertes.
            if case .success(let last) = await request(
                NVDCVEResponse.self,
                urlString: "\(base)?virtualMatchString=\(matchWithVersion)&resultsPerPage=\(Self.pageSize)&startIndex=\(total - Self.pageSize)"),
               let recent = last.vulnerabilities {
                items = recent
            }
        }

        if items.isEmpty && (first.totalResults ?? 0) == 0 {
            // Aucun résultat peut signifier « rien à signaler » comme « le nom Homebrew
            // n'est pas celui du dictionnaire CPE » — Node.js y est publié sous « nodejs ».
            // On demande alors au dictionnaire le produit correspondant, et on ne conclut
            // à l'absence de suivi que s'il n'en connaît aucun.
            guard let resolved = await resolveCPEProduct(for: package),
                  resolved != product,
                  let encodedResolved = resolved.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
                return .notTracked
            }
            let retry = "cpe:2.3:a:*:\(encodedResolved):\(encodedVersion):*:*:*:*:*:*:*"
            guard case .success(let response) = await request(
                NVDCVEResponse.self,
                urlString: "\(base)?virtualMatchString=\(retry)&resultsPerPage=\(Self.pageSize)") else {
                return .notTracked
            }
            items = response.vulnerabilities ?? []
            if items.isEmpty { return .assessed([]) }
        }

        return .assessed(items.compactMap { $0.cve?.assess(for: package) })
    }

    /// Nom du produit dans le dictionnaire CPE de NIST. Le nom d'une formule Homebrew ne
    /// correspond pas toujours à celui sous lequel NVD publie le logiciel ; le dictionnaire
    /// fait le pont. Le nom retenu est le plus fréquent parmi ceux que le rapprochement
    /// produit/paquet accepte — « nodewords » ou « network_node_manager » sont écartés,
    /// « nodejs » retenu.
    private func resolveCPEProduct(for package: BrewPackage) async -> String? {
        let name = productName(for: package)
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        guard case .success(let response) = await request(
            NVDCPEResponse.self,
            urlString: "https://services.nvd.nist.gov/rest/json/cpes/2.0?keywordSearch=\(encoded)&resultsPerPage=500") else {
            return nil
        }

        var tally: [String: Int] = [:]
        for product in response.products ?? [] {
            let parts = (product.cpe?.cpeName ?? "").components(separatedBy: ":")
            // cpe:2.3:<partie>:<éditeur>:<produit>:...
            guard parts.count >= 6, parts[2] == "a" else { continue }
            let candidate = parts[4]
            guard ProductNameMatcher.matches(product: candidate, package: package) else { continue }
            tally[candidate, default: 0] += 1
        }
        return tally.max { $0.value < $1.value }?.key
    }

    // MARK: EUVD

    /// `product=` is a fuzzy search served 100 at a time and in no useful order: the first
    /// page alone missed most advisories (curl: 50 of 163, nginx: none of its 11 relevant ones,
    /// OpenSSL 3.0.1: all 67), so every page is read.
    private static let euvdPageSize = 100
    private static let euvdMaxPages = 25

    private func fetchEUVD(for package: BrewPackage) async -> SourceOutcome {
        let product = productName(for: package)
        guard let encoded = product.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .notTracked
        }
        // `product=` cible les produits déclarés par l'avis ; `text=` noierait une formule
        // comme « node » sous les CVE noyau qui emploient le mot.
        var collected: [EUVDItem] = []
        var total = 0

        for page in 0..<Self.euvdMaxPages {
            let urlString = "https://euvdservices.enisa.europa.eu/api/search?product=\(encoded)&size=\(Self.euvdPageSize)&page=\(page)"
            switch await request(EUVDSearchResponse.self, urlString: urlString) {
            case .failure(let reason):
                // A half-read catalogue must not be reported as « aucune faille ».
                return .failed(page == 0 ? reason : "Lecture EUVD incomplète : \(reason)")
            case .success(let response):
                total = response.total ?? total
                let items = response.items ?? []
                collected.append(contentsOf: items)
                if items.isEmpty || collected.count >= total { break }
            }
            if collected.count >= total { break }
        }

        guard total > 0 else { return .notTracked }

        // Every advisory the database returned for a *different* software (xz -> "xzs-mysql")
        // is noise: when none of them concerns this package, EUVD does not track it, which is
        // not the same thing as « aucune faille ».
        let assessed = collected.compactMap { $0.assess(for: package) }
        guard !assessed.isEmpty else { return .notTracked }
        return .assessed(assessed)
    }

    // MARK: Transport
    //
    // Une requête refusée doit se voir. Auparavant tout échec — quota dépassé, coupure
    // réseau, service indisponible — renvoyait une liste vide, que l'interface affichait
    // en vert : un faux « aucune faille » bien plus dangereux qu'une erreur visible.

    private func request<T: Decodable>(_ type: T.Type, urlString: String) async -> FetchResult<T> {
        guard let url = URL(string: urlString) else { return .failure("URL invalide") }

        var lastError = "Échec inconnu"
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(pow(3.0, Double(attempt)) * 1_000_000_000))
            }
            await pacer.acquire()
            if Task.isCancelled { return .failure("Audit interrompu") }

            var urlRequest = URLRequest(url: url)
            urlRequest.timeoutInterval = 20
            urlRequest.setValue("BrewHelper macOS Security Audit", forHTTPHeaderField: "User-Agent")
            if source == .nvd && !apiKey.isEmpty {
                urlRequest.setValue(apiKey, forHTTPHeaderField: "apiKey")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else {
                    lastError = "Réponse illisible"
                    continue
                }
                switch http.statusCode {
                case 200:
                    do {
                        return .success(try JSONDecoder().decode(T.self, from: data))
                    } catch {
                        return .failure("Réponse inattendue de la base")
                    }
                case 403, 429:
                    lastError = source == .nvd && apiKey.isEmpty
                        ? "Quota NVD dépassé (5 requêtes/30 s sans clé d'API)"
                        : "Quota d'interrogation dépassé"
                case 500...599:
                    lastError = "Service indisponible (code \(http.statusCode))"
                default:
                    return .failure("Refus du service (code \(http.statusCode))")
                }
            } catch is CancellationError {
                return .failure("Audit interrompu")
            } catch {
                lastError = "Réseau indisponible"
            }
        }
        return .failure(lastError)
    }
}

/// Issue d'une interrogation : la réponse décodée, ou le motif d'échec tel qu'il sera
/// montré à l'utilisateur.
enum FetchResult<T> {
    case success(T)
    case failure(String)
}

/// Espace les requêtes sortantes pour rester sous le quota de la base interrogée.
public actor RequestPacer {
    private let interval: TimeInterval
    private var nextSlot = Date.distantPast

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    func acquire() async {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(interval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
