import SwiftUI
import SwiftData

@main
struct HomeLibraryApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: Book.self)
    }
}
