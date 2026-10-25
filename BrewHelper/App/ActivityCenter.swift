import Foundation

// Chaque commande Homebrew devient une tâche : elle attend son tour dans une file sérielle,
// garde son journal, et laisse l'interface libre. Avant, deux commandes lancées coup sur coup
// partaient en parallèle (et se disputaient le verrou de Homebrew), et leur sortie n'existait
// que dans une console modale réécrite à chaque commande.

public struct BrewTask: Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case queued, running, succeeded, cancelled
        case failed(String)

        public var isFinished: Bool {
            switch self {
            case .queued, .running: return false
            case .succeeded, .failed, .cancelled: return true
            }
        }
    }

    public struct Step: Sendable {
        public let arguments: [String]
        public var status: Status = .queued

        public var commandLine: String { "brew " + arguments.joined(separator: " ") }
    }

    public let id = UUID()
    public let title: String
    public var steps: [Step]
    public var status: Status = .queued
    /// Sortie brute, ligne par ligne, plafonnée pour qu'un `brew upgrade` bavard ne grossisse pas sans fin.
    public var log: [String] = []
    /// Dernière ligne non vide : ce que la tâche fait en ce moment.
    public var lastLine: String? = nil
    public let createdAt = Date()
    public var startedAt: Date? = nil
    public var finishedAt: Date? = nil
    /// Paquet concerné (installation, mise à jour...), pour que les vues sachent qu'il est en file.
    public let packageID: String?

    static let maxLogLines = 5_000
}

extension AppState {
    /// Met une tâche en file. Ses commandes s'exécutent dans l'ordre ; la première qui échoue arrête la tâche.
    @discardableResult
    public func enqueue(_ title: String, commands: [[String]], packageID: String? = nil) -> UUID {
        let task = BrewTask(title: title, steps: commands.map { BrewTask.Step(arguments: $0) }, packageID: packageID)
        tasks.append(task)
        pumpQueue()
        return task.id
    }

    /// Retire une tâche qui n'a pas encore commencé. Une tâche en cours va au bout : interrompre
    /// Homebrew au milieu d'une installation laisserait le Cellar dans un état incohérent.
    public func cancelTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].status == .queued else { return }
        tasks[index].status = .cancelled
        tasks[index].finishedAt = Date()
    }

    public func clearFinishedTasks() {
        tasks.removeAll { $0.status.isFinished }
    }

    public var runningTask: BrewTask? { tasks.first { $0.status == .running } }
    public var pendingTaskCount: Int { tasks.filter { !$0.status.isFinished }.count }

    /// Le paquet a-t-il une tâche en attente ou en cours ?
    public func hasPendingTask(forPackage packageID: String) -> Bool {
        tasks.contains { $0.packageID == packageID && !$0.status.isFinished }
    }

    func pumpQueue() {
        guard !isQueueRunning, let next = tasks.first(where: { $0.status == .queued }) else { return }
        isQueueRunning = true
        Task { await self.run(next.id) }
    }

    private func run(_ id: UUID) async {
        guard let start = tasks.firstIndex(where: { $0.id == id }) else { isQueueRunning = false; return }
        tasks[start].status = .running
        tasks[start].startedAt = Date()

        var outcome: BrewTask.Status = .succeeded
        for stepIndex in tasks[start].steps.indices {
            let arguments = tasks[start].steps[stepIndex].arguments
            update(id) {
                $0.steps[stepIndex].status = .running
                $0.log.append("$ brew " + arguments.joined(separator: " "))
            }
            do {
                let code = try await BrewCommandService.shared.runCommandWithStreaming(arguments: arguments) { [weak self] chunk in
                    self?.appendOutput(chunk, to: id)
                }
                if code == 0 {
                    update(id) { $0.steps[stepIndex].status = .succeeded }
                } else {
                    let reason = "brew \(arguments.first ?? "") a renvoyé le code \(code)"
                    update(id) { $0.steps[stepIndex].status = .failed(reason) }
                    outcome = .failed(reason)
                    break
                }
            } catch {
                update(id) { $0.steps[stepIndex].status = .failed(error.localizedDescription) }
                outcome = .failed(error.localizedDescription)
                break
            }
        }

        update(id) {
            $0.status = outcome
            $0.finishedAt = Date()
            // Les étapes jamais lancées après un échec ne doivent pas rester « en attente ».
            for index in $0.steps.indices where $0.steps[index].status == .queued {
                $0.steps[index].status = .cancelled
            }
        }

        isQueueRunning = false
        // Les versions installées ont pu changer : les plans et verdicts calculés contre
        // l'ancienne version ne valent plus rien.
        RemediationService.shared.invalidate()
        await refreshAll()
        pumpQueue()
    }

    private func appendOutput(_ chunk: String, to id: UUID) {
        let lines = chunk.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return }
        update(id) { task in
            task.log.append(contentsOf: lines)
            if task.log.count > BrewTask.maxLogLines {
                task.log.removeFirst(task.log.count - BrewTask.maxLogLines)
            }
            if let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                task.lastLine = last.trimmingCharacters(in: .whitespaces)
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout BrewTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&tasks[index])
    }
}
