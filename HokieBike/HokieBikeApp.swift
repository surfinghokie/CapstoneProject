//
//  HokieBikeApp.swift
//  HokieBike
//
//  Created by John  Hewitt II  on 9/22/26.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}

@main
struct HokieBikeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authManager = AuthSessionManager()

    var body: some Scene {
        WindowGroup {
            RootLaunchView()
                .environmentObject(authManager)
        }
    }
}
