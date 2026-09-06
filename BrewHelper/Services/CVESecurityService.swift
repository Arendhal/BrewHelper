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
    private static let sourceDefaultsKey = "BrewHelper.VulnDatabaseSource"
    private static let apiKeyDefaultsKey = "BrewHelper.NVDAPIKey"
    private static let cacheFileName = "audit-cache.json"

    public init() {
        if let saved = UserDefaults.standard.string(forKey: Self.sourceDefaultsKey),
           let restored = VulnDatabaseSource(rawValue: saved) {
            self.source = restored
        } else {
            self.source = .euvd
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
        scanTask?.cancel()
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: Self.sourceDefaultsKey)
        clearResults()
    }

    public func clearResults() {
        packageVulnerabilities.removeAll()
        scannedVersions.removeAll()
        scanFailures.removeAll()
        untrackedPackages.removeAll()
        scannedCount = 0
        totalToScan = 0
        lastAuditDate = nil
        isScanning = false
        saveToDisk()
    }

    // MARK: - Audit

    public func cancelAudit() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        currentPackageScanned = "Audit interrompu"
    }

    /// Lance l'audit. `force` réexamine aussi les paquets déjà audités contre la même version.
    public func startAudit(for packages: [BrewPackage],
                           force: Bool = false,
                           onUpdate: @escaping (String, PackageCVEStatus) -> Void) {
        scanTask?.cancel()

        let toScan = force ? packages : packages.filter { cachedVulnerabilities(for: $0) == nil }
        guard !toScan.isEmpty else {
            lastAuditDate = Date()
            saveToDisk()
            return
        }

        if force {
            for package in toScan {
                packageVulnerabilities.removeValue(forKey: package.name)
                scannedVersions.removeValue(forKey: package.name)
                scanFailures.removeValue(forKey: package.name)
                untrackedPackages.remove(package.name)
                onUpdate(package.id, .unscanned)
            }
        }

        isScanning = true
        totalToScan = toScan.count
        scannedCount = 0
        currentPackageScanned = ""

        let fetcher = makeFetcher()

        scanTask = Task { [weak self] in
            guard let self = self else { return }

            // Le catalogue KEV sert à hiérarchiser tout le reste : il est chargé d'abord.
            await ThreatIntelService.shared.refreshKnownExploitedIfNeeded()

            await self.scan(toScan, using: fetcher, onUpdate: onUpdate)

            if !Task.isCancelled {
                await self.applyThreatIntel()
                self.lastAuditDate = Date()
                self.currentPackageScanned = "Audit terminé"
                RemediationService.shared.invalidate()
            }
            self.isScanning = false
            self.saveToDisk()
        }
    }

    /// Audite les paquets en parallèle, dans la limite que tolère la base interrogée.
    private func scan(_ packages: [BrewPackage],
                      using fetcher: VulnerabilityFetcher,
                      onUpdate: @escaping (String, PackageCVEStatus) -> Void) async {
        let concurrency = min(fetcher.maxConcurrentRequests, packages.count)

        await withTaskGroup(of: (BrewPackage, ScanOutcome).self) { group in
            var next = 0
            func enqueue() {
                guard next < packages.count else { return }
                let package = packages[next]
                next += 1
                onUpdate(package.id, .scanning)
                group.addTask { (package, await fetcher.fetch(for: package)) }
            }
            for _ in 0..<concurrency { enqueue() }

            while let (package, outcome) = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                currentPackageScanned = package.name
                scannedCount += 1
                apply(outcome, to: package, onUpdate: onUpdate)
                enqueue()
            }
        }
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
        case .found(let flaws):
            scanFailures.removeValue(forKey: package.name)
            untrackedPackages.remove(package.name)
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
        let identifiers = packageVulnerabilities.values.flatMap { $0 }.map { $0.id }
        guard !identifiers.isEmpty else { return }
        await ThreatIntelService.shared.fetchEPSS(for: identifiers)
        for (name, flaws) in packageVulnerabilities {
            let enriched = ThreatIntelService.shared.enrich(flaws)
            packageVulnerabilities[name] = enriched.sorted { $0.riskScore > $1.riskScore }
        }
    }

    public func checkSinglePackageNow(package: BrewPackage, force: Bool = false) async -> [CVEVulnerability] {
        if !force, let cached = cachedVulnerabilities(for: package) { return cached }

        await ThreatIntelService.shared.refreshKnownExploitedIfNeeded()
        let outcome = await makeFetcher().fetch(for: package)
        apply(outcome, to: package) { _, _ in }

        if case .found(let flaws) = outcome, !flaws.isEmpty {
            await ThreatIntelService.shared.fetchEPSS(for: flaws.map { $0.id })
            let enriched = ThreatIntelService.shared.enrich(flaws).sorted { $0.riskScore > $1.riskScore }
            packageVulnerabilities[package.name] = enriched
            if lastAuditDate == nil { lastAuditDate = Date() }
            saveToDisk()
            return enriched
        }
        if lastAuditDate == nil { lastAuditDate = Date() }
        saveToDisk()
        return packageVulnerabilities[package.name] ?? []
    }

    private func store(_ vulnerabilities: [CVEVulnerability], for package: BrewPackage) {
        packageVulnerabilities[package.name] = vulnerabilities
        scannedVersions[package.name] = package.installedVersion
    }

    private func makeFetcher() -> VulnerabilityFetcher {
        VulnerabilityFetcher(source: source, apiKey: nvdAPIKey)
    }

    // MARK: - Persistance
    //
    // Un audit complet coûte plusieurs minutes de requêtes : le perdre à chaque fermeture
    // de l'application le rendrait inutilisable maintenant qu'il est déclenché à la main.

    private struct AuditSnapshot: Codable {
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
        let snapshot = AuditSnapshot(source: source.rawValue,
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
              snapshot.source == source.rawValue else { return }
        scannedVersions = snapshot.versions
        packageVulnerabilities = snapshot.vulnerabilities
        untrackedPackages = Set(snapshot.untracked)
        lastAuditDate = snapshot.date
    }

    // MARK: - Tri et dédoublonnage des avis

    /// Écarte ce que la version installée corrige déjà, puis ordonne du plus récent au
    /// plus ancien (la sévérité ne départage que les entrées du même jour).
    public nonisolated static func openFlawsNewestFirst(_ assessed: [CVEVulnerability]) -> [CVEVulnerability] {
        var deduplicated: [String: CVEVulnerability] = [:]
        for vulnerability in assessed where vulnerability.isStillOpen() {
            // La même faille peut apparaître deux fois (identifiant CVE et alias de base) ;
            // on garde la plus sévère.
            if let existing = deduplicated[vulnerability.id], existing.severity >= vulnerability.severity { continue }
            deduplicated[vulnerability.id] = vulnerability
        }

        return deduplicated.values.sorted { lhs, rhs in
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

    public func fetch(for package: BrewPackage) async -> ScanOutcome {
        switch source {
        case .nvd: return await fetchNVD(for: package)
        case .euvd: return await fetchEUVD(for: package)
        }
    }

    /// Nom du produit tel que les bases le désignent : sans suffixe de branche Homebrew.
    private func productName(for package: BrewPackage) -> String {
        let base = package.fullName.components(separatedBy: "@").first ?? package.fullName
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

    private func fetchNVD(for package: BrewPackage) async -> ScanOutcome {
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
            if items.isEmpty { return .found([]) }
        }

        return .found(CVESecurityService.openFlawsNewestFirst(items.compactMap { $0.cve?.assess(for: package) }))
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

    private func fetchEUVD(for package: BrewPackage) async -> ScanOutcome {
        let product = productName(for: package)
        guard let encoded = product.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .notTracked
        }
        // `product=` cible les produits déclarés par l'avis ; `text=` noierait une formule
        // comme « node » sous les CVE noyau qui emploient le mot.
        let urlString = "https://euvdservices.enisa.europa.eu/api/search?product=\(encoded)&size=50"

        switch await request(EUVDSearchResponse.self, urlString: urlString) {
        case .failure(let reason):
            return .failed(reason)
        case .success(let response):
            guard let items = response.items, !items.isEmpty else {
                return (response.total ?? 0) == 0 ? .notTracked : .found([])
            }
            return .found(CVESecurityService.openFlawsNewestFirst(items.compactMap { $0.assess(for: package) }))
        }
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
