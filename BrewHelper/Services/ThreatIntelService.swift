import Foundation
import Combine

// Hiérarchise les failles ouvertes.
//
// Un score CVSS dit la gravité théorique d'une faille, pas si quelqu'un s'en sert. Deux
// sources publiques comblent ce manque et changent complètement l'ordre de traitement :
//
//  · le catalogue KEV de la CISA recense les failles dont l'exploitation en conditions
//    réelles est avérée — une CVE qui y figure est à traiter avant toutes les autres,
//    quel que soit son score ;
//  · l'EPSS (FIRST.org) donne la probabilité qu'une faille soit exploitée dans les
//    trente jours, ce qui départage les dizaines de CVE « élevées » qui ne le seront
//    jamais de la poignée qui compte.
//
// Les deux tiennent en une poignée de requêtes pour tout un audit : le KEV est un seul
// fichier, l'EPSS accepte cent identifiants par appel.

@MainActor
public final class ThreatIntelService: ObservableObject {
    public static let shared = ThreatIntelService()

    /// Identifiants CVE dont l'exploitation est avérée, avec l'usage connu par rançongiciel.
    @Published public private(set) var knownExploited: [String: KEVEntry] = [:]
    /// Probabilité d'exploitation à trente jours, par CVE.
    @Published public private(set) var epssScores: [String: Double] = [:]
    @Published public private(set) var kevRefreshedAt: Date?

    private let urlSession: URLSession = .shared
    private static let kevURL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
    private static let epssURL = "https://api.first.org/data/v1/epss"
    /// Le catalogue KEV bouge de quelques entrées par semaine : le relire une fois par
    /// jour suffit largement et évite un téléchargement de 1,7 Mo à chaque audit.
    private static let kevMaxAge: TimeInterval = 24 * 3600

    public init() {
        loadKEVFromDisk()
    }

    // MARK: - Catalogue KEV

    public func refreshKnownExploitedIfNeeded() async {
        if let refreshed = kevRefreshedAt, Date().timeIntervalSince(refreshed) < Self.kevMaxAge, !knownExploited.isEmpty {
            return
        }
        guard let url = URL(string: Self.kevURL) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("BrewHelper macOS Security Audit", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let catalog = try? JSONDecoder().decode(KEVCatalog.self, from: data) else { return }

        var indexed: [String: KEVEntry] = [:]
        for entry in catalog.vulnerabilities ?? [] {
            indexed[entry.cveID] = entry
        }
        guard !indexed.isEmpty else { return }
        knownExploited = indexed
        kevRefreshedAt = Date()
        saveKEVToDisk(catalog)
    }

    private var kevCacheURL: URL? {
        BrewHelperStorage.fileURL(named: "cisa-kev.json")
    }

    private func loadKEVFromDisk() {
        guard let url = kevCacheURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(KEVCatalog.self, from: data) else { return }
        for entry in catalog.vulnerabilities ?? [] { knownExploited[entry.cveID] = entry }
        kevRefreshedAt = modified
    }

    private func saveKEVToDisk(_ catalog: KEVCatalog) {
        guard let url = kevCacheURL, let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - EPSS

    /// Complète `epssScores` pour les identifiants encore inconnus. L'API accepte cent
    /// CVE par requête, ce qui couvre un audit complet en un ou deux appels.
    public func fetchEPSS(for identifiers: [String]) async {
        let missing = Array(Set(identifiers.filter { $0.hasPrefix("CVE-") && epssScores[$0] == nil }))
        guard !missing.isEmpty else { return }

        for chunk in stride(from: 0, to: missing.count, by: 100).map({ Array(missing[$0..<min($0 + 100, missing.count)]) }) {
            guard var components = URLComponents(string: Self.epssURL) else { continue }
            components.queryItems = [URLQueryItem(name: "cve", value: chunk.joined(separator: ","))]
            guard let url = components.url else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("BrewHelper macOS Security Audit", forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await urlSession.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(EPSSResponse.self, from: data) else { continue }

            for item in decoded.data ?? [] {
                if let score = Double(item.epss) { epssScores[item.cve] = score }
            }
        }
    }

    // MARK: - Application aux résultats d'audit

    /// Retourne les failles enrichies du renseignement disponible localement.
    public func enrich(_ vulnerabilities: [CVEVulnerability]) -> [CVEVulnerability] {
        vulnerabilities.map { flaw in
            var enriched = flaw
            enriched.isKnownExploited = knownExploited[flaw.id] != nil
            enriched.usedByRansomware = knownExploited[flaw.id]?.knownRansomwareCampaignUse?.lowercased() == "known"
            enriched.epssScore = epssScores[flaw.id]
            return enriched
        }
    }
}

// MARK: - Emplacement des caches sur disque

public enum BrewHelperStorage {
    /// Dossier de support de l'application, créé à la demande.
    public static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = base.appendingPathComponent("BrewHelper", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    public static func fileURL(named name: String) -> URL? {
        directory?.appendingPathComponent(name)
    }
}

// MARK: - Modèles des sources de renseignement

public struct KEVCatalog: Codable {
    public let catalogVersion: String?
    public let vulnerabilities: [KEVEntry]?
}

public struct KEVEntry: Codable {
    public let cveID: String
    public let vendorProject: String?
    public let product: String?
    public let vulnerabilityName: String?
    public let dateAdded: String?
    public let requiredAction: String?
    public let knownRansomwareCampaignUse: String?
}

public struct EPSSResponse: Codable {
    public let data: [EPSSItem]?
}

public struct EPSSItem: Codable {
    public let cve: String
    public let epss: String
    public let percentile: String?
}
