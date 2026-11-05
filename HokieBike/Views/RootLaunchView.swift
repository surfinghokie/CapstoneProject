import SwiftUI

struct RootLaunchView: View {
    @EnvironmentObject var authManager: AuthSessionManager

    var body: some View {
        Group {
            switch authManager.state {
            case .checking:
                ProgressView("Checking session...")
            case .signedIn:
                ContentView()
            case .signedOut, .linkSent, .unavailable:
                NavigationStack {
                    LoginView()
                }
            }
        }
        .onOpenURL { url in
            authManager.handleIncomingLink(url)
        }
    }
}

#Preview {
    RootLaunchView()
        .environmentObject(AuthSessionManager())
}
