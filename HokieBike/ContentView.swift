//
//  ContentView.swift
//  HokieBike
//
//  Created by John  Hewitt II  on 9/22/26.
//

import SwiftUI

enum AppTab: Hashable {
    case go
    case explore
    case activity
    case account
}

/// Main app content view that provides the TabView navigation
struct ContentView: View {
    @EnvironmentObject var authManager: AuthSessionManager
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var rideTrackingManager = RideTrackingManager()
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @AppStorage("hasCompletedProfileSetup") private var hasCompletedProfileSetup = false
    @State private var selectedTab: AppTab = .go
    @State private var showProfileSetup = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                GoView(selectedTab: $selectedTab)
            }
            .environmentObject(viewModel)
            .environmentObject(rideTrackingManager)
            .tag(AppTab.go)
            .tabItem {
                Label("Go", systemImage: "bicycle")
            }

            NavigationStack {
                ExploreView()
            }
            .environmentObject(viewModel)
            .environmentObject(rideTrackingManager)
            .tag(AppTab.explore)
            .tabItem {
                Label("Explore", systemImage: "map")
            }

            NavigationStack {
                ActivityView()
            }
            .environmentObject(viewModel)
            .environmentObject(rideTrackingManager)
            .tag(AppTab.activity)
            .tabItem {
                Label("Activity", systemImage: "person.3")
            }

            NavigationStack {
                AccountView()
            }
            .environmentObject(viewModel)
            .environmentObject(rideTrackingManager)
            .tag(AppTab.account)
            .tabItem {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
        .tint(Color("VTMaroon"))
        .preferredColorScheme(preferredColorScheme)
        .onReceive(authManager.$state) { state in
            switch state {
            case .signedIn(let session):
                viewModel.configureBackendSession(uid: session.uid, email: session.email)
                showProfileSetup = false
            default:
                viewModel.clearBackendSession()
                showProfileSetup = false
            }
        }
        .onReceive(viewModel.$didFinishInitialProfileLoad) { didFinish in
            guard didFinish else { return }
            guard authManager.isAuthenticated else { return }

            let name = viewModel.currentUser.name.trimmingCharacters(in: .whitespacesAndNewlines)
            showProfileSetup = !hasCompletedProfileSetup && name.isEmpty
        }
        .sheet(isPresented: $showProfileSetup) {
            ProfileSetupView(
                initialName: viewModel.currentUser.name,
                initialIsVTStudent: viewModel.currentUser.isVTStudent
            ) { name, isVTStudent, profileImageData in
                viewModel.updateCurrentUserProfile(name: name, isVTStudent: isVTStudent, profileImageData: profileImageData)
                hasCompletedProfileSetup = true
                showProfileSetup = false
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthSessionManager())
    }
}
