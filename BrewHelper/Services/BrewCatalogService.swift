import Foundation

/// Un paquet proposé dans « Découvrir », avec ce qui justifie qu'il le soit.
public struct CatalogItem: Identifiable, Hashable, Sendable {
    public var id: String { (isCask ? "cask-" : "formula-") + name }
    public let name: String
    public let desc: String
    public let homepage: String
    public let version: String
    public let isCask: Bool
    /// Rang parmi les installations des 30 derniers jours (statistiques publiques de Homebrew).
    public let rank: Int?
    /// Installations demandées sur 30 jours.
    public let installs: Int?
    /// Places gagnées par rapport au classement sur un an : ce qui monte en ce moment.
    public let rankGain: Int?

    public init(name: String, desc: String, homepage: String, version: String, isCask: Bool = false,
                rank: Int? = nil, installs: Int? = nil, rankGain: Int? = nil) {
        self.name = name
        self.desc = desc
        self.homepage = homepage
        self.version = version
        self.isCask = isCask
        self.rank = rank
        self.installs = installs
        self.rankGain = rankGain
    }

    public func toBrewPackage() -> BrewPackage {
        return BrewPackage(
            id: id,
            name: name,
            fullName: name,
            type: isCask ? .cask : .formula,
            description: desc,
            homepage: homepage,
            license: "Open Source / Divers",
            installedVersion: "Non installé",
            latestVersion: version,
            isOutdated: false,
            dependencies: [],
            bottleArchitectures: [isCask ? "macOS Universal Cask" : "Apple Silicon / Intel Bottler"],
            caveats: nil
        )
    }
}

/// Une rubrique de « Découvrir » : un titre, ce qui la fonde, et ses paquets.
public struct DiscoverSection: Identifiable, Sendable {
    public enum Kind: String, Sendable { case rising, trendingFormulae, trendingCasks, picks, offline }
    public var id: String { kind.rawValue }
    public let kind: Kind
    public let title: String
    public let subtitle: String
    public let items: [CatalogItem]
}

public struct DiscoverFeed: Sendable {
    public let sections: [DiscoverSection]
    /// Période couverte par les statistiques Homebrew (« 2026-09-25 → 2026-10-25 »), nil hors ligne.
    public let period: String?
}

public class BrewCatalogService: @unchecked Sendable {
    public static let shared = BrewCatalogService()

    // La liste de recommandations était figée dans le code : douze paquets, toujours les mêmes,
    // avec des versions d'une autre année. Elle vient maintenant des statistiques publiques
    // d'installation de Homebrew (actualisées chaque jour) ; cette sélection ne sert plus que
    // hors ligne, et ses versions sont lues localement par `brew info`.
    private static let offlineSelection: [(name: String, isCask: Bool)] = [
        ("bat", false), ("fd", false), ("fzf", false), ("jq", false), ("lazygit", false), ("btop", false),
        ("gh", false), ("starship", false), ("raycast", true), ("iterm2", true), ("visual-studio-code", true), ("orbstack", true)
    ]

    private static let sectionSize = 12
    private static let analyticsCacheFile = "discover-analytics.json"
    private static let analyticsMaxAge: TimeInterval = 24 * 3600

    public init() {}

    /// Rubriques de « Découvrir », sans les paquets déjà installés. `seed` renouvelle la
    /// sélection du jour (bouton « Autre sélection ») ; par défaut elle change chaque jour.
    public func fetchDiscoverFeed(excluding installed: Set<String>, seed: Int? = nil) async -> DiscoverFeed {
        let installedNames = Set(installed.map { $0.lowercased() })
        guard let stats = await loadAnalytics() else {
            let items = await describe(Self.offlineSelection.filter { !installedNames.contains($0.name) }
                .map { RankedName(name: $0.name, isCask: $0.isCask, rank: nil, installs: nil, rankGain: nil) })
            return DiscoverFeed(sections: [DiscoverSection(
                kind: .offline, title: "Sélection",
                subtitle: "Statistiques Homebrew injoignables : sélection fixe, versions lues localement.",
                items: items)], period: nil)
        }

        // Une formule de tap tiers (« hashicorp/tap/terraform ») n'est installable qu'une fois le tap
        // ajouté ; une formule versionnée (« openssl@3 ») est une dépendance plus qu'une découverte.
        func available(_ entries: [AnalyticsEntry]) -> [AnalyticsEntry] {
            entries.filter { !$0.name.contains("/") && !$0.name.contains("@") && !installedNames.contains($0.name.lowercased()) }
        }
        let formulae = available(stats.formulae30d)
        let casks = available(stats.casks30d)

        // Ce qui monte : bien classé ce mois-ci, nettement mieux que sur l'année. Un paquet absent
        // du classement annuel est récent ; il compte comme s'il partait de la fin du classement.
        var yearlyRank: [String: Int] = [:]
        for entry in stats.formulae365d { yearlyRank[entry.name] = min(yearlyRank[entry.name] ?? .max, entry.rank) }
        for entry in stats.casks365d { yearlyRank["cask:" + entry.name] = min(yearlyRank["cask:" + entry.name] ?? .max, entry.rank) }
        func gain(_ entry: AnalyticsEntry, cask: Bool) -> Int {
            let yearly = yearlyRank[(cask ? "cask:" : "") + entry.name] ?? 5_000
            return yearly - entry.rank
        }
        let risingCandidates: [RankedName] = formulae.prefix(1_500).map { entry in
            RankedName(name: entry.name, isCask: false, rank: entry.rank, installs: entry.count, rankGain: gain(entry, cask: false))
        } + casks.prefix(800).map { entry in
            RankedName(name: entry.name, isCask: true, rank: entry.rank, installs: entry.count, rankGain: gain(entry, cask: true))
        }
        func momentum(_ item: RankedName) -> Double {
            Double(item.rankGain ?? 0) / Double(max(item.rank ?? 1, 1))
        }
        // Moitié outils, moitié applications : le classement des casks, plus court, bouge davantage
        // et occuperait sinon toute la rubrique.
        func risingOnes(cask: Bool) -> [RankedName] {
            Array(risingCandidates
                .filter { $0.isCask == cask && ($0.rankGain ?? 0) > 0 && momentum($0) > 1.5 }
                .sorted { momentum($0) > momentum($1) }
                .prefix(Self.sectionSize / 2))
        }
        let risingTools = risingOnes(cask: false), risingApps = risingOnes(cask: true)
        var rising: [RankedName] = []
        for index in 0..<max(risingTools.count, risingApps.count) {
            if index < risingTools.count { rising.append(risingTools[index]) }
            if index < risingApps.count { rising.append(risingApps[index]) }
        }

        let risingNames = Set(rising.map { $0.name })
        func ranked(_ entries: ArraySlice<AnalyticsEntry>, cask: Bool) -> [RankedName] {
            entries.map { RankedName(name: $0.name, isCask: cask, rank: $0.rank, installs: $0.count, rankGain: nil) }
        }
        let topFormulae = ranked(formulae.filter { !risingNames.contains($0.name) }.prefix(Self.sectionSize), cask: false)
        let topCasks = ranked(casks.filter { !risingNames.contains($0.name) }.prefix(Self.sectionSize), cask: true)

        // Au-delà des têtes de classement : un tirage parmi les paquets établis mais moins connus,
        // renouvelé chaque jour pour que la page ne se fige pas.
        let shown = risingNames.union(topFormulae.map { $0.name }).union(topCasks.map { $0.name })
        let pool = ranked(formulae.dropFirst(60).prefix(1_200), cask: false) + ranked(casks.dropFirst(40).prefix(600), cask: true)
        var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed ?? Self.dayNumber()))
        let picks = Array(pool.filter { !shown.contains($0.name) }.shuffled(using: &generator).prefix(Self.sectionSize))

        // Une seule invocation de `brew info` par type pour tout ce qui sera affiché.
        let described = await describe(rising + topFormulae + topCasks + picks)
        var byID: [String: CatalogItem] = [:]
        for item in described where byID[item.id] == nil { byID[item.id] = item }
        func resolve(_ names: [RankedName]) -> [CatalogItem] {
            names.compactMap { byID[($0.isCask ? "cask-" : "formula-") + $0.name] }
        }

        let sections = [
            DiscoverSection(kind: .rising, title: "En forte progression",
                            subtitle: "Bien mieux classés ce mois-ci que sur l'année.", items: resolve(rising)),
            DiscoverSection(kind: .trendingFormulae, title: "Outils en ligne de commande les plus installés",
                            subtitle: "Classement Homebrew des 30 derniers jours, hors paquets déjà installés.", items: resolve(topFormulae)),
            DiscoverSection(kind: .trendingCasks, title: "Applications les plus installées",
                            subtitle: "Casks les plus demandés sur 30 jours.", items: resolve(topCasks)),
            DiscoverSection(kind: .picks, title: "À découvrir aujourd'hui",
                            subtitle: "Tirage parmi des paquets établis mais moins connus, renouvelé chaque jour.", items: resolve(picks)),
        ].filter { !$0.items.isEmpty }
        return DiscoverFeed(sections: sections, period: stats.period)
    }

    private static func dayNumber() -> Int {
        Int(Date().timeIntervalSince1970 / 86_400)
    }

    // MARK: Statistiques d'installation

    struct AnalyticsEntry: Codable, Sendable {
        let name: String
        let rank: Int
        let count: Int
    }

    struct AnalyticsSnapshot: Codable, Sendable {
        let fetchedAt: Date
        let period: String?
        let formulae30d: [AnalyticsEntry]
        let formulae365d: [AnalyticsEntry]
        let casks30d: [AnalyticsEntry]
        let casks365d: [AnalyticsEntry]
    }

    private struct AnalyticsResponse: Decodable {
        struct Item: Decodable {
            let number: Int
            let formula: String?
            let cask: String?
            let count: String
        }
        let start_date: String?
        let end_date: String?
        let items: [Item]
    }

    struct RankedName: Sendable {
        let name: String
        let isCask: Bool
        let rank: Int?
        let installs: Int?
        let rankGain: Int?
    }

    /// Statistiques des 30 derniers jours et de l'année, mises en cache une journée : Homebrew ne
    /// les recalcule qu'une fois par jour. Un cache périmé vaut mieux que rien quand le réseau manque.
    private func loadAnalytics() async -> AnalyticsSnapshot? {
        let cacheURL = BrewHelperStorage.fileURL(named: Self.analyticsCacheFile)
        let cached = cacheURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(AnalyticsSnapshot.self, from: $0) }
        if let cached = cached, Date().timeIntervalSince(cached.fetchedAt) < Self.analyticsMaxAge { return cached }

        let base = "https://formulae.brew.sh/api/analytics"
        async let f30 = fetchAnalytics("\(base)/install-on-request/30d.json")
        async let f365 = fetchAnalytics("\(base)/install-on-request/365d.json")
        async let c30 = fetchAnalytics("\(base)/cask-install/30d.json")
        async let c365 = fetchAnalytics("\(base)/cask-install/365d.json")
        let (formulae30, formulae365, casks30, casks365) = await (f30, f365, c30, c365)

        guard let formulae30 = formulae30, let casks30 = casks30 else { return cached }
        let snapshot = AnalyticsSnapshot(
            fetchedAt: Date(),
            period: [formulae30.start, formulae30.end].compactMap { $0 }.joined(separator: " → "),
            formulae30d: formulae30.entries,
            formulae365d: formulae365?.entries ?? [],
            casks30d: casks30.entries,
            casks365d: casks365?.entries ?? [])
        if let url = cacheURL, let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
        return snapshot
    }

    /// Les 5 000 premiers suffisent : au-delà, les paquets ne totalisent que quelques installations.
    private func fetchAnalytics(_ urlString: String) async -> (entries: [AnalyticsEntry], start: String?, end: String?)? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(AnalyticsResponse.self, from: data) else { return nil }
        let entries = decoded.items.prefix(5_000).compactMap { item -> AnalyticsEntry? in
            guard let name = item.formula ?? item.cask else { return nil }
            // Homebrew écrit les nombres avec des séparateurs de milliers (« 279,001 »).
            let count = Int(item.count.filter { $0.isNumber }) ?? 0
            return AnalyticsEntry(name: name, rank: item.number, count: count)
        }
        return (entries, decoded.start_date, decoded.end_date)
    }

    /// Description, version et site lus par `brew info` (index local, à jour après `brew update`).
    /// Un nom que Homebrew ne connaît plus est simplement omis.
    private func describe(_ names: [RankedName]) async -> [CatalogItem] {
        var seen = Set<String>()
        let unique = names.filter { seen.insert(($0.isCask ? "c:" : "f:") + $0.name).inserted }
        async let formulae = (try? fetchInfo(names: unique.filter { !$0.isCask }.map { $0.name }, flag: "--formula")) ?? []
        async let casks = (try? fetchInfo(names: unique.filter { $0.isCask }.map { $0.name }, flag: "--cask")) ?? []
        let packages = await formulae + casks
        var byKey: [String: BrewPackage] = [:]
        for package in packages {
            let key = (package.type == .cask ? "c:" : "f:") + package.fullName
            if byKey[key] == nil { byKey[key] = package }
        }

        return unique.compactMap { entry in
            guard let package = byKey[(entry.isCask ? "c:" : "f:") + entry.name] else { return nil }
            return CatalogItem(name: entry.name, desc: package.description, homepage: package.homepage,
                               version: package.latestVersion, isCask: entry.isCask,
                               rank: entry.rank, installs: entry.installs, rankGain: entry.rankGain)
        }
    }

    // MARK: - Live Global Homebrew Search
    public func searchGlobalPackages(query: String) async throws -> [BrewPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }
        
        // 1. Search formulae and casks separately so casks are never starved by the formulae
        //    that 'brew search' prints first (the old code kept the first 15 names of the merged output).
        async let formulaeNames = searchNames(query: trimmed, flag: "--formulae")
        async let caskNames = searchNames(query: trimmed, flag: "--casks")
        let (formulae, casks) = try await (formulaeNames, caskNames)
        
        // 2. Rank (exact > prefix > contains) before truncating so the best matches always survive
        func rank(_ name: String) -> Int {
            let short = name.split(separator: "/").last.map(String.init) ?? name
            if short == trimmed { return 0 }
            if short.hasPrefix(trimmed) { return 1 }
            return 2
        }
        let ranked = (formulae.map { ($0, false) } + casks.map { ($0, true) })
            .enumerated()
            .sorted { (rank($0.element.0), $0.offset) < (rank($1.element.0), $1.offset) }
            .map(\.element)
            .prefix(20)
        
        let formulaNames = ranked.filter { !$0.1 }.map(\.0)
        let caskTokens = ranked.filter { $0.1 }.map(\.0)
        
        // 3. Fetch metadata (tap-qualified names such as user/tap/cask are accepted by 'brew info')
        async let formulaPkgs = fetchInfo(names: formulaNames, flag: "--formula")
        async let caskPkgs = fetchInfo(names: caskTokens, flag: "--cask")
        let results = try await formulaPkgs + caskPkgs
        
        return results.sorted {
            let (r0, r1) = (rank($0.fullName), rank($1.fullName))
            return r0 != r1 ? r0 < r1 : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    private func searchNames(query: String, flag: String) async throws -> [String] {
        let result = try await BrewCommandService.shared.runSynchronous(arguments: ["search", flag, query])
        guard let output = String(data: result.data, encoding: .utf8) else { return [] }
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") && !$0.hasPrefix("Warning:") && !$0.hasPrefix("Error:") && !$0.hasPrefix("If you meant") }
    }
    
    /// Batch lookup; if one name makes `brew info` fail (which would drop the whole batch), retry name by name.
    private func fetchInfo(names: [String], flag: String) async throws -> [BrewPackage] {
        guard !names.isEmpty else { return [] }
        if let batch = try await runInfo(names: names, flag: flag), !batch.isEmpty { return batch }
        guard names.count > 1 else { return [] }
        return await withTaskGroup(of: [BrewPackage].self) { group in
            for name in names {
                group.addTask { (try? await self.runInfo(names: [name], flag: flag)) ?? [] }
            }
            var all: [BrewPackage] = []
            for await pkgs in group { all.append(contentsOf: pkgs) }
            return all
        }
    }
    
    private func runInfo(names: [String], flag: String) async throws -> [BrewPackage]? {
        let result = try await BrewCommandService.shared.runSynchronous(arguments: ["info", "--json=v2", flag] + names)
        let clean = BrewCommandService.shared.extractCleanJSONData(from: result.data)
        guard let decoded = try? JSONDecoder().decode(BrewJSONResponseV2.self, from: clean) else { return nil }
        return decoded.formulae.map { $0.toBrewPackage(outdatedList: []) } + decoded.casks.map { $0.toBrewPackage(outdatedList: []) }
    }
}

/// Générateur reproductible : la même graine redonne le même tirage toute la journée.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
