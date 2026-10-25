import Foundation

public struct BrewPackage: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let fullName: String
    public let type: PackageType
    public let description: String
    public let homepage: String
    public let license: String
    public let installedVersion: String
    public let latestVersion: String
    public var isOutdated: Bool
    public var cveStatus: PackageCVEStatus
    public let dependencies: [String]
    public let bottleArchitectures: [String]
    public let caveats: String?
    /// URL de l'archive source (`urls.stable.url`) : avec la page d'accueil, elle désigne le
    /// projet amont, ce qui permet de reconnaître ses avis par leurs références.
    public let sourceURL: String?
    /// Tap d'origine (`homebrew/core`, `user/tap`...). Hors `homebrew/*`, personne ne relit la formule.
    public let tap: String?
    /// État de maintenance déclaré par Homebrew : un logiciel abandonné n'aura plus d'avis ni de correctif.
    public let lifecycle: PackageLifecycle
    /// Installé à la demande de l'utilisateur, et non tiré comme dépendance. Un cask l'est toujours.
    public let installedOnRequest: Bool

    public init(
        id: String,
        name: String,
        fullName: String,
        type: PackageType,
        description: String,
        homepage: String,
        license: String,
        installedVersion: String,
        latestVersion: String,
        isOutdated: Bool = false,
        cveStatus: PackageCVEStatus = .unscanned,
        dependencies: [String] = [],
        bottleArchitectures: [String] = [],
        caveats: String? = nil,
        sourceURL: String? = nil,
        tap: String? = nil,
        lifecycle: PackageLifecycle = .maintained,
        installedOnRequest: Bool = true
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.type = type
        self.description = description
        self.homepage = homepage
        self.license = license
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.isOutdated = isOutdated
        self.cveStatus = cveStatus
        self.dependencies = dependencies
        self.bottleArchitectures = bottleArchitectures
        self.caveats = caveats
        self.sourceURL = sourceURL
        self.tap = tap
        self.lifecycle = lifecycle
        self.installedOnRequest = installedOnRequest
    }

    /// Hors des taps officiels de Homebrew, ni les bottles ni la formule ne sont relues par le projet.
    public var isThirdPartyTap: Bool {
        guard let tap = tap, !tap.isEmpty else { return false }
        return !tap.hasPrefix("homebrew/")
    }
}

/// Ce que Homebrew déclare de la maintenance d'un paquet. Précieux justement quand aucune base de
/// vulnérabilités ne le suit : un logiciel déprécié ou désactivé ne recevra plus de correctif.
public enum PackageLifecycle: Hashable, Sendable {
    case maintained
    case deprecated(reason: String?)
    case disabled(reason: String?)

    public var isMaintained: Bool {
        if case .maintained = self { return true }
        return false
    }

    static func from(deprecated: Bool?, disabled: Bool?, reason: String?) -> PackageLifecycle {
        if disabled == true { return .disabled(reason: reason) }
        if deprecated == true { return .deprecated(reason: reason) }
        return .maintained
    }
}

public enum PackageType: String, CaseIterable, Codable, Hashable, Sendable {
    case formula = "formula"
    case cask = "cask"
}

public enum PackageCVEStatus: Hashable, Sendable {
    case unscanned
    case scanning
    case clean
    /// La base interrogée ne connaît pas ce produit : un badge vert serait mensonger,
    /// l'absence de résultat ne prouve rien pour un paquet qu'elle ne suit pas.
    case notTracked
    case vulnerable(cveCount: Int, highestSeverity: CVESeverity)
    /// Aucune faille confirmée, mais des avis sans plage de versions n'ont pas pu être tranchés :
    /// ce n'est ni un paquet sain ni un paquet vulnérable.
    case inconclusive(unresolved: Int)
    case error(String)
}

// MARK: - JSON Decoding DTOs for Homebrew v2 JSON
public struct BrewJSONResponseV2: Codable {
    public let formulae: [FormulaDTO]
    public let casks: [CaskDTO]
}

public struct FormulaDTO: Codable {
    public let name: String
    public let fullName: String?
    public let desc: String?
    public let homepage: String?
    public let versions: FormulaVersionsDTO?
    public let installed: [FormulaInstalledDTO]?
    public let dependencies: [String]?
    public let caveats: String?
    public let bottle: FormulaBottleDTO?
    public let outdated: Bool?
    public let urls: FormulaURLsDTO?
    public let tap: String?
    public let deprecated: Bool?
    public let disabled: Bool?
    public let deprecationReason: String?

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case urls
        case tap
        case deprecated
        case disabled
        case deprecationReason = "deprecation_reason"
        case desc
        case homepage
        case versions
        case installed
        case dependencies
        case caveats
        case bottle
        case outdated
    }

    public func toBrewPackage(outdatedList: Set<String>) -> BrewPackage {
        let latestVer = versions?.stable ?? "inconnaissable"
        let installedVersions = installed?.map { $0.version } ?? []
        let hasLatestInstalled = installedVersions.contains(latestVer)

        let currentVer: String
        if hasLatestInstalled {
            currentVer = latestVer
        } else {
            currentVer = installedVersions.last ?? latestVer
        }

        // Trust brew's own freshly-computed "outdated" flag first (same source `brew outdated` uses);
        // fall back to version-string comparison only when brew didn't report it.
        let isOut: Bool
        if let flag = outdated {
            isOut = flag || outdatedList.contains(name)
        } else if hasLatestInstalled || currentVer == latestVer || latestVer == "inconnaissable" {
            isOut = false
        } else {
            isOut = outdatedList.contains(name) || (currentVer != latestVer)
        }
        
        var architectures: [String] = []
        if let files = bottle?.stable?.files {
            architectures = Array(files.keys).sorted()
        }
        
        return BrewPackage(
            id: "formula-\(name)",
            name: name,
            fullName: fullName ?? name,
            type: .formula,
            description: desc ?? "Aucune description fournie.",
            homepage: homepage ?? "https://brew.sh",
            license: "Open Source",
            installedVersion: currentVer,
            latestVersion: latestVer,
            isOutdated: isOut,
            dependencies: dependencies ?? [],
            bottleArchitectures: architectures,
            caveats: caveats,
            sourceURL: urls?.stable?.url,
            tap: tap,
            lifecycle: .from(deprecated: deprecated, disabled: disabled, reason: deprecationReason),
            // Une formule absente du disque (catalogue) n'a pas de drapeau : elle compte comme demandée.
            installedOnRequest: installed?.last?.installedOnRequest ?? true
        )
    }
}

public struct FormulaURLsDTO: Codable {
    public let stable: FormulaURLDTO?
}

public struct FormulaURLDTO: Codable {
    public let url: String?
}

public struct FormulaVersionsDTO: Codable {
    public let stable: String?
}

public struct FormulaInstalledDTO: Codable {
    public let version: String
    public let installedOnRequest: Bool?

    enum CodingKeys: String, CodingKey {
        case version
        case installedOnRequest = "installed_on_request"
    }
}

public struct FormulaBottleDTO: Codable {
    public let stable: FormulaBottleStableDTO?
}

public struct FormulaBottleStableDTO: Codable {
    public let files: [String: AnyJSON]?
}

// MARK: - Cask DTOs
public struct CaskDTO: Codable {
    public let token: String
    public let name: [String]?
    public let desc: String?
    public let homepage: String?
    public let version: String?
    public let caveats: String?
    public let installed: String?
    public let outdated: Bool?
    public let url: String?
    public let tap: String?
    public let deprecated: Bool?
    public let disabled: Bool?
    public let deprecationReason: String?

    enum CodingKeys: String, CodingKey {
        case token, name, desc, homepage, version, caveats, installed, outdated, url, tap, deprecated, disabled
        case deprecationReason = "deprecation_reason"
    }

    public func toBrewPackage(outdatedList: Set<String>) -> BrewPackage {
        let displayName = name?.first ?? token
        let latestVer = version ?? "inconnaissable"
        // `installed` is brew's own record of what's actually on disk for this cask — the previous
        // implementation never decoded it, so installedVersion always fell back to the catalog's
        // `version` and casks could never be detected as outdated.
        let currentVer = installed ?? latestVer

        let isOut: Bool
        if let flag = outdated {
            isOut = flag || outdatedList.contains(token)
        } else {
            isOut = outdatedList.contains(token) && (currentVer != latestVer)
        }

        return BrewPackage(
            id: "cask-\(token)",
            name: displayName,
            fullName: token,
            type: .cask,
            description: desc ?? "Application macOS (Cask).",
            homepage: homepage ?? "https://brew.sh",
            license: "Propriétaire / Divers",
            installedVersion: currentVer,
            latestVersion: latestVer,
            isOutdated: isOut,
            dependencies: [],
            bottleArchitectures: ["macOS Universal / Native Cask"],
            caveats: caveats,
            sourceURL: url,
            tap: tap,
            lifecycle: .from(deprecated: deprecated, disabled: disabled, reason: deprecationReason)
        )
    }
}

// Helper to decode flexible Any JSON object for bottle keys without strict structure constraints
public struct AnyJSON: Codable {}

// MARK: - Outdated Response DTOs
public struct BrewOutdatedResponseV2: Codable {
    public let formulae: [OutdatedItemDTO]?
    public let casks: [OutdatedItemDTO]?
}

public struct OutdatedItemDTO: Codable {
    public let name: String
    public let currentVersion: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case currentVersion = "current_version"
    }
}
