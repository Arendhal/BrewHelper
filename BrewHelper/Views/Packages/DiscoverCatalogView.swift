import SwiftUI

public struct DiscoverCatalogView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) var openURL
    
    @State private var searchText: String = ""
    @State private var searchResults: [BrewPackage] = []
    @State private var isSearching: Bool = false
    @State private var selectedPackage: BrewPackage? = nil
    @State private var errorMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left list / search pane
            VStack(alignment: .leading, spacing: 0) {
                // Header bar
                HStack {
                    Image(systemName: "bag.fill")
                        .foregroundColor(.blue)
                    Text("Découvrir & Installer")
                        .font(DesignSystem.Typography.sectionHeader)
                    Spacer()
                }
                .padding(14)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Indispensables Développeurs & Apps macOS")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                            
                            VStack(spacing: 12) {
                                ForEach(appState.featuredCatalog) { item in
                                    FeaturedCatalogRow(item: item)
                                        .onTapGesture {
                                            self.selectedPackage = item.toBrewPackage()
                                        }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 24)
                        }
                    }
                } else {
                    if isSearching {
                        VStack(spacing: 14) {
                            ProgressView()
                            Text("Recherche dans la base mondiale Homebrew...")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if searchResults.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Aucun paquet correspondant pour \"\(searchText)\".")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(searchResults, selection: $selectedPackage) { pkg in
                            PackageRowView(package: pkg)
                                .tag(pkg)
                                .padding(.vertical, 4)
                        }
                        .listStyle(.inset)
                    }
                }
            }
            .frame(minWidth: 340, maxWidth: 400)
            .searchable(text: $searchText, prompt: "Taper un mot-clé (ex: redis, vlc, git, spotify)...")
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: searchText) {
                if searchText.isEmpty {
                    searchResults = []
                    selectedPackage = nil
                } else if searchText.count >= 3 {
                    performSearch()
                }
            }
            
            Divider()
            
            // Detail Right Pane
            if let selected = selectedPackage {
                PackageDetailView(package: selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(selected.id)
            } else {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "sparkles")
                            .font(.system(size: 38))
                            .foregroundColor(.blue)
                    }
                    Text("Explorez le catalogue mondial Homebrew")
                        .font(.system(size: 18, weight: .bold))
                    Text("Tapez n'importe quel mot-clé dans la barre de recherche ou cliquez sur l'un des paquets recommandés pour consulter ses détails et l'installer d'un seul clic.")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.underPageBackgroundColor).opacity(0.4))
            }
        }
        .onAppear {
            if selectedPackage == nil, let first = appState.featuredCatalog.first {
                self.selectedPackage = first.toBrewPackage()
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        
        let query = searchText
        Task {
            do {
                let results = try await BrewCatalogService.shared.searchGlobalPackages(query: query)
                if self.searchText == query {
                    self.searchResults = results
                    self.isSearching = false
                    if self.selectedPackage == nil {
                        self.selectedPackage = results.first
                    }
                }
            } catch {
                if self.searchText == query {
                    self.errorMessage = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }
}

struct FeaturedCatalogRow: View {
    let item: CatalogItem
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.isCask ? Color.indigo.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: item.isCask ? "macwindow" : "terminal.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(item.isCask ? .indigo : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text(item.category)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(6)
                }
                Text(item.desc)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if appState.isPackageInstalled(name: item.name) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        .contentShape(Rectangle())
    }
}
