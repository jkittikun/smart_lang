import Foundation

/// A version number such as `1.2.3` (a leading `v`, as in git tags, is allowed).
/// Missing parts count as 0, so `1.2` equals `1.2.0`.
public struct AppVersion: Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        // Ignore a pre-release / build suffix such as "-beta.1" or "+5".
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) { s = String(s[..<cut]) }
        let pieces = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 4 else { return nil }
        var parts: [Int] = []
        for p in pieces {
            guard !p.isEmpty, p.allSatisfy(\.isASCII), let n = Int(p), n >= 0 else { return nil }
            parts.append(n)
        }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func padded(_ n: Int) -> [Int] { parts + Array(repeating: 0, count: max(0, n - parts.count)) }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(n).lexicographicallyPrecedes(b.padded(n))
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(n) == b.padded(n)
    }
}

/// The parts of a GitHub release (`GET /repos/{owner}/{repo}/releases/latest`) the updater uses.
public struct ReleaseInfo: Decodable {
    public struct Asset: Decodable {
        public let name: String
        public let browserDownloadURL: URL
        public let size: Int

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }

        public init(name: String, browserDownloadURL: URL, size: Int) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
            self.size = size
        }
    }

    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    public init(tagName: String, name: String?, body: String?, htmlURL: URL,
                draft: Bool = false, prerelease: Bool = false, assets: [Asset]) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    public static func decode(_ data: Data) throws -> ReleaseInfo {
        try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    public var version: AppVersion? { AppVersion(tagName) }

    /// `SmartLang-X.Y.Z.zip`, as published by the Release workflow.
    public var zipAsset: Asset? {
        guard let v = version else { return nil }
        let wanted = "SmartLang-\(v).zip"
        return assets.first { $0.name == wanted }
            ?? assets.first { $0.name.hasPrefix("SmartLang") && $0.name.hasSuffix(".zip") }
    }

    /// The `.sha256` file published next to the zip.
    public var zipChecksumAsset: Asset? {
        guard let zip = zipAsset else { return nil }
        return assets.first { $0.name == zip.name + ".sha256" }
    }

    /// True if this release is newer than `current` and can be installed by the updater.
    public func isUpdate(over current: AppVersion) -> Bool {
        guard !draft, !prerelease, let v = version, zipAsset != nil, zipChecksumAsset != nil else { return false }
        return v > current
    }
}

public enum UpdateChecksum {
    /// The first 64-character hex digest in a `shasum -a 256` output line, lowercased.
    public static func parse(_ text: String) -> String? {
        for token in text.split(whereSeparator: { $0.isWhitespace || $0 == "*" }) {
            let t = token.lowercased()
            if t.count == 64, t.allSatisfy({ $0.isHexDigit }) { return t }
        }
        return nil
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public enum ReleaseNotes {
    /// Release notes as plain text for an alert: drops Markdown markup and
    /// the install instructions, and keeps it short.
    public static func plainText(_ markdown: String, limit: Int = 900) -> String {
        var lines: [String] = []
        for raw in markdown.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if title.lowercased().hasPrefix("install") { break } // install steps aren't needed here
                if title.lowercased().hasPrefix("smartlang") { continue } // duplicate of the alert title
                line = title
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
            } else if !line.isEmpty, let last = lines.last, last.hasPrefix("• ") {
                // A wrapped bullet continues on the next line.
                lines[lines.count - 1] = last + " " + line
                continue
            }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            if line.isEmpty && (lines.last?.isEmpty ?? true) { continue }
            lines.append(line)
        }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > limit { text = String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" }
        return text
    }
}
