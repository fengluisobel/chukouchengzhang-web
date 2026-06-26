import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("首页", systemImage: "house.fill")
            }

            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("灵感库", systemImage: "square.stack.3d.up.fill")
            }

            NavigationStack {
                ReportsView()
            }
            .tabItem {
                Label("报告", systemImage: "chart.bar.xaxis")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
        }
        .tint(.orange)
    }
}
