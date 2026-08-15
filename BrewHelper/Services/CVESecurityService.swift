import Foundation
import Combine
import SwiftUI

@MainActor
public class CVESecurityService: ObservableObject {
    public static let shared = CVESecurityService()

    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var currentPackageScanned: String = ""
    @Published public private(set) var totalToScan: Int = 0
    @Published public private(set) var scannedCount: Int = 0
    @Published public private(set) var source: VulnDatabaseSource

    // In-memory vulnerability DB for this run. Only flaws that are still open on the
    // installed version are stored — anything already patched is dropped at scan time.
    @Published public var packageVulnerabilities: [String: [CVEVulnerability]] = [:]
    /// Version each cached result was computed against, so an upgrade invalidates it.
    @Published public private(set) var scannedVersions: [String: String] = [:]

    /// Number of packages carrying at least one open advisory.
    public var vulnerableCount: Int {
        packageVulnerabilities.values.filter { !$0.isEmpty }.count
    }

    private var scanTask: Task<Void, Never>? = nil
    private let urlSession: URLSession = .shared
    private static let sourceDefaultsKey = "BrewHelper.VulnDatabaseSource"

    public init() {
        if let saved = UserDefaults.standard.string(forKey: Self.sourceDefaultsKey),
           let restored = VulnDatabaseSource(rawValue: saved) {
            self.source = restored
        } else {
            self.source = .euvd
        }
    }

    /// Cached result for a package, but only while it was computed against the version
    /// currently on disk — upgrading a package changes every patch verdict.
    public func cachedVulnerabilities(for package: BrewPackage) -> [CVEVulnerability]? {
        guard scannedVersions[package.name] == package.installedVersion else { return nil }
        return packageVulnerabilities[package.name]
    }

    // Switches the active vulnerability database, wipes cached results (they're not comparable
    // across sources) and re-scans the given packages against the newly selected source.
    public func switchSource(to newSource: VulnDatabaseSource, packages: [BrewPackage], onUpdate: @escaping (String, PackageCVEStatus) -> Void) {
        guard newSource != source else { return }
        scanTask?.cancel()
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: Self.sourceDefaultsKey)
        packageVulnerabilities.removeAll()
        scannedVersions.removeAll()
        scannedCount = 0
        totalToScan = 0
        for package in packages {
            onUpdate(package.id, .unscanned)
        }
        startBackgroundScan(for: packages, onUpdate: onUpdate)
    }

    public func startBackgroundScan(for packages: [BrewPackage], onUpdate: @escaping (String, PackageCVEStatus) -> Void) {
        scanTask?.cancel()

        let toScan = packages.filter { cachedVulnerabilities(for: $0) == nil }

        guard !toScan.isEmpty else { return }

        self.isScanning = true
        self.totalToScan = toScan.count
        self.scannedCount = 0

        scanTask = Task {
            for package in toScan {
                if Task.isCancelled { break }

                self.currentPackageScanned = package.name
                onUpdate(package.id, .scanning)

                let openFlaws = await fetchOpenVulnerabilities(for: package)

                self.store(openFlaws, for: package)
                self.scannedCount += 1

                if openFlaws.isEmpty {
                    onUpdate(package.id, .clean)
                } else {
                    let highestSev = openFlaws.map { $0.severity }.max() ?? .low
                    onUpdate(package.id, .vulnerable(cveCount: openFlaws.count, highestSeverity: highestSev))
                }

                try? await Task.sleep(nanoseconds: source.interRequestDelayNanoseconds)
            }
            self.isScanning = false
            self.currentPackageScanned = "Audit terminé"
        }
    }

    public func checkSinglePackageNow(package: BrewPackage, force: Bool = false) async -> [CVEVulnerability] {
        if !force, let cached = cachedVulnerabilities(for: package) {
            return cached
        }
        let results = await fetchOpenVulnerabilities(for: package)
        store(results, for: package)
        return results
    }

    private func store(_ vulnerabilities: [CVEVulnerability], for package: BrewPackage) {
        packageVulnerabilities[package.name] = vulnerabilities
        scannedVersions[package.name] = package.installedVersion
    }

    // MARK: - Fetching & filtering

    /// Queries the active database, cross-checks every hit against the installed version and
    /// returns only the flaws still open on this Mac, newest first.
    private func fetchOpenVulnerabilities(for package: BrewPackage) async -> [CVEVulnerability] {
        let assessed: [CVEVulnerability]
        switch source {
        case .nvd: assessed = await fetchNVDCVEs(for: package)
        case .euvd: assessed = await fetchEUVDCVEs(for: package)
        }
        return Self.openFlawsNewestFirst(assessed)
    }

    /// Drops everything the installed version already fixes, then orders the remainder from
    /// the most recent CVE to the oldest (severity only breaks ties between same-day entries).
    static func openFlawsNewestFirst(_ assessed: [CVEVulnerability]) -> [CVEVulnerability] {
        var deduplicated: [String: CVEVulnerability] = [:]
        for vulnerability in assessed where vulnerability.isStillOpen() {
            // The same flaw can surface twice (CVE id + database alias); keep the worst one.
            if let existing = deduplicated[vulnerability.id], existing.severity >= vulnerability.severity { continue }
            deduplicated[vulnerability.id] = vulnerability
        }

        return deduplicated.values.sorted { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.id > rhs.id
        }
    }

    /// NVD serves keyword results **oldest first**, so a small page only ever exposed
    /// CVEs from the nineties. We take a large page and, when the product has more hits than
    /// that, jump to the last page — the recent flaws are the ones that can still be open.
    private static let nvdPageSize = 200

    private func fetchNVDCVEs(for package: BrewPackage) async -> [CVEVulnerability] {
        // Sanitize & encode package name safely
        let cleanName = package.name.components(separatedBy: "@").first ?? package.name
        guard let encodedName = cleanName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let baseURL = "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=\(encodedName)&resultsPerPage=\(Self.nvdPageSize)"

        guard let firstPage = await fetchNVD(urlString: baseURL) else { return [] }

        var items = firstPage.vulnerabilities ?? []
        if let total = firstPage.totalResults, total > Self.nvdPageSize {
            let startIndex = total - Self.nvdPageSize
            if let lastPage = await fetchNVD(urlString: "\(baseURL)&startIndex=\(startIndex)"),
               let recent = lastPage.vulnerabilities {
                items = recent
            }
        }

        return items.compactMap { $0.cve?.assess(for: package) }
    }

    private func fetchNVD(urlString: String) async -> NVDCVEResponse? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12.0
        request.setValue("BrewHelper/1.0 macOS Native Security Scanner", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(NVDCVEResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func fetchEUVDCVEs(for package: BrewPackage) async -> [CVEVulnerability] {
        let cleanName = package.name.components(separatedBy: "@").first ?? package.name
        // `product=` searches the advisories' declared products, where `text=` searches the whole
        // description — the latter drowns a formula like "node" in unrelated kernel CVEs that
        // merely use the word. An advisory whose product name doesn't contain the package name
        // is rejected downstream anyway, so nothing relevant is lost.
        guard let encodedName = cleanName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://euvdservices.enisa.europa.eu/api/search?product=\(encodedName)&size=50") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12.0
        request.setValue("BrewHelper/1.0 macOS Native Security Scanner", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return []
            }

            let decoder = JSONDecoder()
            let euvdResp = try decoder.decode(EUVDSearchResponse.self, from: data)

            guard let items = euvdResp.items else { return [] }
            return items.compactMap { $0.assess(for: package) }
        } catch {
            return []
        }
    }
}
