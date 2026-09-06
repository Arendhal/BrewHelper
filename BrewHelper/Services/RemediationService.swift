import Foundation
import Combine

// Construit, pour un paquet vulnérable, le chemin concret vers une version saine.
//
// Homebrew publie tout ce qu'il faut pour raisonner : `versioned_formulae` dit quelles
// branches majeures coexistent, `deprecated` / `disabled` signalent les formules
// abandonnées et leur remplaçante, et `brew uses --installed` donne les paquets qui
// retiennent encore l'ancienne branche. C'est ce dernier point qui rend la migration
// délicate — on ne peut pas retirer openssl@1.1 tant qu'une application installée le
// réclame — et le plan le dit explicitement au lieu de conseiller une mise à jour
// impossible.

@MainActor
public final class RemediationService: ObservableObject {
    public static let shared = RemediationService()

    /// Un plan coûte plusieurs appels à `brew`, dont un `brew uses` : on le garde tant que
    /// la version installée ne bouge pas.
    private var cachedPlans: [String: (version: String, plan: RemediationPlan)] = [:]
    private var catalogCache: [String: BrewFormulaDetail] = [:]

    public init() {}

    public func cachedPlan(for package: BrewPackage) -> RemediationPlan? {
        guard let entry = cachedPlans[package.id], entry.version == package.installedVersion else { return nil }
        return entry.plan
    }

    public func plan(for package: BrewPackage, vulnerabilities: [CVEVulnerability]) async -> RemediationPlan {
        if let cached = cachedPlan(for: package) { return cached }
        let plan = await buildPlan(for: package, vulnerabilities: vulnerabilities)
        cachedPlans[package.id] = (package.installedVersion, plan)
        return plan
    }

    public func invalidate() {
        cachedPlans.removeAll()
        catalogCache.removeAll()
    }

    // MARK: - Construction

    private func buildPlan(for package: BrewPackage, vulnerabilities: [CVEVulnerability]) async -> RemediationPlan {
        let openFlaws = vulnerabilities.filter { $0.isConfirmedAffected }
        let fixedIn = highestFixVersion(among: openFlaws)

        if package.type == .cask {
            return await caskPlan(for: package, openFlawCount: openFlaws.count, fixedIn: fixedIn)
        }
        return await formulaPlan(for: package, vulnerabilities: vulnerabilities, openFlaws: openFlaws, fixedIn: fixedIn)
    }

    /// La version qui referme *toutes* les failles ouvertes : la plus haute de celles que
    /// les avis publient. Se contenter de la plus basse laisserait des failles ouvertes.
    private func highestFixVersion(among flaws: [CVEVulnerability]) -> String? {
        var best: (raw: String, parsed: PackageVersion)? = nil
        for flaw in flaws {
            guard let raw = flaw.fixedInVersion else { continue }
            // Un avis peut écrire « > 1.4.2 » quand il ne connaît que la dernière version
            // vulnérable ; la borne n'est alors pas un numéro de version exploitable.
            let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "> "))
            guard let parsed = PackageVersion(cleaned) else { continue }
            if best == nil || parsed > best!.parsed { best = (cleaned, parsed) }
        }
        return best?.raw
    }

    // MARK: - Casks

    private func caskPlan(for package: BrewPackage, openFlawCount: Int, fixedIn: String?) async -> RemediationPlan {
        let detail = await caskDetail(named: package.fullName)

        if detail?.autoUpdates == true {
            return RemediationPlan(
                packageName: package.name,
                kind: .caskSelfUpdate,
                headline: "\(package.name) se met à jour tout seul — Homebrew n'en voit pas la version réelle.",
                rationale: "Ce cask est marqué `auto_updates` : l'application installe elle-même ses mises à jour, et la version enregistrée par Homebrew (v\(package.installedVersion)) reste figée à celle du téléchargement initial. L'audit compare donc les avis à une version qui n'est probablement plus celle sur le disque. Vérifiez la version réelle dans l'application avant de conclure.",
                steps: [
                    RemediationStep(id: "check-app", title: "Vérifier la version réelle dans l'application",
                                    detail: "Menu de l'app → À propos. C'est cette version qui compte, pas celle affichée par Homebrew."),
                    RemediationStep(id: "greedy", title: "Forcer Homebrew à réaligner le cask",
                                    detail: "`--greedy` inclut les casks à mise à jour automatique, que `brew upgrade` ignore par défaut.",
                                    command: ["upgrade", "--cask", "--greedy", package.fullName])
                ],
                fixedInVersion: fixedIn,
                resolvedVulnerabilityCount: openFlawCount
            )
        }

        if package.isOutdated {
            return RemediationPlan(
                packageName: package.name,
                kind: .upgrade,
                headline: "Mettre à jour vers la v\(package.latestVersion) referme les failles ouvertes.",
                rationale: "Le cask installé est en v\(package.installedVersion) alors que le catalogue propose la v\(package.latestVersion)\(fixedIn.map { " et que le correctif est publié en \($0)" } ?? "").",
                steps: [
                    RemediationStep(id: "upgrade", title: "Mettre à jour l'application",
                                    detail: "Homebrew télécharge et remplace l'application par sa dernière version publiée.",
                                    command: ["upgrade", "--cask", package.fullName])
                ],
                fixedInVersion: fixedIn,
                resolvedVulnerabilityCount: openFlawCount
            )
        }

        return RemediationPlan(
            packageName: package.name,
            kind: .mitigation,
            headline: "Aucune version corrigée n'est disponible dans Homebrew pour ce cask.",
            rationale: "La v\(package.installedVersion) installée est déjà la plus récente publiée\(fixedIn.map { ", alors que les avis annoncent le correctif en \($0)" } ?? ""). Le cask n'a pas encore été mis à jour côté Homebrew, ou l'éditeur n'a pas publié de correctif.",
            steps: [
                RemediationStep(id: "vendor", title: "Consulter le site de l'éditeur",
                                detail: "Une version corrigée peut exister en téléchargement direct avant d'arriver dans Homebrew."),
                RemediationStep(id: "uninstall", title: "Retirer l'application si la faille est critique",
                                detail: "Mesure de dernier recours tant qu'aucun correctif n'est disponible.",
                                command: ["uninstall", "--cask", package.fullName])
            ],
            fixedInVersion: fixedIn,
            resolvedVulnerabilityCount: 0
        )
    }

    // MARK: - Formulae

    private func formulaPlan(for package: BrewPackage,
                             vulnerabilities: [CVEVulnerability],
                             openFlaws: [CVEVulnerability],
                             fixedIn: String?) async -> RemediationPlan {
        let detail = await formulaDetail(named: package.fullName)
        let catalogVersion = detail?.versions?.stable ?? package.latestVersion
        let installed = PackageVersion(package.upstreamInstalledVersion)
        let catalog = PackageVersion(catalogVersion)
        let fix = fixedIn.flatMap(PackageVersion.init)

        let catalogIsNewer = (installed != nil && catalog != nil) ? catalog! > installed! : package.isOutdated
        let catalogCarriesFix = fix == nil ? true : (catalog.map { $0 >= fix! } ?? false)

        // 1. Le catalogue de cette formule suffit : une mise à jour classique referme tout.
        if catalogIsNewer && catalogCarriesFix {
            return RemediationPlan(
                packageName: package.name,
                kind: .upgrade,
                headline: "`brew upgrade \(package.fullName)` suffit : la v\(catalogVersion) du catalogue porte le correctif.",
                rationale: "La version installée est la v\(package.installedVersion)\(fixedIn.map { " et le correctif est publié en \($0)" } ?? ""). La formule reste la même, aucune dépendance n'est cassée par cette mise à jour.",
                steps: [
                    RemediationStep(id: "upgrade", title: "Mettre à jour \(package.fullName)",
                                    detail: "Passe de la v\(package.installedVersion) à la v\(catalogVersion).",
                                    command: ["upgrade", package.fullName]),
                    RemediationStep(id: "cleanup", title: "Purger l'ancienne version du Cellar",
                                    detail: "L'ancienne version reste sur le disque jusqu'au nettoyage — sans danger, mais elle fausse un audit de fichiers.",
                                    command: ["cleanup", package.fullName])
                ],
                fixedInVersion: fixedIn,
                resolvedVulnerabilityCount: openFlaws.count
            )
        }

        // 2. Formule abandonnée : le correctif ne viendra jamais de celle-ci.
        if detail?.disabled == true || detail?.deprecated == true {
            return await replacementPlan(for: package, detail: detail, openFlaws: openFlaws, fixedIn: fixedIn)
        }

        // 3. Le correctif n'existe que dans une branche majeure suivante.
        if let migration = await migrationTarget(for: package, detail: detail, requiredVersion: fix) {
            return await migrationPlan(for: package, target: migration, openFlaws: openFlaws, fixedIn: fixedIn)
        }

        // 4. La version installée est la plus récente publiée et la faille reste ouverte.
        let unverifiable = vulnerabilities.count - openFlaws.count
        var rationale = "La v\(package.installedVersion) installée est déjà la plus récente que Homebrew publie (v\(catalogVersion))"
        if let fixedIn = fixedIn {
            rationale += ", alors que les avis annoncent le correctif en \(fixedIn) : la formule Homebrew n'a pas encore été mise à jour en amont."
        } else {
            rationale += " et aucun avis ne publie de version corrigée — la faille est vraisemblablement encore ouverte chez l'éditeur."
        }
        if unverifiable > 0 {
            rationale += " \(unverifiable) avis supplémentaire(s) ne publient pas de plage de versions et n'ont pas pu être tranchés."
        }

        return RemediationPlan(
            packageName: package.name,
            kind: .mitigation,
            headline: "Aucun correctif atteignable via Homebrew pour l'instant.",
            rationale: rationale,
            steps: [
                RemediationStep(id: "refresh", title: "Réactualiser le catalogue Homebrew",
                                detail: "La formule peut avoir été corrigée depuis la dernière synchronisation.",
                                command: ["update"]),
                RemediationStep(id: "upstream", title: "Suivre l'avis en amont",
                                detail: "Le rapport officiel indique si un correctif est en préparation ou si un contournement est recommandé."),
                RemediationStep(id: "uninstall", title: "Désinstaller si l'exposition est inacceptable",
                                detail: "À n'envisager qu'après avoir vérifié qu'aucun autre paquet installé n'en dépend.",
                                command: ["uninstall", package.fullName])
            ],
            fixedInVersion: fixedIn,
            resolvedVulnerabilityCount: 0
        )
    }

    // MARK: - Migration de branche majeure

    /// Formule vers laquelle migrer : la branche la plus proche qui porte réellement le
    /// correctif. `versioned_formulae` liste les branches parallèles publiées par Homebrew.
    private func migrationTarget(for package: BrewPackage,
                                 detail: BrewFormulaDetail?,
                                 requiredVersion: PackageVersion?) async -> BrewFormulaDetail? {
        // Sans version corrigée connue, aucune branche ne peut être désignée comme la
        // cible : proposer « migrer vers node@20 » à une installation déjà en node 26
        // serait un contresens.
        guard let requiredVersion = requiredVersion else { return nil }
        let installed = PackageVersion(package.upstreamInstalledVersion)

        var candidates: [String] = []
        // Le nom sans suffixe pointe sur la branche courante : openssl@1.1 → openssl.
        let base = package.fullName.components(separatedBy: "@").first ?? package.fullName
        if base != package.fullName { candidates.append(base) }
        candidates.append(contentsOf: detail?.versionedFormulae ?? [])

        var best: BrewFormulaDetail? = nil
        var bestVersion: PackageVersion? = nil
        for candidate in candidates.prefix(6) {
            guard let info = await formulaDetail(named: candidate),
                  info.disabled != true,
                  let stable = info.versions?.stable.flatMap(PackageVersion.init) else { continue }
            guard stable >= requiredVersion else { continue }
            // Une branche plus ancienne que ce qui est déjà installé n'est pas une cible.
            if let installed = installed, stable <= installed { continue }
            // La branche la plus basse qui corrige : migrer plus loin que nécessaire
            // casse davantage de dépendances.
            if bestVersion == nil || stable < bestVersion! {
                best = info
                bestVersion = stable
            }
        }
        return best
    }

    private func migrationPlan(for package: BrewPackage,
                               target: BrewFormulaDetail,
                               openFlaws: [CVEVulnerability],
                               fixedIn: String?) async -> RemediationPlan {
        let blockers = await dependents(of: package)
        let hard = blockers.filter { $0.resolution == .stillRequiresOldVersion }
        let freeable = blockers.filter { $0.resolution == .freedByUpgrading }
        let targetVersion = target.versions?.stable ?? "?"

        var steps: [RemediationStep] = [
            RemediationStep(id: "install-target",
                            title: "Installer \(target.name) (v\(targetVersion))",
                            detail: "Les formules versionnées de Homebrew sont `keg-only` : la nouvelle branche s'installe à côté de l'ancienne sans la remplacer ni casser ce qui l'utilise.",
                            command: ["install", target.name])
        ]

        if !freeable.isEmpty {
            let names = freeable.map { $0.name }
            steps.append(RemediationStep(
                id: "upgrade-dependents",
                title: "Mettre à jour \(names.joined(separator: ", "))",
                detail: "La version catalogue de \(names.count > 1 ? "ces paquets" : "ce paquet") dépend désormais de \(target.name) : les mettre à jour retire la dernière raison de garder \(package.fullName).",
                command: ["upgrade"] + names))
        }

        if hard.isEmpty {
            steps.append(RemediationStep(
                id: "uninstall-old",
                title: "Retirer \(package.fullName)",
                detail: "Plus aucun paquet installé ne la réclame : c'est la seule étape qui referme réellement les failles, tant que l'ancienne branche reste sur le disque elle reste exploitable.",
                command: ["uninstall", package.fullName]))
        } else {
            let names = hard.map { $0.name }.joined(separator: ", ")
            steps.append(RemediationStep(
                id: "keep-old",
                title: "Conserver \(package.fullName) pour \(names)",
                detail: "\(names) réclame\(hard.count > 1 ? "nt" : "") encore cette branche dans sa version la plus récente. La désinstaller casserait \(hard.count > 1 ? "ces paquets" : "ce paquet") ; l'ancienne branche reste donc exposée."))
            steps.append(RemediationStep(
                id: "audit-dependents",
                title: "Vérifier si \(names) a\(hard.count > 1 ? "" : "") une alternative",
                detail: "Chercher une variante liée à \(target.name), ou remplacer le paquet dépendant, est le seul moyen de se débarrasser complètement de la branche vulnérable."))
        }

        var rationale = "Le correctif n'existe pas dans la branche \(package.fullName)"
        if let fixedIn = fixedIn { rationale += " : il est publié en \(fixedIn), disponible via \(target.name) (v\(targetVersion))." }
        else { rationale += " ; \(target.name) (v\(targetVersion)) en est la branche maintenue." }
        rationale += " Les deux branches peuvent coexister — Homebrew les installe dans des répertoires séparés — mais tant que \(package.fullName) reste installée, les failles qui la visent restent ouvertes."
        if !hard.isEmpty {
            rationale += " \(hard.count) paquet(s) installé(s) empêchent aujourd'hui de la retirer."
        } else if !blockers.isEmpty {
            rationale += " Aucun paquet ne la retient une fois les dépendants mis à jour."
        }

        return RemediationPlan(
            packageName: package.name,
            kind: .majorMigration,
            headline: "Migrer vers \(target.name) (v\(targetVersion))\(hard.isEmpty ? "" : ", en gardant \(package.fullName) pour \(hard.count) dépendant(s)")",
            rationale: rationale,
            steps: steps,
            blockers: blockers,
            fixedInVersion: fixedIn,
            replacement: target.name,
            resolvedVulnerabilityCount: hard.isEmpty ? openFlaws.count : 0
        )
    }

    /// Paquets installés qui dépendent encore de la formule vulnérable, et verdict sur
    /// leur capacité à s'en passer une fois mis à jour.
    private func dependents(of package: BrewPackage) async -> [RemediationBlocker] {
        let names = await installedDependents(of: package.fullName)
        var blockers: [RemediationBlocker] = []
        for name in names {
            guard let info = await formulaDetail(named: name) else {
                blockers.append(RemediationBlocker(name: name, isOutdated: false, resolution: .unknown))
                continue
            }
            let declared = Set((info.dependencies ?? []) + (info.buildDependencies ?? []))
            // Si le catalogue ne réclame plus l'ancienne branche, c'est l'installation
            // locale — plus ancienne — qui la retient : la mettre à jour la libère.
            let resolution: RemediationBlocker.Resolution = declared.contains(package.fullName)
                ? .stillRequiresOldVersion
                : .freedByUpgrading
            blockers.append(RemediationBlocker(name: name, isOutdated: info.outdated ?? false, resolution: resolution))
        }
        return blockers.sorted { $0.name < $1.name }
    }

    // MARK: - Remplacement d'une formule abandonnée

    /// Formules dont le successeur ne se déduit d'aucun champ Homebrew : le motif de
    /// dépréciation est du texte libre, et parfois il n'y en a pas.
    private static let knownSuccessors: [String: String] = [
        "youtube-dl": "yt-dlp",
        "python@2": "python@3",
        "node@10": "node", "node@12": "node", "node@14": "node", "node@16": "node",
        "openssl@1.0": "openssl@3", "openssl@1.1": "openssl@3",
        "ffmpeg@4": "ffmpeg", "ffmpeg@5": "ffmpeg", "ffmpeg@6": "ffmpeg",
        "gnupg@1.4": "gnupg", "gnupg@2.0": "gnupg",
        "elasticsearch": "opensearch", "kibana": "opensearch-dashboards",
        "unrar": "rar", "batik": "batik-rasterizer"
    ]

    private func replacementPlan(for package: BrewPackage,
                                 detail: BrewFormulaDetail?,
                                 openFlaws: [CVEVulnerability],
                                 fixedIn: String?) async -> RemediationPlan {
        let reason = detail?.disableReason ?? detail?.deprecationReason
        let isDisabled = detail?.disabled == true
        let successor = Self.knownSuccessors[package.fullName]
            ?? successorMentioned(in: reason)
            ?? detail?.versionedFormulae?.first
        let dependents = await installedDependents(of: package.fullName)

        var steps: [RemediationStep] = []
        if let successor = successor {
            steps.append(RemediationStep(id: "install-successor",
                                         title: "Installer \(successor)",
                                         detail: "Remplaçante maintenue de \(package.fullName).",
                                         command: ["install", successor]))
        } else {
            steps.append(RemediationStep(id: "find-successor",
                                         title: "Chercher une formule maintenue équivalente",
                                         detail: "Homebrew n'annonce pas de remplaçante pour \(package.fullName). `brew search` sur la fonction recherchée est le point de départ.",
                                         command: ["search", package.name]))
        }
        if dependents.isEmpty {
            steps.append(RemediationStep(id: "uninstall",
                                         title: "Désinstaller \(package.fullName)",
                                         detail: "Aucun paquet installé n'en dépend : la retirer referme les failles sans rien casser.",
                                         command: ["uninstall", package.fullName]))
        } else {
            steps.append(RemediationStep(id: "dependents",
                                         title: "Traiter d'abord \(dependents.joined(separator: ", "))",
                                         detail: "Ces paquets installés dépendent de \(package.fullName) : les désinstaller ou les migrer avant de retirer la formule abandonnée."))
        }

        var rationale = isDisabled
            ? "Homebrew a désactivé \(package.fullName) : la formule ne reçoit plus aucune mise à jour, correctifs de sécurité compris."
            : "Homebrew a déprécié \(package.fullName) : la formule est en fin de vie et ne recevra plus de correctifs."
        if let reason = reason, !reason.isEmpty { rationale += " Motif annoncé : « \(reason) »." }
        if fixedIn != nil { rationale += " Le correctif publié en amont n'atteindra donc jamais cette formule." }

        return RemediationPlan(
            packageName: package.name,
            kind: .replacement,
            headline: successor.map { "Remplacer \(package.fullName) par \($0)" }
                ?? "\(package.fullName) est abandonnée et doit être remplacée",
            rationale: rationale,
            steps: steps,
            blockers: dependents.map { RemediationBlocker(name: $0, isOutdated: false, resolution: .stillRequiresOldVersion) },
            fixedInVersion: fixedIn,
            replacement: successor,
            resolvedVulnerabilityCount: dependents.isEmpty ? openFlaws.count : 0
        )
    }

    /// Les motifs de dépréciation Homebrew sont du texte libre, mais ils suivent presque
    /// tous la même tournure : « use <formule> instead ».
    private func successorMentioned(in reason: String?) -> String? {
        guard let reason = reason?.lowercased() else { return nil }
        for marker in ["use ", "replaced by ", "superseded by ", "migrate to "] {
            guard let range = reason.range(of: marker) else { continue }
            let tail = reason[range.upperBound...]
            let candidate = tail.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "@" || $0 == "." || $0 == "_" }
            let trimmed = String(candidate).trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2 && trimmed != "the" { return trimmed }
        }
        return nil
    }

    // MARK: - Accès à Homebrew

    private func installedDependents(of name: String) async -> [String] {
        guard let result = try? await BrewCommandService.shared.runSynchronous(
            arguments: ["uses", "--installed", "--formula", name]) else { return [] }
        return String(data: result.data, encoding: .utf8)?
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
    }

    private func formulaDetail(named name: String) async -> BrewFormulaDetail? {
        if let cached = catalogCache[name] { return cached }
        guard let response = await brewInfo(name), let detail = response.formulae?.first else { return nil }
        catalogCache[name] = detail
        return detail
    }

    private func caskDetail(named token: String) async -> BrewCaskDetail? {
        await brewInfo(token)?.casks?.first
    }

    private func brewInfo(_ name: String) async -> BrewInfoResponse? {
        guard let result = try? await BrewCommandService.shared.runSynchronous(
            arguments: ["info", "--json=v2", name]), result.exitCode == 0 else { return nil }
        let cleaned = BrewCommandService.shared.extractCleanJSONData(from: result.data)
        return try? JSONDecoder().decode(BrewInfoResponse.self, from: cleaned)
    }
}

// MARK: - DTO du catalogue Homebrew
//
// `brew info --json=v2` expose bien plus que ce que la liste des paquets installés
// consomme : ces champs-là sont ceux qui portent la logique de remédiation.

public struct BrewInfoResponse: Codable {
    public let formulae: [BrewFormulaDetail]?
    public let casks: [BrewCaskDetail]?
}

public struct BrewFormulaDetail: Codable {
    public let name: String
    public let fullName: String?
    public let versions: BrewVersionsDetail?
    /// Branches majeures publiées en parallèle : ["openssl@4", "openssl@3.5", "openssl@3.0"].
    public let versionedFormulae: [String]?
    public let deprecated: Bool?
    public let deprecationReason: String?
    public let disabled: Bool?
    public let disableReason: String?
    public let kegOnly: Bool?
    public let aliases: [String]?
    public let dependencies: [String]?
    public let buildDependencies: [String]?
    public let outdated: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case versions
        case versionedFormulae = "versioned_formulae"
        case deprecated
        case deprecationReason = "deprecation_reason"
        case disabled
        case disableReason = "disable_reason"
        case kegOnly = "keg_only"
        case aliases
        case dependencies
        case buildDependencies = "build_dependencies"
        case outdated
    }
}

public struct BrewVersionsDetail: Codable {
    public let stable: String?
}

public struct BrewCaskDetail: Codable {
    public let token: String
    public let version: String?
    /// L'application installe elle-même ses mises à jour : la version connue de Homebrew
    /// n'est alors plus celle qui tourne.
    public let autoUpdates: Bool?
    public let deprecated: Bool?
    public let deprecationReason: String?

    enum CodingKeys: String, CodingKey {
        case token
        case version
        case autoUpdates = "auto_updates"
        case deprecated
        case deprecationReason = "deprecation_reason"
    }
}
