import SwiftUI

public struct PackageDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) var openURL
    
    let package: BrewPackage
    @State private var vulnerabilities: [CVEVulnerability] = []
    @State private var isCheckingSecurityNow: Bool = false
    
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
                
                // Security CVE Section (source dynamique : NVD/NIST ou EUVD/ENISA)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(vulnerabilities.isEmpty ? .green : .red)
                        Text("Audit de Sécurité & Failles CVE (\(CVESecurityService.shared.source.shortLabel))")
                            .font(DesignSystem.Typography.sectionHeader)
                        Spacer()
                        if isCheckingSecurityNow {
                            ProgressView().controlSize(.small)
                            Text("Recherche en cours...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Button("Forcer une revérification \(CVESecurityService.shared.source.shortLabel)") {
                                Task {
                                    await checkSecurity(force: true)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 12, weight: .semibold))
                        }
                    }

                    if vulnerabilities.isEmpty {
                        GlassCard {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 24))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Aucune faille non corrigée pour la version installée.")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.green)
                                    Text("L'audit de la base \(CVESecurityService.shared.source.fullDescription) n'a relevé aucune CVE ouverte pour \(package.name) v\(package.installedVersion). Les CVE déjà corrigées par cette version ne sont pas listées.")
                                        .font(DesignSystem.Typography.body)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text("\(vulnerabilities.count) faille(s) encore ouverte(s) sur la version installée (v\(package.installedVersion)), de la plus récente à la plus ancienne. Les CVE corrigées par cette version sont masquées.")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(vulnerabilities) { vuln in
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            StatusBadge(text: vuln.id, color: vuln.severity.color, icon: "exclamationmark.triangle.fill")
                                            StatusBadge(text: "Sévérité : \(vuln.severity.localizedLabel)", color: vuln.severity.color)
                                            if let score = vuln.cvssScore {
                                                StatusBadge(text: "CVSS : \(String(format: "%.1f", score))", color: vuln.severity.color)
                                            }
                                            Spacer()
                                            Text("Publié le : \(vuln.publishedDate)")
                                                .font(DesignSystem.Typography.monospace)
                                                .foregroundColor(.secondary)
                                        }

                                        // Patch cross-check: why this CVE is still considered open here.
                                        HStack(spacing: 8) {
                                            if vuln.isConfirmedAffected {
                                                StatusBadge(text: vuln.verdict.localizedLabel, color: .red, icon: "xmark.shield.fill")
                                            } else {
                                                StatusBadge(text: vuln.verdict.localizedLabel, color: .gray, icon: "questionmark.circle.fill")
                                            }
                                            if let range = vuln.affectedRangeSummary {
                                                StatusBadge(text: "Versions affectées : \(range)", color: .secondary)
                                            }
                                            Spacer()
                                        }

                                        Text(vuln.description)
                                            .font(DesignSystem.Typography.body)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        HStack {
                                            Spacer()
                                            Button("Consulter le rapport officiel \(vuln.sourceLabel) →") {
                                                if let ref = vuln.referenceURL, let url = URL(string: ref) {
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
                    }
                }
                
                Spacer()
            }
            .padding(28)
        }
        .onAppear {
            Task {
                await loadCachedOrFetchSecurity()
            }
        }
        .onChange(of: package.id) {
            Task {
                await loadCachedOrFetchSecurity()
            }
        }
    }
    
    private func loadCachedOrFetchSecurity() async {
        if let cached = CVESecurityService.shared.cachedVulnerabilities(for: package) {
            DispatchQueue.main.async {
                self.vulnerabilities = cached
            }
        } else {
            await checkSecurity()
        }
    }
    
    private func checkSecurity(force: Bool = false) async {
        DispatchQueue.main.async {
            isCheckingSecurityNow = true
        }
        let results = await CVESecurityService.shared.checkSinglePackageNow(package: package, force: force)
        DispatchQueue.main.async {
            self.vulnerabilities = results
            isCheckingSecurityNow = false
        }
    }
}
