import Foundation

public enum BrewCommandType: String {
    case doctor = "brew doctor"
    case cleanup = "brew cleanup"
    case update = "brew update && brew upgrade"
    case updateOnly = "brew update"
    case upgradeAll = "brew upgrade"
}

public enum PackageAction: String {
    case upgrade = "upgrade"
    case uninstall = "uninstall"
    case reinstall = "reinstall"
    case install = "install"
}

public enum BrewCommandError: LocalizedError {
    case binaryNotFound
    case executionFailed(Int32, String)
    case jsonDecodingError(String)
    
    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Le binaire Homebrew est introuvable (/opt/homebrew/bin/brew ou /usr/local/bin/brew)."
        case .executionFailed(let code, let msg):
            return "Commande échouée (code \(code)) : \(msg)"
        case .jsonDecodingError(let msg):
            return "Erreur de parsing JSON : \(msg)"
        }
    }
}

public final class BrewCommandService: @unchecked Sendable {
    public static let shared = BrewCommandService()
    
    private var brewExecutablePath: String? {
        let armPath = "/opt/homebrew/bin/brew"
        let intelPath = "/usr/local/bin/brew"
        if FileManager.default.fileExists(atPath: armPath) { return armPath }
        if FileManager.default.fileExists(atPath: intelPath) { return intelPath }
        return nil
    }
    
    public init() {}
    
    // Helper to strip any Homebrew network logs, progress or notices before `{` and after `}`
    public func extractCleanJSONData(from data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8) else { return data }
        if let firstBrace = string.firstIndex(of: "{"),
           let lastBrace = string.lastIndex(of: "}") {
            let jsonSub = string[firstBrace...lastBrace]
            return Data(jsonSub.utf8)
        }
        return data
    }
    
    // MARK: - Step 1: Ultra-Fast Local Disk Read (< 0.2s) without network blocks!
    public func fetchInstalledPackagesOnly() async throws -> [BrewPackage] {
        guard let brewPath = brewExecutablePath else {
            print("🚨 [BrewCommandService] Binaire Homebrew introuvable!")
            throw BrewCommandError.binaryNotFound
        }
        
        print("⚡️ [BrewCommandService] Lecture rapide locale du Cellar via \(brewPath)...")
        
        let (outputData, exitCode, errOutput) = try await runSynchronous(path: brewPath, arguments: ["info", "--installed", "--json=v2"])
        
        if exitCode != 0 && outputData.isEmpty {
            print("🚨 [BrewCommandService] Échec commande brew info (code \(exitCode)) : \(errOutput)")
            throw BrewCommandError.executionFailed(exitCode, errOutput)
        }
        
        let cleanedData = extractCleanJSONData(from: outputData)
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(BrewJSONResponseV2.self, from: cleanedData)
            
            var allPackages: [BrewPackage] = []
            
            for f in response.formulae {
                allPackages.append(f.toBrewPackage(outdatedList: []))
            }
            
            for c in response.casks {
                allPackages.append(c.toBrewPackage(outdatedList: []))
            }
            
            let sorted = allPackages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            print("✅ [BrewCommandService] Lecture locale instantanée réussie : \(sorted.count) paquets en mémoire.")
            return sorted
        } catch {
            print("🚨 [BrewCommandService] Erreur de parsing JSON : \(error.localizedDescription)")
            throw BrewCommandError.jsonDecodingError(error.localizedDescription)
        }
    }
    
    // MARK: - Step 2: Background Network Outdated Check (non-blocking)
    public func fetchOutdatedSet() async throws -> Set<String> {
        guard let brewPath = brewExecutablePath else {
            return []
        }
        
        print("🌐 [BrewCommandService] Lancement de la vérification distante des catalogues (brew outdated)...")
        var outdatedSet: Set<String> = []
        let result = try await runSynchronous(path: brewPath, arguments: ["outdated", "--json=v2"])
        let cleanedOutdated = extractCleanJSONData(from: result.data)
        if let decoded = try? JSONDecoder().decode(BrewOutdatedResponseV2.self, from: cleanedOutdated) {
            if let formulae = decoded.formulae {
                for item in formulae { outdatedSet.insert(item.name) }
            }
            if let casks = decoded.casks {
                for item in casks { outdatedSet.insert(item.name) }
            }
        }
        print("🔄 [BrewCommandService] Vérification réseau terminée ! \(outdatedSet.count) paquet(s) obsolètes : \(outdatedSet)")
        return outdatedSet
    }
    
    public func fetchAllPackages() async throws -> [BrewPackage] {
        let pkgs = try await fetchInstalledPackagesOnly()
        guard let outdated = try? await fetchOutdatedSet() else { return pkgs }
        return pkgs.map { pkg in
            var copy = pkg
            copy.isOutdated = outdated.contains(pkg.name) && (pkg.installedVersion != pkg.latestVersion)
            return copy
        }
    }
    
    // MARK: - Run Maintenance / Interactive Tasks with Live Output Streaming
    public func runCommandWithStreaming(arguments: [String], onLog: @escaping (String) -> Void) async throws -> Int32 {
        guard let brewPath = brewExecutablePath else {
            throw BrewCommandError.binaryNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = arguments
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["HOMEBREW_NO_ANALYTICS"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_INSECURE_REDIRECT"] = "1"
            env["HOMEBREW_CURL_RETRIES"] = "3"
            process.environment = env
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                    DispatchQueue.main.async {
                        onLog(line)
                    }
                }
            }
            
            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
                if let line = String(data: remainingData, encoding: .utf8), !line.isEmpty {
                    DispatchQueue.main.async {
                        onLog(line)
                    }
                }
                continuation.resume(returning: proc.terminationStatus)
            }
            
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
    
    public func executePackageAction(package: BrewPackage, action: PackageAction, onLog: @escaping (String) -> Void) async throws {
        var args = [action.rawValue]
        if package.type == .cask && (action == .install || action == .reinstall) {
            args.append("--cask")
        }
        let sanitizedFullName = package.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        args.append(sanitizedFullName)
        
        let code = try await runCommandWithStreaming(arguments: args, onLog: onLog)
        if code != 0 {
            throw BrewCommandError.executionFailed(code, "L'action \(action.rawValue) sur \(package.name) a renvoyé une erreur (Code \(code)).")
        }
    }
    
    // MARK: - Public helper for synchronous command execution (used by Catalog search)
    public func runSynchronous(arguments: [String]) async throws -> (data: Data, exitCode: Int32, errorOutput: String) {
        guard let path = brewExecutablePath else {
            throw BrewCommandError.binaryNotFound
        }
        return try await runSynchronous(path: path, arguments: arguments)
    }
    
    private func runSynchronous(path: String, arguments: [String]) async throws -> (data: Data, exitCode: Int32, errorOutput: String) {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["HOMEBREW_NO_ANALYTICS"] = "1"
            env["HOMEBREW_NO_ENV_HINTS"] = "1"
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_INSECURE_REDIRECT"] = "1"
            env["HOMEBREW_CURL_RETRIES"] = "3"
            process.environment = env
            
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            
            let outHandle = outPipe.fileHandleForReading
            let errHandle = errPipe.fileHandleForReading
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            
            let errTask = Task.detached {
                (try? errHandle.readToEnd()) ?? Data()
            }
            
            let outData = (try? outHandle.readToEnd()) ?? Data()
            
            Task {
                let errData = await errTask.value
                process.waitUntilExit()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: (outData, process.terminationStatus, errStr))
            }
        }
    }
}
