import SwiftUI

public struct PackageDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) var openURL
    
    let package: BrewPackage
    
    public init(package: BrewPackage) {
        self.package = package
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Banner
                HStack(alignment: .top, spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(package.type == .cask ? DesignSystem.Colors.purpleGradient : DesignSystem.Colors.primaryGradient)
                            .frame(width: 64, height: 64)
                            .shadow(color: (package.type == .cask ? Color.purple : Color.blue).opacity(0.3), radius: 8, y: 4)
                        Image(systemName: package.type == .cask ? "macwindow.on.rectangle" : "shippingbox.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(package.name)
                                .font(DesignSystem.Typography.title)
                            StatusBadge(text: package.type.rawValue, color: package.type == .cask ? .indigo : .blue)
                            if package.isOutdated {
                                StatusBadge(text: "Mise à jour v\(package.latestVersion) disponible", color: .orange, icon: "sparkles")
                            } else {
                                StatusBadge(text: "À jour", color: .green, icon: "checkmark.circle.fill")
                            }
                        }
                        
                        Text(package.description)
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                        
                        HStack(spacing: 16) {
                            Text("Installé : **v\(package.installedVersion)**")
                                .font(DesignSystem.Typography.body)
                            Text("Licence : **\(package.license)**")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    Spacer()
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    if !appState.isPackageInstalled(name: package.name) {
                        ActionButton(title: "Installer sur mon Mac (brew install)", icon: "arrow.down.circle.fill", gradient: DesignSystem.Colors.greenGradient) {
                            appState.executePackageAction(package: package, action: .install)
                        }
                    } else {
                        if package.isOutdated {
                            ActionButton(title: "Mettre à jour v\(package.latestVersion)", icon: "arrow.up.circle.fill", gradient: DesignSystem.Colors.greenGradient) {
                                appState.executePackageAction(package: package, action: .upgrade)
                            }
                        }
                        
                        ActionButton(title: "Réinstaller", icon: "arrow.triangle.2.circlepath", gradient: DesignSystem.Colors.primaryGradient) {
                            appState.executePackageAction(package: package, action: .reinstall)
                        }
                    }
                    
                    Button(action: {
                        if let url = URL(string: package.homepage) {
                            openURL(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text("Site Web")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    if appState.isPackageInstalled(name: package.name) {
                        Button(action: {
                            appState.executePackageAction(package: package, action: .uninstall)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                Text("Désinstaller")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider()
                
                // Bottles & Apple Silicon Architecture Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "cpu.fill")
                            .foregroundColor(.blue)
                        Text(package.type == .formula ? "Bouteilles et Architectures Compatibles (Bottles)" : "Type d'Application macOS")
                            .font(DesignSystem.Typography.sectionHeader)
                    }
                    
                    GlassCard {
                        if package.bottleArchitectures.isEmpty {
                            Text("Aucune information spécifique de bouteille précompilée disponible pour ce paquet (assemblé depuis les sources ou Cask).")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(package.bottleArchitectures, id: \.self) { arch in
                                    HStack(spacing: 6) {
                                        Image(systemName: arch.contains("arm64") ? "bolt.shield.fill" : "desktopcomputer")
                                            .foregroundColor(arch.contains("arm64") ? .green : .blue)
                                            .font(.system(size: 12))
                                        Text(arch)
                                            .font(DesignSystem.Typography.monospace)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(arch.contains("arm64") ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1))
                                }
                            }
                        }
                    }
                }
                
                // Dependencies Tree (Using native LazyVGrid instead of custom FlowLayout to avoid layout recursion)
                if !package.dependencies.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                                .foregroundColor(.purple)
                            Text("Dépendances Installées (\(package.dependencies.count))")
                                .font(DesignSystem.Typography.sectionHeader)
                        }
                        
                        GlassCard {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(package.dependencies, id: \.self) { dep in
                                    StatusBadge(text: dep, color: .purple, icon: "cube.fill")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                
                // Caveats
                if let caveats = package.caveats, !caveats.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text("Avertissements & Caveats Homebrew")
                                .font(DesignSystem.Typography.sectionHeader)
                        }
                        
                        Text(caveats)
                            .font(DesignSystem.Typography.monospace)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
                    }
                }
                
                PackageSecuritySection(package: package)
                
                Spacer()
            }
            .padding(28)
        }
    }
}


// MARK: - Section sécurité de la fiche paquet
//
// Rien n'est interrogé à l'ouverture de la fiche : on montre le verdict du dernier audit,
// et l'analyse d'un paquet isolé reste une action explicite.
struct PackageSecuritySection: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var security: CVESecurityService = .shared

    let package: BrewPackage
    @State private var isChecking: Bool = false

    private var vulnerabilities: [CVEVulnerability] {
        security.cachedVulnerabilities(for: package) ?? []
    }

    private var hasVerdict: Bool {
        security.cachedVulnerabilities(for: package) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let failure = security.scanFailures[package.name] {
                verdictCard(icon: "wifi.exclamationmark", color: .red,
                            title: "Vérification impossible",
                            message: "\(failure). Ce paquet n'a pas été comparé aux avis de sécurité : son état est inconnu, pas sain.")
            } else if !hasVerdict {
                verdictCard(icon: "circle.dashed", color: .secondary,
                            title: "Paquet non audité",
                            message: "Aucun verdict en mémoire pour la v\(package.installedVersion). Lancez l'analyse pour comparer cette version aux avis publiés.")
            } else if security.untrackedPackages.contains(package.name) {
                verdictCard(icon: "questionmark.circle.fill", color: .secondary,
                            title: "Produit absent de la base \(security.source.shortLabel)",
                            message: "La base interrogée ne suit pas ce logiciel : l'absence de résultat n'y prouve rien. Essayez l'autre base depuis l'onglet Audit de Sécurité.")
            } else if vulnerabilities.isEmpty {
                verdictCard(icon: "checkmark.shield.fill", color: .green,
                            title: "Aucune faille non corrigée pour la version installée",
                            message: "L'audit \(security.source.fullDescription) n'a relevé aucune CVE encore ouverte pour \(package.name) v\(package.installedVersion). Les failles déjà corrigées par cette version ne sont pas listées.")
            } else {
                vulnerabilityList
            }

            if !vulnerabilities.isEmpty {
                RemediationPlanCard(package: package, vulnerabilities: vulnerabilities)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(vulnerabilities.isEmpty ? .green : .red)
            Text("Audit de Sécurité & Failles CVE (\(security.source.shortLabel))")
                .font(DesignSystem.Typography.sectionHeader)
            Spacer()
            if isChecking {
                ProgressView().controlSize(.small)
                Text("Interrogation de \(security.source.shortLabel)...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Button(hasVerdict ? "Revérifier ce paquet" : "Analyser ce paquet") {
                    Task {
                        isChecking = true
                        _ = await security.checkSinglePackageNow(package: package, force: true)
                        isChecking = false
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private func verdictCard(icon: String, color: Color, title: String, message: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color == .secondary ? .primary : color)
                    Text(message)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var vulnerabilityList: some View {
        VStack(spacing: 12) {
            Text("\(vulnerabilities.count) faille(s) encore ouverte(s) sur la v\(package.installedVersion), classées par urgence réelle : l'exploitation avérée prime sur le score.")
                .font(DesignSystem.Typography.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(vulnerabilities) { vulnerability in
                VulnerabilityCard(vulnerability: vulnerability)
            }
        }
    }
}

/// Une faille, avec ce qui permet de décider s'il faut agir aujourd'hui.
struct VulnerabilityCard: View {
    @Environment(\.openURL) var openURL
    let vulnerability: CVEVulnerability

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    StatusBadge(text: vulnerability.id, color: vulnerability.severity.color, icon: "exclamationmark.triangle.fill")
                    StatusBadge(text: "Sévérité : \(vulnerability.severity.localizedLabel)", color: vulnerability.severity.color)
                    if let score = vulnerability.cvssScore {
                        StatusBadge(text: "CVSS : \(String(format: "%.1f", score))", color: vulnerability.severity.color)
                    }
                    Spacer()
                    Text("Publié le : \(vulnerability.publishedDate)")
                        .font(DesignSystem.Typography.monospace)
                        .foregroundColor(.secondary)
                }

                // Renseignement d'exploitation : ce qui distingue une faille théorique
                // d'une faille dont on se sert aujourd'hui.
                if vulnerability.isKnownExploited || vulnerability.epssScore != nil {
                    HStack(spacing: 8) {
                        if vulnerability.isKnownExploited {
                            StatusBadge(text: "Exploitation avérée (CISA KEV)", color: .red, icon: "flame.fill")
                        }
                        if vulnerability.usedByRansomware {
                            StatusBadge(text: "Employée par des rançongiciels", color: .red, icon: "lock.trianglebadge.exclamationmark.fill")
                        }
                        if let epss = vulnerability.epssLabel {
                            StatusBadge(text: "\(epss) de risque d'exploitation à 30 j",
                                        color: (vulnerability.epssScore ?? 0) > 0.1 ? .orange : .secondary,
                                        icon: "chart.line.uptrend.xyaxis")
                        }
                        Spacer()
                    }
                }

                HStack(spacing: 8) {
                    if vulnerability.isConfirmedAffected {
                        StatusBadge(text: vulnerability.verdict.localizedLabel, color: .red, icon: "xmark.shield.fill")
                    } else {
                        StatusBadge(text: vulnerability.verdict.localizedLabel, color: .gray, icon: "questionmark.circle.fill")
                    }
                    if let range = vulnerability.affectedRangeSummary {
                        StatusBadge(text: "Versions affectées : \(range)", color: .secondary)
                    }
                    Spacer()
                }

                Text(vulnerability.description)
                    .font(DesignSystem.Typography.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Consulter le rapport officiel \(vulnerability.sourceLabel) →") {
                        if let reference = vulnerability.referenceURL, let url = URL(string: reference) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12, weight: .bold))
                }
            }
        }
    }
}
