import SwiftUI

// Découvrir : une vitrine tirée des statistiques publiques d'installation de Homebrew (ce qui
// monte, ce qui s'installe le plus, un tirage du jour), sans ce qui est déjà sur ce Mac, et la
// recherche dans tout le catalogue. Installer met le paquet en file, sans quitter la page.

public struct DiscoverCatalogView: View {
    @EnvironmentObject var appState: AppState

    @State private var searchText: String = ""
    @State private var searchResults: [BrewPackage] = []
    @State private var isSearching: Bool = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var detailPackage: BrewPackage? = nil

    public init() {}

    private var isQueryActive: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if isQueryActive {
                    searchSection
                } else if let feed = appState.discoverFeed {
                    feedSections(feed)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Lecture des tendances Homebrew...")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(Palette.textSecondary)
                    }
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: 1240, alignment: .leading)
        }
        .background(Palette.background)
        .sheet(item: $detailPackage) { package in
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Fermer") { detailPackage = nil }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(12)
                PackageDetailView(package: package)
            }
            .frame(width: 640, height: 720)
            .background(Palette.background)
        }
        .onAppear {
            if appState.discoverFeed == nil { Task { await appState.loadCatalog() } }
            consumePendingQuery()
        }
        .onChange(of: appState.pendingDiscoverQuery) { consumePendingQuery() }
    }

    private func consumePendingQuery() {
        guard let query = appState.pendingDiscoverQuery else { return }
        appState.pendingDiscoverQuery = nil
        searchText = query
        performSearch()
    }

    // MARK: En-tête et recherche

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Découvrir").font(DesignSystem.Typography.largeTitle).foregroundColor(Palette.text)
                Text(periodLine).font(.system(size: 14)).foregroundColor(Palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(Palette.textSecondary)
                TextField("Chercher dans tout Homebrew", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { performSearch() }
                if isQueryActive {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effacer la recherche")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: 340)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.lineStrong, lineWidth: 1))
        }
        .onChange(of: searchText) {
            if searchText.isEmpty {
                searchTask?.cancel()
                searchResults = []
                errorMessage = nil
            } else if searchText.count >= 3 {
                performSearch()
            }
        }
    }

    private var periodLine: String {
        if let period = appState.discoverFeed?.period, !period.isEmpty {
            return "D'après les installations Homebrew du \(period) — sans ce que vous avez déjà."
        }
        return "Recommandations Homebrew, sans ce que vous avez déjà."
    }

    @ViewBuilder
    private var searchSection: some View {
        if isSearching {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Recherche dans le catalogue Homebrew...")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(Palette.textSecondary)
            }
        } else if searchResults.isEmpty {
            Text(errorMessage ?? "Aucun paquet pour « \(searchText) ».")
                .font(DesignSystem.Typography.body)
                .foregroundColor(Palette.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Résultats", subtitle: "\(searchResults.count) paquet(s), correspondances exactes en premier")
                LazyVGrid(columns: Self.columns, spacing: 12) {
                    ForEach(searchResults) { package in
                        DiscoverCard(name: package.name, type: package.type, description: package.description,
                                     version: package.latestVersion, meta: nil, metaIsGain: false, popularity: nil,
                                     packageID: package.id, onOpen: { detailPackage = package },
                                     onInstall: { appState.executePackageAction(package: package, action: .install) })
                    }
                }
            }
        }
    }

    private func performSearch() {
        let query = searchText
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        searchTask?.cancel()
        searchTask = Task {
            do {
                let results = try await BrewCatalogService.shared.searchGlobalPackages(query: query)
                guard !Task.isCancelled, searchText == query else { return }
                searchResults = results
            } catch {
                guard !Task.isCancelled, searchText == query else { return }
                searchResults = []
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    // MARK: Vitrine

    private static let columns = [GridItem(.adaptive(minimum: 250), spacing: 12)]

    @ViewBuilder
    private func feedSections(_ feed: DiscoverFeed) -> some View {
        if let hero = feed.sections.first(where: { $0.kind == .rising })?.items.first ?? feed.sections.first?.items.first {
            HeroCard(item: hero, onOpen: { detailPackage = hero.toBrewPackage() })
        }
        ForEach(feed.sections) { section in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionTitle(section.title, subtitle: section.subtitle)
                    Spacer()
                    if section.kind == .picks {
                        Button {
                            appState.reshuffleDiscover()
                        } label: {
                            Label("Autre tirage", systemImage: "shuffle")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(appState.isLoadingDiscover)
                    }
                }
                LazyVGrid(columns: Self.columns, spacing: 12) {
                    ForEach(section.items) { item in
                        DiscoverCard(name: item.name, type: item.isCask ? .cask : .formula, description: item.desc,
                                     version: item.version,
                                     meta: item.rankGain.map { "+\($0) places" } ?? item.rank.map { "#\($0)" },
                                     metaIsGain: item.rankGain != nil,
                                     popularity: item.installs.map(Self.popularity),
                                     packageID: item.id,
                                     onOpen: { detailPackage = item.toBrewPackage() },
                                     onInstall: { appState.executePackageAction(package: item.toBrewPackage(), action: .install) })
                    }
                }
            }
        }
    }

    static func popularity(_ installs: Int) -> String {
        let value = installs >= 1_000 ? "\(installs / 1_000) k" : "\(installs)"
        return "\(value) inst. / 30 j"
    }
}

// MARK: - Cartes

struct HeroCard: View {
    @EnvironmentObject var appState: AppState
    let item: CatalogItem
    let onOpen: () -> Void

    private let highlight = Color(light: 0xF5C27A, dark: 0xF5C27A)

    var body: some View {
        let package = item.toBrewPackage()
        let pending = appState.hasPendingTask(forPackage: package.id)
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Label(item.rankGain.map { "Plus forte progression du mois · +\($0) places" } ?? "À la une", systemImage: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(highlight)
                Text(item.name)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(item.desc)
                    .font(.system(size: 15))
                    .foregroundColor(Color(light: 0xD1D1D6, dark: 0xD1D1D6))
                    .lineLimit(2)
                Text([item.version, item.installs.map(DiscoverCatalogView.popularity), item.rank.map { "rang \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(Color(light: 0xAEAEB2, dark: 0xAEAEB2))
            }
            Spacer()
            VStack(spacing: 10) {
                Button {
                    appState.executePackageAction(package: package, action: .install)
                } label: {
                    Text(pending ? "Dans la file d'installation" : "Installer \(item.name)")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .foregroundColor(pending ? highlight : Color(light: 0x1C1C1E, dark: 0x1C1C1E))
                        .background(pending ? Color(light: 0x48484A, dark: 0x48484A) : highlight)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(pending)
                Button("Voir la fiche", action: onOpen)
                    .buttonStyle(.link)
                    .foregroundColor(highlight)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(Color(light: 0x1D1D1F, dark: 0x2C2C2E))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

struct DiscoverCard: View {
    @EnvironmentObject var appState: AppState
    let name: String
    let type: PackageType
    let description: String
    let version: String
    let meta: String?
    let metaIsGain: Bool
    let popularity: String?
    let packageID: String
    let onOpen: () -> Void
    let onInstall: () -> Void

    var body: some View {
        let pending = appState.hasPendingTask(forPackage: packageID)
        let installed = appState.isPackageInstalled(name: name)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                KindTag(type)
                Text(name)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let meta = meta {
                    Text(meta)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(metaIsGain ? Palette.success : Palette.textSecondary)
                }
            }
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(Palette.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            HStack(spacing: 8) {
                Text([version, popularity].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                if installed {
                    Label("Installé", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.success)
                } else {
                    Button(action: onInstall) {
                        Text(pending ? "Dans la file" : "Installer")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .foregroundColor(pending ? Palette.accentText : Palette.text)
                            .background(pending ? Palette.accentBackground : Palette.fill)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(pending ? Palette.accentLine : Palette.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(pending)
                    .accessibilityLabel("Installer \(name)")
                }
            }
        }
        .padding(14)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
