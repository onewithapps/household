import Foundation
import Supabase
import SwiftUI

struct HouseholdRecord: Decodable, Identifiable {
    let id: UUID
    let name: String
}

struct MemberRecord: Decodable, Identifiable {
    let user_id: UUID
    let role: String
    let profiles: ProfileRecord
    var id: UUID { user_id }
}

struct ProfileRecord: Decodable {
    let display_name: String
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var userID: UUID?
    @Published private(set) var email = ""
    @Published private(set) var household: HouseholdRecord?
    @Published private(set) var members: [MemberRecord] = []
    @Published private(set) var starting = true
    @Published private(set) var loadingHousehold = false
    @Published private(set) var householdLoadFailed = false
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var inviteCode: String?
    let client: SupabaseClient?

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let urlString = info["SUPABASE_URL"] as? String ?? ""
        let key = info["SUPABASE_PUBLISHABLE_KEY"] as? String ?? ""
        if let url = URL(string: urlString), url.scheme == "https", url.host != nil,
           !urlString.contains("YOUR_PROJECT"), !key.isEmpty,
           !key.contains("$("), !key.contains("YOUR_PUBLISHABLE_KEY") {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key,
                options: .init(auth: .init(emitLocalSessionAsInitialSession: true)))
        } else {
            client = nil
            starting = false
        }
    }

    func observeAuthentication() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            let nextID = session?.user.id
            let changed = nextID != userID
            userID = nextID
            email = session?.user.email ?? ""
            if changed || nextID == nil {
                household = nil
                members = []
                inviteCode = nil
                error = nil
                notice = nil
            }
            if nextID != nil && (changed || starting) {
                await loadHousehold()
            }
            starting = false
        }
    }

    @discardableResult
    func perform(_ operation: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do {
            try await operation()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func sendCode(to email: String) async -> Bool {
        guard let client else { return false }
        return await perform {
            try await client.auth.signInWithOTP(email: email)
            notice = "Check your email for your sign-in code."
        }
    }

    func verify(email: String, code: String) async {
        guard let client else { return }
        await perform {
            _ = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        }
    }

    func loadHousehold() async {
        guard let client, let requestedUser = userID else { return }
        loadingHousehold = true
        householdLoadFailed = false
        defer { loadingHousehold = false }
        do {
            let households: [HouseholdRecord] = try await client.from("households").select().execute().value
            guard userID == requestedUser else { return }
            let selected = households.first
            var loadedMembers: [MemberRecord] = []
            if let selected {
                loadedMembers = try await client.from("household_members")
                    .select("user_id, role, profiles(display_name)")
                    .eq("household_id", value: selected.id.uuidString)
                    .order("created_at").execute().value
            }
            guard userID == requestedUser else { return }
            household = selected
            members = loadedMembers
            error = nil
        } catch {
            guard userID == requestedUser else { return }
            householdLoadFailed = true
            self.error = error.localizedDescription
        }
    }

    func createHousehold(name: String, displayName: String) async {
        guard let client else { return }
        if await perform({
            _ = try await client.rpc("create_household", params: [
                "p_name": name, "p_display_name": displayName
            ]).execute()
        }) { await loadHousehold() }
    }

    func joinHousehold(code: String, displayName: String) async {
        guard let client else { return }
        if await perform({
            _ = try await client.rpc("accept_household_invite", params: [
                "p_token": code, "p_display_name": displayName
            ]).execute()
        }) { await loadHousehold() }
    }

    func invite(email: String) async {
        guard let client, let household else { return }
        inviteCode = nil
        await perform {
            let token: UUID = try await client.rpc("create_household_invite", params: [
                "p_household_id": household.id.uuidString, "p_email": email
            ]).execute().value
            inviteCode = token.uuidString
        }
    }

    func signOut() async {
        guard let client else { return }
        await perform { try await client.auth.signOut(scope: .local) }
    }
}
