import SwiftUI

@main
struct ChuKouChengZhangApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(viewModel)
                .task {
                    await viewModel.loadRemoteBootstrapIfNeeded()
                }
        }
    }
}
