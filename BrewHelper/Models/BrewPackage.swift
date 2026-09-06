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
        caveats: String? = nil
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

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
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
            caveats: caveats
        )
    }
}

public struct FormulaVersionsDTO: Codable {
    public let stable: String?
}

public struct FormulaInstalledDTO: Codable {
    public let version: String
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
            caveats: caveats
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
