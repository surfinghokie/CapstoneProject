import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthSessionManager
    @State private var pastedSignInLink = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bicycle.circle.fill")
                .font(.system(size: 68))
                .foregroundColor(Color("VTMaroon"))

            Text("HokieBike")
                .font(.largeTitle.bold())
                .foregroundColor(Color("VTMaroon"))

            Text("Enter your Virginia Tech email to continue")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("you@g.vt.edu", text: $authManager.emailInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button {
                Task {
                    await authManager.sendVTSignInLink()
                }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("VTMaroon"))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            if case .linkSent(let email) = authManager.state {
                Text("Check \(email) for your sign-in link, then reopen it on this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Paste sign-in link here if it opens in browser", text: $pastedSignInLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button {
                    authManager.completeSignInFromPastedLink(pastedSignInLink)
                } label: {
                    Text("Complete Sign-In from Link")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color("VTOrange"))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }

            if case .unavailable(let message) = authManager.state {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let status = authManager.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .navigationTitle("Login")
    }
}

#Preview {
    NavigationStack {
        LoginView()
            .environmentObject(AuthSessionManager())
    }
}
