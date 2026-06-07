import Foundation

enum StartupProbe {
    private static let start = CFAbsoluteTimeGetCurrent()

    static func mark(_ label: String) {
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print(String(format: "[Startup] %.3fs %@", elapsed, label))
    }
}
