import Foundation
import SwiftUI
import Combine

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@MainActor
final class AuthSessionManager: ObservableObject {
    enum State {
        case checking
        case signedOut
        case linkSent(String)
        case signedIn(UserSession)
        case unavailable(String)
    }

    struct UserSession {
        let uid: String
        let email: String
    }

    @Published var state: State = .checking
    @Published var emailInput = ""
    @Published var statusMessage: String?

    private let pendingEmailKey = "hokiebike.pendingLoginEmail"
    private let demoSessionEmailKey = "hokiebike.demoSessionEmail"
    private let demoModeEnabled = false

#if canImport(FirebaseAuth)
    private var authListener: AuthStateDidChangeListenerHandle?
#endif

    init() {
        configureFirebaseIfPossible()
        observeAuthState()
    }

    var isAuthenticated: Bool {
        if case .signedIn = state { return true }
        return false
    }

    func sendVTSignInLink() async {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard isVTEmail(email) else {
            statusMessage = "Use your @vt.edu or @g.vt.edu email."
            return
        }

        if demoModeEnabled {
            signInLocally(with: email)
            return
        }

#if canImport(FirebaseAuth)
        guard let bundleID = Bundle.main.bundleIdentifier else {
            statusMessage = "Missing app bundle identifier."
            return
        }

        let settings = ActionCodeSettings()
        settings.handleCodeInApp = true
        // Use the hosting root as a safe continue URL to avoid 404 landing paths.
        settings.url = URL(string: "https://hokiebike.firebaseapp.com")
        settings.setIOSBundleID(bundleID)

        do {
            try await Auth.auth().sendSignInLink(toEmail: email, actionCodeSettings: settings)
            UserDefaults.standard.set(email, forKey: pendingEmailKey)
            state = .linkSent(email)
            statusMessage = "Sign-in link sent to \(email)."
        } catch {
            let nsError = error as NSError
            statusMessage = "Could not send sign-in link (\(nsError.domain):\(nsError.code)): \(error.localizedDescription)"
        }
#else
        state = .unavailable("FirebaseAuth is not linked yet. Add Firebase packages and GoogleService-Info.plist.")
#endif
    }

    func handleIncomingLink(_ url: URL) {
        guard !demoModeEnabled else { return }
#if canImport(FirebaseAuth)
        let link = url.absoluteString
        guard Auth.auth().isSignIn(withEmailLink: link) else {
            statusMessage = "That link is not a valid Firebase sign-in link."
            return
        }

        completeSignIn(withLink: link)
#endif
    }

    func completeSignInFromPastedLink(_ rawLink: String) {
        guard !demoModeEnabled else { return }
#if canImport(FirebaseAuth)
        let trimmed = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)

        if let directURL = URL(string: trimmed), Auth.auth().isSignIn(withEmailLink: directURL.absoluteString) {
            handleIncomingLink(directURL)
            return
        }

        if let extracted = extractFirebaseEmailLink(from: trimmed), let extractedURL = URL(string: extracted) {
            handleIncomingLink(extractedURL)
            return
        }

        guard URL(string: trimmed) != nil else {
            statusMessage = "Paste the full sign-in URL from your email."
            return
        }

        statusMessage = "Could not find a valid Firebase sign-in link in that URL. Try copying the full button link from the email."
#endif
    }

    private func extractFirebaseEmailLink(from raw: String) -> String? {
        // Some mail clients wrap the Firebase link inside query params such as link/deep_link_id/continueUrl.
        let candidates = [raw, raw.removingPercentEncoding ?? raw]

        for candidate in candidates {
            guard let url = URL(string: candidate), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                continue
            }

            if isFirebaseEmailLink(candidate) {
                return candidate
            }

            let keys = ["link", "deep_link_id", "continueUrl", "continue_url", "url"]
            for key in keys {
                if let value = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value {
                    let decoded = value.removingPercentEncoding ?? value
                    if isFirebaseEmailLink(decoded) {
                        return decoded
                    }
                }
            }
        }

        return nil
    }

    private func isFirebaseEmailLink(_ link: String) -> Bool {
#if canImport(FirebaseAuth)
        Auth.auth().isSignIn(withEmailLink: link)
#else
        false
#endif
    }

    private func completeSignIn(withLink link: String) {
#if canImport(FirebaseAuth)

        guard let email = UserDefaults.standard.string(forKey: pendingEmailKey) else {
            statusMessage = "Open the login link on the same device after requesting it."
            return
        }

        Task {
            do {
                let result = try await Auth.auth().signIn(withEmail: email, link: link)
                UserDefaults.standard.removeObject(forKey: pendingEmailKey)
                await createUserProfileIfNeeded(uid: result.user.uid, email: result.user.email ?? email)
                statusMessage = "Signed in successfully."
            } catch {
                let nsError = error as NSError
                statusMessage = friendlyAuthMessage(for: nsError)
            }
        }
#endif
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: demoSessionEmailKey)
        UserDefaults.standard.removeObject(forKey: pendingEmailKey)
        emailInput = ""
        statusMessage = nil

#if canImport(FirebaseAuth)
        if !demoModeEnabled {
            do {
                try Auth.auth().signOut()
            } catch {
                statusMessage = "Sign out failed: \(error.localizedDescription)"
            }
        }
#endif

        state = .signedOut
    }

    private func friendlyAuthMessage(for error: NSError) -> String {
#if canImport(FirebaseAuth)
        if error.domain == AuthErrorDomain {
            switch error.code {
            case AuthErrorCode.invalidActionCode.rawValue: // 17030
                return "This sign-in link is expired or already used. Request a new link and open the newest email."
            case AuthErrorCode.invalidEmail.rawValue:
                return "The saved login email looks invalid. Enter your VT email and request a new sign-in link."
            case AuthErrorCode.userDisabled.rawValue:
                return "This account is disabled. Contact support if you think this is a mistake."
            default:
                break
            }
        }
#endif
        return "Sign-in failed (\(error.domain):\(error.code)): \(error.localizedDescription)"
    }

    // TEMP: non-VT testers whose VT mail filters drop the Firebase sign-in email.
    // Remove before release.
    private let allowedTesterEmails: Set<String> = [
        "ethan.luchsrivera@gmail.com",
    ]

    private func isVTEmail(_ email: String) -> Bool {
        email.hasSuffix("@vt.edu") || email.hasSuffix("@g.vt.edu") || allowedTesterEmails.contains(email)
    }

    private func signInLocally(with email: String) {
        let uid = "local-\(abs(email.hashValue))"
        UserDefaults.standard.set(email, forKey: demoSessionEmailKey)
        state = .signedIn(UserSession(uid: uid, email: email))
        statusMessage = "Signed in as \(email)."

#if canImport(FirebaseFirestore)
        Task {
            await createUserProfileIfNeeded(uid: uid, email: email)
        }
#endif
    }

    private func configureFirebaseIfPossible() {
#if canImport(FirebaseCore)
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
#endif
    }

    private func observeAuthState() {
        if demoModeEnabled {
            if let savedEmail = UserDefaults.standard.string(forKey: demoSessionEmailKey), isVTEmail(savedEmail) {
                signInLocally(with: savedEmail)
            } else {
                state = .signedOut
            }
            return
        }

#if canImport(FirebaseAuth)
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if let user, let email = user.email {
                    self.state = .signedIn(UserSession(uid: user.uid, email: email))
                    await self.createUserProfileIfNeeded(uid: user.uid, email: email)
                } else {
                    self.state = .signedOut
                }
            }
        }
#else
        state = .unavailable("FirebaseAuth is not linked yet. Add Firebase packages and GoogleService-Info.plist.")
#endif
    }

    private func createUserProfileIfNeeded(uid: String, email: String) async {
#if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let ref = db.collection("users").document(uid)
        do {
            let snapshot = try await ref.getDocument()
            if !snapshot.exists {
                try await ref.setData([
                    "email": email,
                    "displayName": email.components(separatedBy: "@").first ?? "Hokie",
                    "isVTStudent": true,
                    "createdAt": Timestamp(date: Date()),
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
            } else {
                try await ref.setData(["updatedAt": Timestamp(date: Date())], merge: true)
            }
        } catch {
            statusMessage = "Profile sync failed: \(error.localizedDescription)"
        }
#endif
    }
}
