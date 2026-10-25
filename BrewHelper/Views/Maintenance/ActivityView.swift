import SwiftUI

// L'Activité remplace le bandeau de progression et la console modale : chaque commande y est
// une tâche, en cours, en attente ou terminée, avec son journal consultable après coup.

enum TaskStatusStyle {
    static func tone(_ status: BrewTask.Status) -> Tone {
        switch status {
        case .queued: return .neutral
        case .running: return .warning
        case .succeeded: return .success
        case .failed: return .danger
        case .cancelled: return .neutral
        }
    }

    static func label(_ status: BrewTask.Status) -> String {
        switch status {
        case .queued: return "En attente"
        case .running: return "En cours"
        case .succeeded: return "Terminé"
        case .failed: return "Échec"
        case .cancelled: return "Retiré"
        }
    }
}

public struct ActivityView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedID: UUID? = nil
    @State private var showsRawLog: Bool = false

    public init() {}

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var selected: BrewTask? {
        let id = selectedID ?? appState.runningTask?.id ?? appState.tasks.last?.id
        return appState.tasks.first { $0.id == id }
    }

    public var body: some View {
        HStack(spacing: 0) {
            taskList
                .frame(minWidth: 380, idealWidth: 460, maxWidth: 520)
            Divider()
            logPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.bar)
        }
        .background(Palette.background)
    }

    // MARK: Tâches

    private var taskList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Activité").font(DesignSystem.Typography.title).foregroundColor(Palette.text)
                        Text("Chaque commande Homebrew est une tâche : elle attend son tour, sans bloquer l'interface, et garde son journal.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("Actualiser Homebrew") { appState.synchronizeCatalog() }
                    Button("Nettoyer") { appState.runMaintenance(command: .cleanup) }
                    Button("Diagnostic") { appState.runMaintenance(command: .doctor) }
                }
                .buttonStyle(SecondaryButtonStyle())

                if appState.tasks.isEmpty {
                    GlassCard {
                        Text("Aucune commande depuis le lancement de BrewHelper.")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(Palette.textSecondary)
                    }
                }

                group("En cours", appState.tasks.filter { $0.status == .running })
                group("À suivre", appState.tasks.filter { $0.status == .queued })
                let finished = appState.tasks.filter { $0.status.isFinished }.reversed()
                if !finished.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            groupTitle("Terminé")
                            Spacer()
                            Button("Effacer l'historique") { appState.clearFinishedTasks(); selectedID = nil }
                                .buttonStyle(.link)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        ForEach(Array(finished)) { task in taskCard(task) }
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ tasks: [BrewTask]) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                groupTitle(title)
                ForEach(tasks) { task in taskCard(task) }
            }
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundColor(Palette.textSecondary)
    }

    private func taskCard(_ task: BrewTask) -> some View {
        let isSelected = task.id == selected?.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(TaskStatusStyle.tone(task.status).mark).frame(width: 9, height: 9)
                Text(task.title).font(.system(size: 14, weight: .semibold)).foregroundColor(Palette.text)
                Spacer()
                Text(whenLabel(task)).font(.system(size: 11)).foregroundColor(Palette.textSecondary)
            }
            Text(detailLine(task))
                .font(DesignSystem.Typography.monospace)
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if task.status == .running {
                ProgressView().progressViewStyle(.linear).tint(Palette.warningMark)
            }
            if task.status == .queued {
                Button("Retirer de la file") { appState.cancelTask(task.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isSelected ? Palette.accentLine : Palette.line, lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedID = task.id }
        .accessibilityAddTraits(.isButton)
    }

    private func whenLabel(_ task: BrewTask) -> String {
        switch task.status {
        case .queued: return "en attente"
        case .running: return "depuis " + Self.timeFormatter.string(from: task.startedAt ?? task.createdAt)
        default: return Self.timeFormatter.string(from: task.finishedAt ?? task.createdAt)
        }
    }

    private func detailLine(_ task: BrewTask) -> String {
        if case .failed(let reason) = task.status { return reason }
        if task.status == .running, let line = task.lastLine { return line }
        return task.steps.map { $0.commandLine }.joined(separator: " puis ")
    }

    // MARK: Journal

    @ViewBuilder
    private var logPane: some View {
        if let task = selected {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Journal — \(task.title)").font(DesignSystem.Typography.sectionHeader).foregroundColor(Palette.text)
                    Spacer()
                    Picker("", selection: $showsRawLog) {
                        Text("Résumé").tag(false)
                        Text("Sortie brute").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
                if showsRawLog {
                    rawLog(task)
                } else {
                    summary(task)
                    Spacer()
                }
            }
            .padding(24)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "text.alignleft").font(.system(size: 28)).foregroundColor(Palette.textSecondary)
                Text("Le journal de la tâche sélectionnée s'affiche ici.")
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summary(_ task: BrewTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(task.steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(TaskStatusStyle.tone(step.status).mark).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.commandLine).font(DesignSystem.Typography.monospace).foregroundColor(Palette.text)
                        Text(stepDetail(step)).font(.system(size: 12)).foregroundColor(Palette.textSecondary)
                    }
                }
            }
            if let line = task.lastLine, task.status == .running {
                Text(line)
                    .font(DesignSystem.Typography.monospace)
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    private func stepDetail(_ step: BrewTask.Step) -> String {
        if case .failed(let reason) = step.status { return reason }
        return TaskStatusStyle.label(step.status)
    }

    private func rawLog(_ task: BrewTask) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(task.log.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(line.hasPrefix("$ ") ? Palette.accentText : Palette.consoleText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .padding(14)
            }
            .background(Palette.console)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: task.log.count) {
                proxy.scrollTo(task.log.count - 1, anchor: .bottom)
            }
        }
    }
}
