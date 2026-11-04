import AppKit

/// The macOS system alert sounds (Tink, Pop, Glass, …).
enum Sounds {
    static let available: [String] = {
        let dirs = ["/System/Library/Sounds", "/Library/Sounds",
                    (NSHomeDirectory() as NSString).appendingPathComponent("Library/Sounds")]
        var names = Set<String>()
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            let exts = [".aiff", ".aif", ".wav", ".caf", ".mp3", ".m4a"]
            for f in files where exts.contains(where: { f.lowercased().hasSuffix($0) }) {
                names.insert((f as NSString).deletingPathExtension)
            }
        }
        if names.isEmpty {
            names = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                     "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
        }
        return names.sorted()
    }()

    static func play(_ name: String, volume: Double) {
        guard !name.isEmpty, let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = Float(max(0, min(1, volume)))
        sound.play()
    }
}
