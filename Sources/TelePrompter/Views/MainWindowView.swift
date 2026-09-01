import SwiftUI
import AppKit

// MARK: - MainWindowView
// The main application window with sidebar navigation.

struct MainWindowView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: TeleprompterState
    @EnvironmentObject var storage: ScriptStorage
    @EnvironmentObject var windowManager: WindowManager
    @EnvironmentObject var sessionController: SessionController

    @State private var selectedSection: SidebarSection = .scripts
    @State private var showOnboarding: Bool = false

    enum SidebarSection: String, CaseIterable, Identifiable {
        case scripts     = "Scripts"
        case teleprompter = "Teleprompter"
        case settings    = "Settings"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .scripts:      return "doc.text"
            case .teleprompter: return "tv"
            case .settings:     return "gear"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle("TelePrompter")
        .toolbar { toolbarContent }
        .onAppear {
            if !settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .environmentObject(settings)
                .environmentObject(sessionController)
        }
        .frame(minWidth: 800, minHeight: 560)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SidebarSection.allCases, selection: $selectedSection) { section in
            Label(section.rawValue, systemImage: section.systemImage)
                .tag(section)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        .listStyle(.sidebar)
    }

    // MARK: - Detail view

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .scripts:
            ScriptLibraryView()
        case .teleprompter:
            TeleprompterControlView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Following state button
            Button {
                sessionController.toggleFollowing()
            } label: {
                Label(
                    state.followingState.isActive ? "Stop Following" : "Start Following",
                    systemImage: state.followingState.isActive ? "stop.circle.fill" : "waveform.circle.fill"
                )
                .foregroundStyle(state.followingState.isActive ? .red : .green)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .help("Start or stop voice following (⌘↩)")

            // Teleprompter visibility
            Button {
                windowManager.toggleTeleprompter()
            } label: {
                Label(
                    windowManager.isTeleprompterVisible ? "Hide Teleprompter" : "Show Teleprompter",
                    systemImage: windowManager.isTeleprompterVisible ? "eye.slash" : "eye"
                )
            }
            .help("Show or hide the teleprompter window")

            // Recording mode shortcut
            Button {
                sessionController.toggleRecordingMode()
            } label: {
                Label("Recording Mode", systemImage: "record.circle")
                    .foregroundStyle(settings.readingMode == .recording ? .red : .primary)
            }
            .help("Toggle recording mode")
        }
    }
}


