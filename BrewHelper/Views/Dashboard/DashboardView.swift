import SwiftUI

public struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var securityService: CVESecurityService = .shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header Banner
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Vue d'ensemble Homebrew")
                            .font(DesignSystem.Typography.title)
                            .foregroundColor(.primary)
                        Text("Gestion native Apple Silicon & maintenance en un clic.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    StatusBadge(text: "Apple Silicon & Intel compatible", color: .green, icon: "cpu")
                }
                .padding(.top, 8)
                
                // One-Click "Upgrade All" Banner — the most visible CTA on the home screen when updates are pending
                if appState.outdatedCount > 0 {
                    GlassCard {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(DesignSystem.Colors.amberGradient)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(appState.outdatedCount) mise(s) à jour disponible(s)")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Formulae et Casks confondus — lance brew update && brew upgrade en un clic.")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: {
                                appState.runMaintenance(command: .update)
                            }) {
                                HStack(spacing: 6) {
                                    if appState.isCommandRunning {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                    }
                                    Text("Tout mettre à jour")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(DesignSystem.Colors.amberGradient)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(appState.isCommandRunning)
                        }
                    }
                }

                // Error Alert Banner (if Homebrew binary or JSON error occurred)
                if let errorMsg = appState.errorMessage {
                    GlassCard {
                        HStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 28))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Attention : Problème de communication avec Homebrew")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.red)
                                Text(errorMsg)
                                    .font(DesignSystem.Typography.monospace)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Réessayer") {
                                Task { await appState.refreshAll() }
                            }
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // 4 Vibrant Statistics Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    StatCard(title: "Formulae CLI", count: appState.formulaeCount, icon: "terminal.fill", gradient: DesignSystem.Colors.primaryGradient) {
                        appState.selectedTab = .formulae
                    }
                    
                    StatCard(title: "Casks (Apps)", count: appState.casksCount, icon: "macwindow.badge.plus", gradient: DesignSystem.Colors.purpleGradient) {
                        appState.selectedTab = .casks
                    }
                    
                    StatCard(title: "Mises à jour", count: appState.outdatedCount, icon: "arrow.triangle.2.circlepath.circle.fill", gradient: DesignSystem.Colors.amberGradient, isAlert: appState.outdatedCount > 0) {
                        appState.selectedTab = .outdated
                    }
                    
                    StatCard(title: "Alertes CVE", count: securityService.vulnerableCount, icon: "exclamationmark.shield.fill", gradient: DesignSystem.Colors.amberGradient, isAlert: securityService.vulnerableCount > 0) {
                        appState.selectedTab = .securityAudit
                    }
                }
                
                // Live Background Security Scanner Widget
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(securityService.vulnerableCount > 0 ? .orange : .green)
                                .font(.system(size: 20))
                            Text("Audit de Sécurité en arrière-plan")
                                .font(DesignSystem.Typography.sectionHeader)
                            Spacer()
                            HStack(spacing: 8) {
                                Text("Base de données :")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Picker("", selection: Binding(
                                    get: { securityService.source },
                                    set: { newSource in
                                        securityService.switchSource(to: newSource, packages: appState.packages) { pkgId, newStatus in
                                            if let index = appState.packages.firstIndex(where: { $0.id == pkgId }) {
                                                var modified = appState.packages[index]
                                                modified.cveStatus = newStatus
                                                appState.packages[index] = modified
                                            }
                                        }
                                    }
                                )) {
                                    ForEach(VulnDatabaseSource.allCases) { src in
                                        Text(src.shortLabel).tag(src)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 140)
                                .disabled(securityService.isScanning)
                            }

                            if securityService.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Analyse : \(securityService.currentPackageScanned)")
                                    .font(DesignSystem.Typography.monospace)
                                    .foregroundColor(.secondary)
                            } else {
                                StatusBadge(text: "Audit à jour (\(securityService.scannedCount) vérifiés)", color: .green, icon: "checkmark.shield.fill")
                            }
                        }
                        
                        if securityService.totalToScan > 0 && securityService.isScanning {
                            ProgressView(value: Double(securityService.scannedCount), total: Double(securityService.totalToScan))
                                .tint(.green)
                        }
                        
                        Text(securityService.vulnerableCount == 0 ?
                             "Aucune faille de sécurité majeure (CVE) détectée parmi vos paquets Homebrew actifs (source : \(securityService.source.fullDescription))." :
                             "⚠️ \(securityService.vulnerableCount) paquet(s) affichent des alertes de vulnérabilité répertoriées dans la base \(securityService.source.fullDescription). Consultez l'onglet Audit de Sécurité.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(securityService.vulnerableCount > 0 ? .orange : .secondary)
                    }
                    .padding(4)
                }
                
                // Maintenance Hub Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Utilitaires & Entretien du Système")
                        .font(DesignSystem.Typography.sectionHeader)
                    
                    HStack(spacing: 16) {
                        MaintenanceCard(
                            title: "Diagnostic Système",
                            subtitle: "brew doctor",
                            desc: "Vérifie la santé du système, les conflits de liens et les autorisations.",
                            icon: "stethoscope",
                            color: .blue
                        ) {
                            appState.runMaintenance(command: .doctor)
                        }
                        
                        MaintenanceCard(
                            title: "Nettoyage du Cache",
                            subtitle: "brew cleanup",
                            desc: "Supprime les vieilles bouteilles, logs et téléchargements obsolètes.",
                            icon: "trash.fill",
                            color: .red
                        ) {
                            appState.runMaintenance(command: .cleanup)
                        }
                        
                        MaintenanceCard(
                            title: "Tout Mettre à Jour",
                            subtitle: appState.outdatedCount > 0 ? "\(appState.outdatedCount) en attente" : "À jour",
                            desc: "Met à jour l'ensemble des formulae et casks vers les versions les plus récentes.",
                            icon: "arrow.up.circle.fill",
                            color: appState.outdatedCount > 0 ? .orange : .green
                        ) {
                            appState.runMaintenance(command: .update)
                        }
                    }
                }
                
                // Discovery Carousel / Catalog
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Découvertes & Utilitaires Tendance")
                            .font(DesignSystem.Typography.sectionHeader)
                        Spacer()
                        Text("Sélection officielle Brew")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(appState.featuredCatalog) { item in
                            CatalogCardView(item: item)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(28)
        }
    }
}

// MARK: - Subcomponents
struct StatCard: View {
    let title: String
    let count: Int
    let icon: String
    let gradient: LinearGradient
    var isAlert: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(count)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(isAlert ? .orange : .primary)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(gradient)
                            .frame(width: 44, height: 44)
                            .opacity(0.85)
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct MaintenanceCard: View {
    let title: String
    let subtitle: String
    let desc: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(color)
                    Spacer()
                    Text(subtitle)
                        .font(DesignSystem.Typography.monospace)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.15))
                        .foregroundColor(color)
                        .cornerRadius(6)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack {
                    Spacer()
                    Text("Exécuter →")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(color)
                }
            }
            .padding(18)
            .background(.regularMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovered ? color : Color.white.opacity(0.15), lineWidth: isHovered ? 2 : 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { h in isHovered = h }
    }
}

struct CatalogCardView: View {
    let item: CatalogItem
    @Environment(\.openURL) var openURL
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                Spacer()
                Text(item.category)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            Text(item.desc)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: .topLeading)
            
            HStack {
                Text("v\(item.version)")
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Site Web") {
                    if let url = URL(string: item.homepage) {
                        openURL(url)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}
