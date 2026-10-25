import Foundation

// Identité du produit : un avis vise-t-il bien *ce* paquet ?
//
// Un nom identique ne suffit pas. « python » est aussi l'extension Python de Visual Studio
// Code (éditeur Microsoft, numérotée 2020.5.0), « gettext.js » n'est pas GNU gettext, et
// « deno » a une faille qui ne concerne que Windows. Chaque rapprochement est donc confronté
// à plusieurs indices indépendants — nom, éditeur, plateforme visée, schéma de version,
// références de l'avis — dont le total donne un score et, surtout, des raisons lisibles :
// ce qui est retenu dit pourquoi, ce qui est écarté aussi.

public enum IdentityConfidence: Int, Codable, Comparable, Sendable {
    case weak = 0
    case probable = 1
    case strong = 2

    public static func < (lhs: IdentityConfidence, rhs: IdentityConfidence) -> Bool { lhs.rawValue < rhs.rawValue }

    public var localizedLabel: String {
        switch self {
        case .weak: return "faible"
        case .probable: return "probable"
        case .strong: return "forte"
        }
    }
}

/// Le produit tel que la base le publie, et pourquoi on l'a pris pour le paquet installé.
public struct ProductIdentity: Codable, Hashable, Sendable {
    public let advisoryProduct: String
    public let vendor: String?
    public let score: Int
    public let confidence: IdentityConfidence
    public let reasons: [String]

    public init(advisoryProduct: String, vendor: String?, score: Int, reasons: [String]) {
        self.advisoryProduct = advisoryProduct
        self.vendor = vendor
        self.score = score
        self.reasons = reasons
        self.confidence = score >= 6 ? .strong : (score >= 3 ? .probable : .weak)
    }

    /// « python (éditeur python) », pour l'affichage.
    public var summary: String {
        guard let vendor = vendor, !vendor.isEmpty, vendor != "n/a", vendor != "*" else { return advisoryProduct }
        return "\(advisoryProduct) (éditeur \(vendor))"
    }
}

/// Un avis dont le nom correspondait au paquet mais que les autres indices ont écarté.
public struct RejectedAdvisory: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(source)-\(advisoryID)-\(product)" }
    public let advisoryID: String
    public let source: String
    public let product: String
    public let reason: String

    public init(advisoryID: String, source: String, product: String, reason: String) {
        self.advisoryID = advisoryID
        self.source = source
        self.product = product
        self.reason = reason
    }
}

public enum AdvisoryOutcome {
    case kept(CVEVulnerability)
    case rejected(RejectedAdvisory)
    /// L'avis ne concerne pas ce logiciel, même de loin : rien à signaler.
    case irrelevant
}

/// Ce qu'un avis déclare sur l'un des produits qu'il touche.
public struct AdvisoryProductClaim {
    public let name: String
    public let vendor: String?
    /// Logiciel hôte visé (champ `target_sw` d'un CPE) : « visual_studio_code », « windows »...
    public let targetSoftware: String?
    public let range: AffectedVersionRange?

    public init(name: String, vendor: String?, targetSoftware: String?, range: AffectedVersionRange?) {
        self.name = name
        self.vendor = vendor
        self.targetSoftware = targetSoftware
        self.range = range
    }
}

public enum ProductIdentityEvaluator {
    public enum Verdict {
        case accepted(ProductIdentity)
        case rejected(String)
        /// Le nom du produit n'a rien à voir avec le paquet.
        case notThisProduct
    }

    /// Seuil sous lequel un avis sans aucune version à recouper n'est pas retenu : sans plage,
    /// l'identité est la seule chose qui le sépare d'un homonyme.
    private static let minimumScoreWithoutVersion = 3

    public static func evaluate(_ claim: AdvisoryProductClaim,
                                description: String,
                                references: [String],
                                package: BrewPackage) -> Verdict {
        guard let kind = ProductNameMatcher.matchKind(product: claim.name, package: package) else {
            return .notThisProduct
        }
        if let reason = hardRejection(claim: claim, description: description, package: package) {
            return .rejected(reason)
        }

        var score = kind.weight
        var reasons = [kind.localizedReason.prefix(1).uppercased() + kind.localizedReason.dropFirst()]

        // Un produit désigné par une adresse de dépôt porte son éditeur dans l'adresse
        // (github.com/nodejs/node -> « nodejs »), faute de mieux dans le champ éditeur.
        var vendor = claim.vendor
        if kind == .repository, ProductNameMatcher.normalize(vendor ?? "").isEmpty || ["na", "unspecified"].contains(ProductNameMatcher.normalize(vendor ?? "")) {
            let parts = claim.name.split(separator: "/").map(String.init)
            if parts.count >= 2 { vendor = parts[parts.count - 2] }
        }

        let plausibleVendor = vendorPlausibility(vendor, package: package)
        switch plausibleVendor {
        case .some(true):
            score += 2
            reasons.append("éditeur « \(vendor ?? "") » cohérent avec le projet")
        case .some(false):
            score -= 1
            reasons.append("éditeur « \(vendor ?? "") » sans lien visible avec le projet")
        case .none:
            break
        }

        // Un produit désigné par l'adresse même du dépôt amont du paquet ne laisse aucun doute.
        var corroborated = false
        if kind == .repository, let anchor = ReferenceCorroboration.match(references: [claim.name], package: package) {
            score += 3
            corroborated = true
            reasons.append("le produit est le dépôt amont du paquet (\(anchor))")
        } else if let anchor = ReferenceCorroboration.match(references: references, package: package) {
            score += 3
            corroborated = true
            reasons.append("l'avis cite le site officiel du projet (\(anchor))")
        }

        if plausibleVendor == false && !corroborated {
            // Un nom seulement voisin que tout le reste contredit : `ca-certificates` recevait les
            // failles de Step CA, que smallstep publie sous le produit « certificates ».
            if kind != .exact {
                return .rejected("Nom seulement voisin (« \(claim.name) ») et éditeur « \(vendor ?? "") » sans lien avec le projet : un autre logiciel")
            }
            // Même nom, mais l'éditeur est une distribution qui décrit sa propre version du paquet
            // (« ca-certificates for Amazon Linux 2 ») : ce n'est pas le logiciel amont qu'installe Homebrew.
            if let distribution = AdvisoryText.linuxDistribution(in: description, vendor: vendor) {
                return .rejected("Paquet reconditionné par \(distribution), pas le projet amont")
            }
        }

        let hasVersionInformation = claim.range?.carriesVersionInformation ?? false
        if hasVersionInformation {
            score += 1
            reasons.append("plage de versions dans le même schéma que la version installée")
        } else if score < minimumScoreWithoutVersion {
            return .rejected("Aucune version à recouper et correspondance trop faible (score \(score))")
        }

        if score <= 0 { return .rejected("Correspondance insuffisante (score \(score))") }

        return .accepted(ProductIdentity(advisoryProduct: claim.name, vendor: claim.vendor, score: score, reasons: reasons))
    }

    /// Avis qui ne cite aucun produit : seul le texte rattache le paquet. Jamais mieux que faible.
    public static func evaluateText(description: String, references: [String], package: BrewPackage) -> Verdict {
        guard ProductNameMatcher.textMentions(package: package, in: description) else { return .notThisProduct }
        if let reason = hardRejection(claim: nil, description: description, package: package) {
            return .rejected(reason)
        }
        var score = 1
        var reasons = ["Nom du paquet cité dans la description, sans produit déclaré"]
        if let anchor = ReferenceCorroboration.match(references: references, package: package) {
            score += 3
            reasons.append("l'avis cite le site officiel du projet (\(anchor))")
        }
        return .accepted(ProductIdentity(advisoryProduct: package.name, vendor: nil, score: score, reasons: reasons))
    }

    // MARK: Indices éliminatoires

    private static func hardRejection(claim: AdvisoryProductClaim?, description: String, package: BrewPackage) -> String? {
        if let target = claim?.targetSoftware {
            switch TargetSoftware.classify(target) {
            case .compatible: break
            case .otherPlatform(let name): return "Faille propre à \(name), pas à macOS"
            case .hostApplication(let host): return "Greffon ou extension pour « \(host) », pas le logiciel lui-même"
            }
        }

        if let range = claim?.range, let installed = PackageVersion(package.upstreamInstalledVersion),
           range.isForeignScheme(to: installed) {
            let sample = range.boundSample ?? "?"
            return "Numérotation par année (« \(sample) ») étrangère à la version \(package.upstreamInstalledVersion) : un autre logiciel du même nom"
        }

        if let platform = AdvisoryText.onlyOtherPlatform(description) {
            return "Faille propre à \(platform), pas à macOS"
        }
        if let host = AdvisoryText.extensionHost(in: description, package: package) {
            return "Extension ou greffon pour « \(host) », pas le logiciel lui-même"
        }
        return nil
    }

    // MARK: Éditeur

    /// `true` si l'éditeur porte le nom du paquet ou celui de son projet, `false` s'il n'a rien
    /// à voir, `nil` si l'avis ne le précise pas.
    static func vendorPlausibility(_ vendor: String?, package: BrewPackage) -> Bool? {
        guard let vendor = vendor else { return nil }
        let normalizedVendor = ProductNameMatcher.normalize(vendor)
        if normalizedVendor.isEmpty || ["na", "unspecified", "unknown"].contains(normalizedVendor) { return nil }
        if ProductNameMatcher.candidates(for: package).contains(normalizedVendor) { return true }

        let labels = ReferenceCorroboration.identityLabels(for: package)
        let plausible = labels.contains { label in
            label == normalizedVendor
                || (label.count >= 4 && normalizedVendor.contains(label))
                || (normalizedVendor.count >= 4 && label.contains(normalizedVendor))
        }
        return plausible
    }
}

// MARK: - Logiciel hôte visé par un CPE

enum TargetSoftware {
    enum Kind {
        case compatible
        case otherPlatform(String)
        case hostApplication(String)
    }

    /// macOS, ou aucune précision : l'avis peut viser ce paquet.
    private static let compatible: Set<String> = [
        "", "*", "-", "x", "macos", "mac_os", "mac_os_x", "macosx", "osx", "os_x", "darwin",
        // Un langage n'est pas un hôte : yt-dlp, cffi ou certifi sont des bibliothèques Python.
        "python", "node.js", "nodejs", "ruby", "php", "perl", "java", "go", "golang", "rust",
        "jre", "jdk", ".net", "dotnet", "lua", "swift"
    ]

    private static let otherPlatforms: [String: String] = [
        "windows": "Windows", "android": "Android", "iphone_os": "iOS", "ios": "iOS",
        "ipados": "iPadOS", "tvos": "tvOS", "watchos": "watchOS", "linux": "Linux",
        "linux_kernel": "Linux", "freebsd": "FreeBSD", "openbsd": "OpenBSD", "netbsd": "NetBSD",
        "solaris": "Solaris", "aix": "AIX", "hp-ux": "HP-UX", "chrome_os": "ChromeOS"
    ]

    static func classify(_ raw: String) -> Kind {
        let value = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if compatible.contains(value) { return .compatible }
        if let platform = otherPlatforms[value] { return .otherPlatform(platform) }
        return .hostApplication(value.replacingOccurrences(of: "_", with: " "))
    }
}

// MARK: - Indices dans le texte de l'avis

enum AdvisoryText {
    private static let macOrNeutral = [
        "macos", "mac os", "os x", "darwin", "unix", "linux", "posix", "bsd",
        "cross-platform", "all platforms", "any platform", "all operating systems"
    ]

    private static let otherPlatformPhrases: [(name: String, phrases: [String])] = [
        ("Windows", ["on windows", "windows-only", "windows only", "only on windows", "microsoft windows",
                     "windows version", "windows platform", "windows installer", "windows service",
                     "windows operating system"]),
        ("Android", ["on android", "android app", "android version", "android devices"]),
        ("iOS", ["on ios", "iphone os", "ios app", "ios version"])
    ]

    /// Vrai quand l'avis ne vise qu'une autre plateforme que macOS (« ... on Windows contain a
    /// command injection ») : aucun mot ne laisse croire qu'il touche aussi les systèmes Unix.
    static func onlyOtherPlatform(_ text: String) -> String? {
        let lowered = text.lowercased()
        guard !macOrNeutral.contains(where: { lowered.contains($0) }) else { return nil }
        return otherPlatformPhrases.first { entry in entry.phrases.contains { lowered.contains($0) } }?.name
    }

    private static let distributions: [(name: String, phrases: [String], vendors: [String])] = [
        ("Amazon Linux", ["amazon linux"], ["amazon", "aws"]),
        ("Red Hat", ["red hat enterprise linux", "rhel"], ["redhat", "redhatinc"]),
        ("SUSE", ["suse linux", "opensuse", "sles"], ["suse", "opensuse"]),
        ("Debian", ["debian"], ["debian"]),
        ("Ubuntu", ["ubuntu"], ["canonical", "ubuntu"]),
        ("Fedora", ["fedora"], ["fedora", "fedoraproject"]),
        ("Oracle Linux", ["oracle linux"], ["oracle"]),
        ("Alpine Linux", ["alpine linux"], ["alpine", "alpinelinux"])
    ]

    /// La distribution Linux dont l'avis décrit le paquet, quand c'est aussi elle qui le publie :
    /// « The ca-certificates package ... for Amazon Linux 2 », éditeur Amazon. Les deux indices
    /// sont exigés : un avis amont cite parfois une distribution touchée sans en être le paquet.
    static func linuxDistribution(in text: String, vendor: String?) -> String? {
        let lowered = text.lowercased()
        let normalizedVendor = ProductNameMatcher.normalize(vendor ?? "")
        return distributions.first { entry in
            entry.vendors.contains(normalizedVendor) && entry.phrases.contains { lowered.contains($0) }
        }?.name
    }

    private static let hosts = [
        "visual studio code", "vs code", "vscode", "wordpress", "jenkins", "chrome", "firefox",
        "jira", "confluence", "magento", "drupal", "joomla", "eclipse", "intellij", "sublime text"
    ]
    private static let extensionWords = ["extension", "plugin", "plug-in", "add-on", "addon", "module", "theme"]

    /// L'avis traite d'une extension d'une application hôte (« Visual Studio Code - Python
    /// extension »). Ne vaut que si le paquet n'est pas lui-même lié à cet hôte : le paquet
    /// `wp-cli`, dont la description parle de WordPress, n'est pas concerné.
    static func extensionHost(in text: String, package: BrewPackage) -> String? {
        let lowered = text.lowercased()
        guard extensionWords.contains(where: { lowered.contains($0) }) else { return nil }
        let own = "\(package.name) \(package.fullName) \(package.description)".lowercased()
        return hosts.first { lowered.contains($0) && !own.contains($0) }
    }
}

// MARK: - Références de l'avis

enum ReferenceCorroboration {
    /// Hébergeurs partagés par des milliers de projets : seule l'adresse du dépôt compte.
    private static let sharedHosts: Set<String> = [
        "github.com", "gitlab.com", "codeberg.org", "bitbucket.org", "sourceforge.net", "sf.net",
        "gnu.org", "savannah.gnu.org", "savannah.nongnu.org", "pypi.org", "npmjs.com",
        "rubygems.org", "crates.io", "launchpad.net", "kernel.org", "gitlab.freedesktop.org"
    ]

    /// Adresses qui désignent le projet : son site, ou son dépôt (hôte/propriétaire/dépôt).
    static func anchors(for package: BrewPackage) -> [String] {
        var result: Set<String> = []
        for raw in [package.homepage, package.sourceURL ?? ""] {
            guard let url = URL(string: raw), var host = url.host?.lowercased() else { continue }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            if host == "brew.sh" { continue }
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }.map { $0.lowercased() }
            if sharedHosts.contains(host) {
                switch host {
                case "gnu.org":
                    if parts.count >= 2, parts[0] == "software" { result.insert("gnu.org/software/\(parts[1])") }
                case "sourceforge.net", "sf.net":
                    if parts.count >= 2, parts[0] == "projects" { result.insert("sourceforge.net/projects/\(parts[1])") }
                default:
                    if parts.count >= 2 { result.insert("\(host)/\(parts[0])/\(parts[1])") }
                }
            } else {
                result.insert(host)
            }
        }
        return result.sorted()
    }

    /// Mots qui identifient le projet : domaine de son site, propriétaire et nom de son dépôt.
    static func identityLabels(for package: BrewPackage) -> Set<String> {
        var labels: Set<String> = []
        for anchor in anchors(for: package) {
            let parts = anchor.split(separator: "/").map(String.init)
            if parts.count == 1 {
                for label in parts[0].split(separator: ".").dropLast() { labels.insert(ProductNameMatcher.normalize(String(label))) }
            } else {
                for part in parts.dropFirst() { labels.insert(ProductNameMatcher.normalize(part)) }
            }
        }
        labels.remove("")
        labels.remove("software")
        labels.remove("projects")
        return labels.filter { $0.count >= 3 }
    }

    /// L'adresse du projet que l'une des références de l'avis désigne, s'il y en a une.
    static func match(references: [String], package: BrewPackage) -> String? {
        let anchors = anchors(for: package)
        guard !anchors.isEmpty else { return nil }
        for reference in references {
            guard let url = URL(string: reference.trimmingCharacters(in: .whitespacesAndNewlines)),
                  var host = url.host?.lowercased() else { continue }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            let path = url.pathComponents.filter { $0 != "/" }.joined(separator: "/").lowercased()
            let full = path.isEmpty ? host : "\(host)/\(path)"
            for anchor in anchors {
                if anchor.contains("/") {
                    if full == anchor || full.hasPrefix(anchor + "/") { return anchor }
                } else if host == anchor || host.hasSuffix("." + anchor) {
                    return anchor
                }
            }
        }
        return nil
    }
}
