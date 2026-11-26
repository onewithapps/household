import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var email = ""
    @State private var sentTo: String?
    @State private var code = ""

    var body: some View {
        Form {
            Section {
                Label("Welcome to Household", systemImage: "house.fill")
                    .font(.title2.bold())
                Text("Your own account, one shared home. Sign in or create an account with an email code.")
            }
            if let sentTo {
                Section("Check your email") {
                    Text("Enter the code sent to \(sentTo).")
                    TextField("Sign-in code", text: $code)
                        .textContentType(.oneTimeCode)
                    Button("Continue") {
                        Task { await account.verify(email: sentTo, code: code.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Send a new code") {
                        Task { _ = await account.sendCode(to: sentTo) }
                    }
                    Button("Use another email") {
                        self.sentTo = nil
                        code = ""
                        account.error = nil
                        account.notice = nil
                    }
                }
            } else {
                Section("Your account") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                    Button("Send sign-in code") {
                        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        Task {
                            if await account.sendCode(to: normalized) { sentTo = normalized }
                        }
                    }.disabled(!email.contains("@"))
                }
            }
            AccountStatusView()
        }
        .formStyle(.grouped)
        .disabled(account.busy)
    }
}

struct HouseholdSetupView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var displayName = ""
    @State private var name = "Our household"
    @State private var inviteCode = ""
    @State private var joining = false

    var body: some View {
        Form {
            Section("Your profile") {
                Text(account.email).foregroundStyle(.secondary)
                TextField("Your name", text: $displayName)
            }
            Section("Your household") {
                Picker("Get started", selection: $joining) {
                    Text("Create a household").tag(false)
                    Text("Join a household").tag(true)
                }
                if joining {
                    TextField("Invitation code", text: $inviteCode)
                        .autocorrectionDisabled()
                    Text("Sign in with the email address your partner invited, then paste their code here.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    TextField("Household name", text: $name)
                }
                Button(joining ? "Join household" : "Create household") {
                    Task {
                        if joining {
                            await account.joinHousehold(code: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines), displayName: cleanName)
                        } else {
                            await account.createHousehold(name: name.trimmingCharacters(in: .whitespacesAndNewlines), displayName: cleanName)
                        }
                    }
                }
                .disabled(cleanName.isEmpty || (joining ? UUID(uuidString: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)) == nil : name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            AccountStatusView()
            Button("Sign out", role: .destructive) { Task { await account.signOut() } }
        }
        .formStyle(.grouped)
        .disabled(account.busy || account.loadingHousehold)
    }

    private var cleanName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct HouseholdSettingsView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var inviteEmail = ""

    var body: some View {
        Form {
            Section("Household members") {
                ForEach(account.members) { member in
                    LabeledContent(member.profiles.display_name, value: member.role.capitalized)
                }
            }
            if account.members.contains(where: { $0.id == account.userID && $0.role != "child" }) {
                Section("Invite your partner") {
                    TextField("Their email address", text: $inviteEmail)
                        .textContentType(.emailAddress).autocorrectionDisabled()
                    Button("Create invitation") {
                        Task { await account.invite(email: inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
                    }.disabled(!inviteEmail.contains("@"))
                    if let code = account.inviteCode {
                        Text("Share this code with your partner. It expires in seven days and works once, only for the invited email address.")
                        Text(code).font(.footnote.monospaced()).textSelection(.enabled)
                        ShareLink(item: code) { Label("Share invitation code", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            Section("Signed in") {
                Text(account.email)
                Button("Sign out on this device", role: .destructive) { Task { await account.signOut() } }
            }
            AccountStatusView()
        }
        .formStyle(.grouped)
        .disabled(account.busy)
        .navigationTitle("Household")
        .task { await account.loadHousehold() }
    }
}

struct AccountStatusView: View {
    @EnvironmentObject private var account: AccountStore
    var body: some View {
        if account.busy { ProgressView("Please wait…") }
        if let error = account.error { Text(error).foregroundStyle(.red).accessibilityLabel("Error: \(error)") }
        if let notice = account.notice { Text(notice).foregroundStyle(.secondary) }
    }
}
