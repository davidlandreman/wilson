import SwiftUI

struct ContentView: View {
    @Environment(\.appState) private var appState
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: SidebarItem.dashboard) {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                NavigationLink(value: SidebarItem.lightDesigner) {
                    Label("Light Designer", systemImage: "lightbulb")
                }
                NavigationLink(value: SidebarItem.virtualStage) {
                    Label("Virtual Stage", systemImage: "theatermasks")
                }
                NavigationLink(value: SidebarItem.audioDebug) {
                    Label("Audio Debug", systemImage: "waveform")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .dashboard, .none:
                DashboardView()
            case .lightDesigner:
                LightDesignerView()
            case .virtualStage:
                VirtualStageView()
            case .audioDebug:
                AudioDebugView()
            }
        }
    }
}

enum SidebarItem: Hashable {
    case dashboard
    case lightDesigner
    case virtualStage
    case audioDebug
}

#Preview {
    ContentView()
        .environment(\.appState, AppState())
}
