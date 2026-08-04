import SwiftUI

public struct TerminalLogModalView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Window Bar
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 12, height: 12)
                    Circle().fill(Color.yellow).frame(width: 12, height: 12)
                    Circle().fill(Color.green).frame(width: 12, height: 12)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .foregroundColor(.gray)
                    Text(appState.terminalTitle)
                        .font(DesignSystem.Typography.sectionHeader)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                if appState.isCommandRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else {
                    Button(action: {
                        appState.isTerminalPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Console Logs Area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(appState.terminalLogs.enumerated()), id: \.offset) { idx, line in
                            HStack(alignment: .top, spacing: 8) {
                                Text(">")
                                    .foregroundColor(line.contains("❌") ? .red : (line.contains("✅") ? .green : .cyan))
                                    .font(DesignSystem.Typography.monospace)
                                
                                Text(line)
                                    .font(DesignSystem.Typography.monospace)
                                    .foregroundColor(line.contains("❌") || line.contains("Error") ? .red : .white.opacity(0.9))
                                    .textSelection(.enabled)
                            }
                            .id(idx)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black.opacity(0.85))
                .onChange(of: appState.terminalLogs.count) {
                    if let lastIdx = appState.terminalLogs.indices.last {
                        withAnimation {
                            proxy.scrollTo(lastIdx, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Bottom Action Bar
            HStack {
                if appState.isCommandRunning {
                    Label("Exécution dans Homebrew en cours...", systemImage: "gear.badge")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(.orange)
                } else {
                    Label("Processus terminé", systemImage: "checkmark.circle.fill")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Button(action: {
                    appState.isTerminalPresented = false
                }) {
                    Text(appState.isCommandRunning ? "Réduire en arrière-plan" : "Fermer")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(appState.isCommandRunning ? Color.gray.opacity(0.3) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        }
        .frame(width: 700, height: 480)
        .background(Color.black)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }
}
