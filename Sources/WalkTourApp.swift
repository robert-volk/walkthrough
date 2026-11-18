import SwiftUI

@main
struct WalkTourApp: App {
    @StateObject private var store = TourStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
