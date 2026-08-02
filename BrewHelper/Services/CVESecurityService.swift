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
    @Published public private(set) var vulnerableCount: Int = 0
    
    // In-memory persistent vulnerability DB during run
    @Published public var packageVulnerabilities: [String: [CVEVulnerability]] = [:]
    
    private var scanTask: Task<Void, Never>? = nil
    private let urlSession: URLSession = .shared
    
    public init() {}
    
    public func startBackgroundScan(for packages: [BrewPackage], onUpdate: @escaping (String, PackageCVEStatus) -> Void) {
        scanTask?.cancel()
        
        let toScan = packages.filter { package in
            return packageVulnerabilities[package.name] == nil
        }
        
        guard !toScan.isEmpty else { return }
        
        self.isScanning = true
        self.totalToScan = toScan.count
        self.scannedCount = 0
        
        scanTask = Task {
            for package in toScan {
                if Task.isCancelled { break }
                
                self.currentPackageScanned = package.name
                onUpdate(package.id, .scanning)
                
                let cves = await fetchCVEs(for: package)
                
                self.packageVulnerabilities[package.name] = cves
                self.scannedCount += 1
                
                if cves.isEmpty {
                    onUpdate(package.id, .clean)
                } else {
                    self.vulnerableCount += 1
                    let highestSev = cves.map { $0.severity }.max() ?? .low
                    onUpdate(package.id, .vulnerable(cveCount: cves.count, highestSeverity: highestSev))
                }
                
                // Rate-limiting delay (~1.2 seconds) to respect NIST NVD API limits
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            self.isScanning = false
            self.currentPackageScanned = "Audit terminé"
        }
    }
    
    public func checkSinglePackageNow(package: BrewPackage) async -> [CVEVulnerability] {
        if let cached = packageVulnerabilities[package.name] {
            return cached
        }
        let results = await fetchCVEs(for: package)
        packageVulnerabilities[package.name] = results
        if !results.isEmpty {
            vulnerableCount += 1
        }
        return results
    }
    
    private func fetchCVEs(for package: BrewPackage) async -> [CVEVulnerability] {
        // Sanitize & encode package name safely
        let cleanName = package.name.components(separatedBy: "@").first ?? package.name
        guard let encodedName = cleanName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=\(encodedName)&resultsPerPage=15") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue("BrewHelper/1.0 macOS Native Security Scanner", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return []
            }
            
            let decoder = JSONDecoder()
            let nvdResp = try decoder.decode(NVDCVEResponse.self, from: data)
            
            guard let vulnItems = nvdResp.vulnerabilities else { return [] }
            
            var converted: [CVEVulnerability] = []
            for item in vulnItems {
                if let cveData = item.cve, cveData.isRelevantFor(package: package) {
                    converted.append(cveData.toVulnerability())
                }
            }
            return converted.sorted { $0.severity > $1.severity }
        } catch {
            return []
        }
    }
}
