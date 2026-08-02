import Foundation

public struct BrewPackage: Identifiable, Hashable {
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

public enum PackageType: String, CaseIterable, Codable, Hashable {
    case formula = "formula"
    case cask = "cask"
}

public enum PackageCVEStatus: Hashable {
    case unscanned
    case scanning
    case clean
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
        
        // Strict Version Match Guard: If the latest version is already present on disk, NEVER mark as outdated!
        let isOut: Bool
        if hasLatestInstalled || currentVer == latestVer || latestVer == "inconnaissable" {
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
    
    public func toBrewPackage(outdatedList: Set<String>, installedVersion: String? = nil) -> BrewPackage {
        let displayName = name?.first ?? token
        let currentVer = installedVersion ?? version ?? "installé"
        let latestVer = version ?? currentVer
        
        // Strict Version Match Guard for Casks
        let isOut: Bool
        if currentVer == latestVer && latestVer != "installé" && currentVer != "inconnaissable" {
            isOut = false
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
