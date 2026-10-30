import Scrib3Core
import SwiftUI

@main
struct Scrib3App: App {
    var body: some Scene {
        WindowGroup {
            Text(Scrib3.name)
                .frame(minWidth: 640, minHeight: 420)
        }
    }
}
