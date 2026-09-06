import SwiftUI

public struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 16) {
                // Brand Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DesignSystem.Colors.amberGradient)
                            .frame(width: 38, height: 38)
                            .shadow(color: .orange.opacity(0.4), radius: 6, y: 2)
                        Image(systemName: "mug.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BrewHelper")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("macOS Native GUI")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                
                Divider()
                
                // Navigation Links
                List(NavigationTab.allCases, selection: $appState.selectedTab) { tab in
                    NavigationLink(value: tab) {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15))
                                .frame(width: 22)
                            
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .medium))
                            
                            Spacer()
                            
                            if tab == .outdated && appState.outdatedCount > 0 {
                                Text("\(appState.outdatedCount)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            } else if tab == .securityAudit && appState.vulnerableCount > 0 {
                                Text("\(appState.vulnerableCount)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .tag(tab)
                }
                .listStyle(.sidebar)
                
                Spacer()
                
                // Refresh Button & Status Footer
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    HStack {
                        if appState.isLoading || appState.isCommandRunning || appState.isSyncingCatalog {
                            ProgressView()
                                .controlSize(.small)
                            Text("Synchronisation...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: {
                                appState.runMaintenance(command: .updateOnly)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                    Text("Actualiser Homebrew")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            .frame(minWidth: 220)
            .background(DesignSystem.Colors.sidebarBackground)
        } detail: {
            VStack(spacing: 0) {
                // LIVE STATUS BANNER (Barre de Progression Silencieuese en Tâche de Fond)
                if let msg = appState.activeOperationMessage {
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            if appState.isCommandRunning || appState.isSyncingCatalog {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(msg)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)
                                if let detail = appState.activeOperationDetail, !detail.isEmpty {
                                    Text(detail)
                                        .font(DesignSystem.Typography.monospace)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            Button("Console Terminal") {
                                appState.isTerminalPresented = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.blue)
                        }
                        if appState.isCommandRunning || appState.isSyncingCatalog {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.98))
                    .overlay(
                        Rectangle().frame(height: 1).foregroundColor(Color(NSColor.separatorColor)),
                        alignment: .bottom
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: appState.activeOperationMessage)
                }
                
                // Main Detail Content Area
                Group {
                    if appState.selectedTab == .dashboard {
                        DashboardView()
                    } else if appState.selectedTab == .discover {
                        DiscoverCatalogView()
                    } else if appState.selectedTab == .securityAudit {
                        SecurityAuditView()
                    } else {
                        PackageListView(currentTab: appState.selectedTab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onAppear {
            appState.onAppearInitialLoad()
        }
        .sheet(isPresented: $appState.isTerminalPresented) {
            TerminalLogModalView()
        }
    }
}
