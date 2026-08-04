import SwiftUI

public struct PackageListView: View {
    @EnvironmentObject var appState: AppState
    let currentTab: NavigationTab
    
    @State private var searchText: String = ""
    @State private var selectedPackage: BrewPackage? = nil
    
    public init(currentTab: NavigationTab) {
        self.currentTab = currentTab
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Package Table/List left pane
            VStack(alignment: .leading, spacing: 0) {
                // List Bar
                HStack {
                    Image(systemName: currentTab.icon)
                        .foregroundColor(.blue)
                    Text(currentTab.rawValue)
                        .font(DesignSystem.Typography.sectionHeader)
                    Spacer()
                    Text("\(appState.filteredPackages(for: currentTab, search: searchText).count) paquets")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                let filtered = appState.filteredPackages(for: currentTab, search: searchText)
                if filtered.isEmpty {
                    VStack(spacing: 16) {
                        if let errorMsg = appState.errorMessage {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                            Text("Problème de lecture Homebrew")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.red)
                            Text(errorMsg)
                                .font(DesignSystem.Typography.monospace)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                            Button("Réessayer") {
                                Task { await appState.refreshAll() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else if appState.isLoading {
                            ProgressView()
                            Text("Chargement des paquets Homebrew...")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 42))
                                .foregroundColor(.secondary)
                            Text("Aucun paquet trouvé dans cette vue.")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered, selection: $selectedPackage) { pkg in
                        PackageRowView(package: pkg)
                            .tag(pkg)
                            .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 320, maxWidth: 380)
            .searchable(text: $searchText, prompt: "Rechercher un paquet par nom ou description...")
            
            Divider()
            
            // Detail Right Pane
            if let selected = selectedPackage {
                PackageDetailView(package: selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(selected.id)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.4))
                    Text("Sélectionnez un paquet dans la liste pour consulter son détail complet, ses bouteilles compatibles et son audit de sécurité CVE.")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.underPageBackgroundColor).opacity(0.4))
            }
        }
        .onAppear {
            if selectedPackage == nil {
                let first = appState.filteredPackages(for: currentTab, search: "").first
                DispatchQueue.main.async {
                    self.selectedPackage = first
                }
            }
        }
        .onChange(of: currentTab) {
            let first = appState.filteredPackages(for: currentTab, search: searchText).first
            DispatchQueue.main.async {
                self.selectedPackage = first
            }
        }
    }
}

struct PackageRowView: View {
    let package: BrewPackage
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(package.type == .cask ? Color.indigo.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 34, height: 34)
                Image(systemName: package.type == .cask ? "macwindow" : "terminal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(package.type == .cask ? .indigo : .blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(package.name)
                        .font(.system(size: 14, weight: .bold))
                    if package.isOutdated {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                    }
                }
                Text("v\(package.installedVersion)")
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Security status icon
            switch package.cveStatus {
            case .vulnerable(let count, let sev):
                StatusBadge(text: "\(count)", color: sev.color, icon: "exclamationmark.triangle.fill")
            case .scanning:
                ProgressView().controlSize(.small)
            case .clean:
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
            default:
                EmptyView()
            }
        }
    }
}
