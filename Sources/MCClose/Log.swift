import Foundation

/// Appends lines to ~/Library/Logs/MCClose.log, so problems can be read from evidence.
/// Window titles are not written unless the user opts in:
///   defaults write io.github.anujbajaj4.MCClose VerboseLog -bool YES
enum Log {
    static let url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MCClose.log")
    private static let queue = DispatchQueue(label: "MCClose.log")
    private static let maxBytes = 512 * 1024

    static var verbose: Bool { UserDefaults.standard.bool(forKey: "VerboseLog") }

    /// A title as it may appear in the log: the real text only in verbose mode.
    static func title(_ s: String) -> String {
        verbose ? "\"\(s)\"" : "<\(s.count) chars>"
    }

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                formatOptions: [.withInternetDateTime])
        let line = "\(stamp) \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
                let old = url.deletingPathExtension().appendingPathExtension("old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
