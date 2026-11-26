import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var account: AccountStore
    @State private var section: String? = "calendar"

    var body: some View {
        Group {
            if account.client == nil {
                ContentUnavailableView("Connect Household", systemImage: "house.and.flag", description: Text("The backend hasn’t been connected yet. Follow the project’s setup instructions to enable accounts."))
            } else if account.starting || (account.loadingHousehold && account.household == nil) {
                ProgressView("Opening your household…")
            } else if account.userID == nil {
                SignInView()
            } else if account.householdLoadFailed && account.household == nil {
                VStack(spacing: 16) {
                    ContentUnavailableView("Couldn’t load your household", systemImage: "wifi.exclamationmark", description: Text(account.error ?? "Please try again."))
                    Button("Try again") { Task { await account.loadHousehold() } }
                    Button("Sign out") { Task { await account.signOut() } }
                }
            } else if let household = account.household, let userID = account.userID {
                NavigationSplitView {
                    List(selection: $section) {
                        NavigationLink(value: "calendar") { Label("Calendar", systemImage: "calendar") }
                        NavigationLink(value: "household") { Label("Household", systemImage: "person.2") }
                    }
                    .navigationTitle(household.name)
                } detail: {
                    NavigationStack {
                        if section == "household" {
                            HouseholdSettingsView()
                        } else {
                            CalendarScreen(selectionKey: "calendar.\(userID).\(household.id)")
                                .id("\(userID).\(household.id)")
                        }
                    }
                }
            } else {
                HouseholdSetupView()
            }
        }
        .task { await account.observeAuthentication() }
    }
}
