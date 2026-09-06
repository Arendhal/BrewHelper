import Foundation
import SwiftUI

// Ce qu'il faut faire d'un paquet vulnérable.
//
// Savoir qu'une faille est ouverte ne dit pas quoi en faire : selon les cas il faut
// mettre à jour, migrer vers une formule versionnée plus récente, remplacer un paquet
// abandonné, ou constater qu'aucun correctif n'existe encore. Le cas le plus délicat
// est la migration majeure, où la version vulnérable ne peut pas simplement disparaître
// parce que d'autres paquets installés en dépendent encore.

public enum RemediationKind: String, Hashable {
    /// La version corrigée est déjà dans le catalogue Homebrew : un `brew upgrade` suffit.
    case upgrade
    /// Le correctif n'existe que dans une branche majeure suivante (openssl@1.1 → openssl@3).
    case majorMigration
    /// La formule est obsolète ou abandonnée : il faut lui substituer un autre paquet.
    case replacement
    /// Aucun correctif publié : seule une mesure de contournement est possible.
    case mitigation
    /// L'application se met à jour toute seule, Homebrew n'est pas le bon levier.
    case caskSelfUpdate
    /// Rien à faire : la version installée est déjà la plus récente disponible.
    case alreadyLatest

    public var localizedTitle: String {
        switch self {
        case .upgrade: return "Mise à jour disponible"
        case .majorMigration: return "Migration de version majeure requise"
        case .replacement: return "Paquet à remplacer"
        case .mitigation: return "Aucun correctif publié"
        case .caskSelfUpdate: return "Mise à jour intégrée à l'application"
        case .alreadyLatest: return "Déjà sur la dernière version publiée"
        }
    }

    public var icon: String {
        switch self {
        case .upgrade: return "arrow.up.circle.fill"
        case .majorMigration: return "arrow.triangle.branch"
        case .replacement: return "arrow.left.arrow.right.circle.fill"
        case .mitigation: return "exclamationmark.shield.fill"
        case .caskSelfUpdate: return "app.badge.checkmark"
        case .alreadyLatest: return "checkmark.seal.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .upgrade: return .green
        case .majorMigration: return .orange
        case .replacement: return .purple
        case .mitigation: return .red
        case .caskSelfUpdate: return .blue
        case .alreadyLatest: return .secondary
        }
    }
}

/// Un paquet installé qui dépend encore de la version vulnérable, avec le verdict sur sa
/// capacité à s'en passer. C'est ce qui répond à « je ne peux pas supprimer la v1, telle
/// autre application la réclame ».
public struct RemediationBlocker: Identifiable, Hashable {
    public enum Resolution: Hashable {
        /// Le paquet dépendant réclame désormais la nouvelle version dans le catalogue :
        /// le mettre à jour suffit à libérer l'ancienne.
        case freedByUpgrading
        /// Le paquet dépendant est déjà à jour et réclame toujours l'ancienne version.
        case stillRequiresOldVersion
        /// Impossible de trancher (formule d'un tap tiers, information absente).
        case unknown
    }

    public let id: String
    public let name: String
    public let isOutdated: Bool
    public let resolution: Resolution

    public init(name: String, isOutdated: Bool, resolution: Resolution) {
        self.id = name
        self.name = name
        self.isOutdated = isOutdated
        self.resolution = resolution
    }

    public var localizedVerdict: String {
        switch resolution {
        case .freedByUpgrading:
            return "sa version à jour n'en dépend plus — le mettre à jour libère l'ancienne branche"
        case .stillRequiresOldVersion:
            return "en dépend toujours dans sa version la plus récente — l'ancienne branche doit rester"
        case .unknown:
            return "dépendance non vérifiable (tap tiers ou formule absente du catalogue)"
        }
    }
}

/// Une action concrète du plan, avec la commande Homebrew qui l'exécute quand il y en a une.
public struct RemediationStep: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let detail: String
    /// Arguments passés à `brew`, ou `nil` pour une étape purement informative.
    public let command: [String]?

    public init(id: String, title: String, detail: String, command: [String]? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.command = command
    }

    public var commandLine: String? {
        guard let command = command else { return nil }
        return "brew " + command.joined(separator: " ")
    }
}

public struct RemediationPlan: Identifiable, Hashable {
    public let id: String
    public let packageName: String
    public let kind: RemediationKind
    /// Résumé en une phrase, affiché en tête de la fiche.
    public let headline: String
    /// Le raisonnement : pourquoi ce plan-là, et ce qu'il laisse ouvert.
    public let rationale: String
    public let steps: [RemediationStep]
    /// Paquets installés qui retiennent encore la version vulnérable.
    public let blockers: [RemediationBlocker]
    /// Version qui referme les failles ouvertes, quand les avis en publient une.
    public let fixedInVersion: String?
    /// Formule de remplacement suggérée (migration majeure ou paquet abandonné).
    public let replacement: String?
    /// Nombre de failles ouvertes que ce plan referme réellement.
    public let resolvedVulnerabilityCount: Int

    public init(packageName: String,
                kind: RemediationKind,
                headline: String,
                rationale: String,
                steps: [RemediationStep],
                blockers: [RemediationBlocker] = [],
                fixedInVersion: String? = nil,
                replacement: String? = nil,
                resolvedVulnerabilityCount: Int = 0) {
        self.id = packageName
        self.packageName = packageName
        self.kind = kind
        self.headline = headline
        self.rationale = rationale
        self.steps = steps
        self.blockers = blockers
        self.fixedInVersion = fixedInVersion
        self.replacement = replacement
        self.resolvedVulnerabilityCount = resolvedVulnerabilityCount
    }

    /// Paquets dépendants qui empêchent réellement de retirer l'ancienne version.
    public var hardBlockers: [RemediationBlocker] {
        blockers.filter { $0.resolution == .stillRequiresOldVersion }
    }
}
