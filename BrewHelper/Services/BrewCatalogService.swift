import Foundation

public struct CatalogItem: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let desc: String
    public let homepage: String
    public let version: String
    public let category: String
    public let isCask: Bool
    
    public init(name: String, desc: String, homepage: String, version: String, category: String, isCask: Bool = false) {
        self.name = name
        self.desc = desc
        self.homepage = homepage
        self.version = version
        self.category = category
        self.isCask = isCask
    }
    
    public func toBrewPackage() -> BrewPackage {
        return BrewPackage(
            id: isCask ? "cask-\(name)" : "formula-\(name)",
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

public class BrewCatalogService: @unchecked Sendable {
    public static let shared = BrewCatalogService()
    
    private var cachedFeatured: [CatalogItem] = [
        // Outils Développeurs
        CatalogItem(name: "bat", desc: "Clone de cat(1) avec coloration syntaxique et intégration Git.", homepage: "https://github.com/sharkdp/bat", version: "0.24.0", category: "CLI Utility"),
        CatalogItem(name: "fd", desc: "Alternative ultra-rapide et conviviale à find.", homepage: "https://github.com/sharkdp/fd", version: "9.0.0", category: "File System"),
        CatalogItem(name: "fzf", desc: "Filtre flou de recherche interactif en ligne de commande.", homepage: "https://github.com/junegunn/fzf", version: "0.54.0", category: "Productivity"),
        CatalogItem(name: "jq", desc: "Processeur de flux JSON en ligne de commande ultra-légendaire.", homepage: "https://jqlang.github.io/jq/", version: "1.7.1", category: "Data Parsing"),
        CatalogItem(name: "lazygit", desc: "Interface utilisateur simple au terminal pour les commandes git.", homepage: "https://github.com/jesseduffield/lazygit", version: "0.43.1", category: "Git & Dev"),
        CatalogItem(name: "btop", desc: "Moniteur de ressources système en terminal avec graphiques somptueux.", homepage: "https://github.com/aristocratos/btop", version: "1.3.2", category: "System Monitor"),
        CatalogItem(name: "gh", desc: "L'outil officiel d'interface en ligne de commande GitHub.", homepage: "https://cli.github.com", version: "2.54.0", category: "GitHub"),
        CatalogItem(name: "starship", desc: "Prompt shell minimaliste, fulgurant et extrêmement personnalisable.", homepage: "https://starship.rs", version: "1.20.1", category: "Shell Customization"),
        // Applications macOS (Casks)
        CatalogItem(name: "raycast", desc: "Lanceur ultra-puissant et remplaçant d'Spotlight avec des extensions infinis.", homepage: "https://raycast.com", version: "Latest", category: "macOS Apps (Cask)", isCask: true),
        CatalogItem(name: "iterm2", desc: "Le terminal de référence avancé pour macOS avec fenêtres partagées et onglets.", homepage: "https://iterm2.com", version: "Latest", category: "macOS Apps (Cask)", isCask: true),
        CatalogItem(name: "visual-studio-code", desc: "L'éditeur de code multi-plateforme ultra-rapide de Microsoft.", homepage: "https://code.visualstudio.com", version: "Latest", category: "macOS Apps (Cask)", isCask: true),
        CatalogItem(name: "orbstack", desc: "Alternative rapide et légère à Docker Desktop pour Linux et Conteneurs.", homepage: "https://orbstack.dev", version: "Latest", category: "macOS Apps (Cask)", isCask: true)
    ]
    
    public init() {}
    
    public func fetchFeaturedItems() async -> [CatalogItem] {
        return cachedFeatured
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
