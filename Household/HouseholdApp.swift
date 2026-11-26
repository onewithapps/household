import SwiftUI

@main
struct HouseholdApp: App {
    @StateObject private var account = AccountStore()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(account)
        }
    }
}
