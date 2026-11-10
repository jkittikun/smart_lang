import AppKit
import CryptoKit
import Security
import SmartLangCore
import UserNotifications

/// Checks GitHub Releases for a newer SmartLang, and downloads, verifies and
/// installs it in place, then relaunches.
///
/// The download is checked three ways before anything is replaced:
/// 1. its SHA-256 must match the `.sha256` file published with the release;
/// 2. the unzipped app must have SmartLang's bundle ID and the release's version;
/// 3. if this copy of SmartLang is signed with a certificate, the new app must
///    be signed with the same one (it must satisfy our designated requirement).
///
/// A file the app downloads itself is not quarantined, so the new version opens
/// without Gatekeeper's "could not verify" warning (no `xattr` needed).
/// Releases are signed ad hoc, so macOS sees each version as a new app and the
/// Accessibility and Input Monitoring permissions must be given again after updating.
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    static let repo = "jkittikun/smart_lang"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// The newer release, once one has been found.
    @Published private(set) var available: ReleaseInfo?
    @Published private(set) var lastChecked: Date?

    private let settings = AppSettings.shared
    private var timer: Timer?
    private var checkedThisLaunch = false
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 10 * 60
        config.httpAdditionalHeaders = ["User-Agent": "SmartLang/\(Updater.currentVersionString)"]
        return URLSession(configuration: config)
    }()

    static var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    static var currentVersion: AppVersion { AppVersion(currentVersionString) ?? AppVersion("0.0.0")! }

    /// True when running as SmartLang.app (not via `swift run`), so it can replace itself.
    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    override private init() {
        lastChecked = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
        super.init()
    }

    // MARK: Scheduling

    /// Checks shortly after launch, then about once a day while SmartLang runs.
    func start() {
        if Updater.isAppBundle {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            let install = UNNotificationAction(identifier: "install", title: "Install Update", options: [])
            let category = UNNotificationCategory(identifier: "update", actions: [install],
                                                  intentIdentifiers: [], options: [])
            center.setNotificationCategories([category])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        guard settings.autoCheckForUpdates else { return }
        let due = lastChecked.map { Date().timeIntervalSince($0) >= Updater.checkInterval } ?? true
        // Also check once per launch, so a known update shows up again after a restart.
        guard due || !checkedThisLaunch else { return }
        checkedThisLaunch = true
        check(userInitiated: false)
    }

    // MARK: Checking

    /// Asks GitHub for the latest release. `userInitiated` checks report
    /// "up to date" and errors, and ignore a skipped version.
    func check(userInitiated: Bool) {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        var request = URLRequest(url: Updater.latestAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleCheck(data: data, response: response, error: error, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handleCheck(data: Data?, response: URLResponse?, error: Error?, userInitiated: Bool) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, status == 200, let data, let release = try? ReleaseInfo.decode(data) else {
            let message: String
            if let error { message = error.localizedDescription }
            else if status == 404 { message = "No release has been published yet." }
            else if status == 403 || status == 429 { message = "GitHub is limiting requests. Try again later." }
            else { message = "Couldn't read the release information (HTTP \(status))." }
            state = .failed(message)
            if userInitiated { showError("Couldn't check for updates", message) }
            return
        }

        lastChecked = Date()
        UserDefaults.standard.set(lastChecked, forKey: "lastUpdateCheck")

        guard release.isUpdate(over: Updater.currentVersion), let version = release.version else {
            available = nil
            state = .upToDate
            if userInitiated { showUpToDate() }
            return
        }

        if !userInitiated && settings.skippedUpdateVersion == version.description {
            // Skipped: no badge, no menu item. "Check Now" still offers it.
            available = nil
            state = .idle
            return
        }
        available = release
        state = .available
        if userInitiated {
            showUpdateAlert()
        } else if settings.notifiedUpdateVersion != version.description {
            settings.notifiedUpdateVersion = version.description
            postNotification(for: version)
        }
    }

    // MARK: Alerts and notifications

    /// Banner in Notification Center. (An alert would steal focus while you type.)
    private func postNotification(for version: AppVersion) {
        guard Updater.isAppBundle else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return } // the menu still shows the update
            let content = UNMutableNotificationContent()
            content.title = "SmartLang \(version) is available"
            content.body = "You have \(Updater.currentVersionString). Click to see what's new and update."
            content.categoryIdentifier = "update"
            let request = UNNotificationRequest(identifier: "smartlang-update", content: content, trigger: nil)
            center.add(request)
        }
    }

    /// "SmartLang X is available" with the release notes and Install / Later / Skip.
    func showUpdateAlert() {
        guard let release = available, let version = release.version else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SmartLang \(version) is available"
        var info = "You have version \(Updater.currentVersionString)."
        if let notes = release.body.map({ ReleaseNotes.plainText($0) }), !notes.isEmpty {
            info += "\n\n" + notes
        }
        if !Updater.isAppBundle {
            info += "\n\nRunning from a development build, so it can't update itself."
        } else if signingKind(of: Bundle.main.bundleURL) == .adHoc {
            info += "\n\nAfter updating, give SmartLang its permissions again: in System Settings → Privacy & Security → Accessibility and Input Monitoring, select SmartLang, click − to remove it, then allow it again when SmartLang asks."
        }
        alert.informativeText = info
        alert.addButton(withTitle: Updater.isAppBundle ? "Install and Relaunch" : "Open Releases Page")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if Updater.isAppBundle { install() } else { NSWorkspace.shared.open(release.htmlURL) }
        case .alertThirdButtonReturn:
            settings.skippedUpdateVersion = version.description
            available = nil
            state = .idle
        default:
            break
        }
    }

    private func showUpToDate() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SmartLang is up to date"
        alert.informativeText = "Version \(Updater.currentVersionString) is the latest version."
        alert.runModal()
    }

    private func showError(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Releases Page")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(available?.htmlURL ?? Updater.releasesPage)
        }
    }

    // MARK: Installing

    struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Downloads, verifies and installs the available update, then relaunches.
    func install() {
        guard let release = available, let zip = release.zipAsset, let sum = release.zipChecksumAsset,
              let version = release.version else { return }
        switch state {
        case .downloading, .installing: return
        default: break
        }
        let appURL = Bundle.main.bundleURL
        if let problem = installLocationProblem(appURL) {
            fail(problem)
            return
        }
        state = .downloading

        session.dataTask(with: sum.browserDownloadURL) { [weak self] sumData, _, sumError in
            guard let self else { return }
            guard sumError == nil, let sumData, let text = String(data: sumData, encoding: .utf8),
                  let expected = UpdateChecksum.parse(text) else {
                self.failOnMain("Couldn't download the checksum: \(sumError?.localizedDescription ?? "invalid file").")
                return
            }
            self.session.downloadTask(with: zip.browserDownloadURL) { tmpURL, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil, status == 200, let tmpURL else {
                    self.failOnMain("Couldn't download the update: \(error?.localizedDescription ?? "HTTP \(status)").")
                    return
                }
                do {
                    // The temporary file is deleted when this handler returns, so
                    // move it next to the installed app (same volume) first.
                    let staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                              appropriateFor: appURL, create: true)
                    let zipURL = staging.appendingPathComponent(zip.name)
                    try FileManager.default.moveItem(at: tmpURL, to: zipURL)
                    DispatchQueue.main.async { self.state = .installing }
                    let newApp = try self.prepare(zipURL: zipURL, expectedSHA256: expected,
                                                  version: version, staging: staging)
                    DispatchQueue.main.async { self.replaceAndRelaunch(appURL: appURL, newApp: newApp, staging: staging) }
                } catch {
                    self.failOnMain(error.localizedDescription)
                }
            }.resume()
        }.resume()
    }

    /// Verifies the zip, unpacks it and checks the app inside. Runs off the main thread.
    private func prepare(zipURL: URL, expectedSHA256: String, version: AppVersion, staging: URL) throws -> URL {
        guard let handle = try? FileHandle(forReadingFrom: zipURL) else { throw UpdateError("Couldn't open the download.") }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let actual = UpdateChecksum.hex(Array(hasher.finalize()))
        guard actual == expectedSHA256 else {
            throw UpdateError("The download is damaged (its checksum doesn't match). Nothing was changed.")
        }

        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpacked.path])
        let newApp = unpacked.appendingPathComponent("SmartLang.app", isDirectory: true)
        guard let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError("The download doesn't contain SmartLang.app.")
        }
        let newVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
        guard newVersion == version else {
            throw UpdateError("The downloaded app has the wrong version (\(newVersion?.description ?? "none")).")
        }
        try checkSignature(of: newApp)
        // Belt and braces: files we download aren't quarantined, but make sure.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        return newApp
    }

    enum SigningKind { case unsigned, adHoc, certificate }

    func signingKind(of url: URL) -> SigningKind {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return .unsigned }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return .unsigned }
        if let flags = dict[kSecCodeInfoFlags as String] as? UInt32,
           flags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return .adHoc }
        if let certs = dict[kSecCodeInfoCertificates as String] as? [Any], !certs.isEmpty { return .certificate }
        return dict[kSecCodeInfoIdentifier as String] == nil ? .unsigned : .adHoc
    }

    /// The new app's signature must be intact. If we are signed with a
    /// certificate, the new app must be signed with the same certificate.
    private func checkSignature(of newApp: URL) throws {
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            throw UpdateError("Couldn't read the new app's signature.")
        }
        let strict = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(newCode, strict, nil) == errSecSuccess else {
            throw UpdateError("The new app's code signature is invalid. Nothing was changed.")
        }

        guard signingKind(of: Bundle.main.bundleURL) == .certificate else { return } // ad-hoc: nothing to compare
        var ourCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &ourCode) == errSecSuccess, let ourCode,
              SecCodeCopyDesignatedRequirement(ourCode, [], &requirement) == errSecSuccess, let requirement else {
            throw UpdateError("Couldn't read this app's own signature.")
        }
        guard SecStaticCodeCheckValidity(newCode, strict, requirement) == errSecSuccess else {
            throw UpdateError("The new version is signed with a different certificate, so it was not installed. "
                              + "You can download it from the Releases page instead.")
        }
    }

    /// Swaps the new app into place and starts it once this process has quit.
    private func replaceAndRelaunch(appURL: URL, newApp: URL, staging: URL) {
        let fm = FileManager.default
        let old = staging.appendingPathComponent("previous.app", isDirectory: true)
        do {
            try fm.moveItem(at: appURL, to: old)
        } catch {
            fail("Couldn't replace \(appURL.path): \(error.localizedDescription)\n\n"
                 + "If macOS asked, allow SmartLang under System Settings → Privacy & Security → App Management, then try again.")
            return
        }
        do {
            try fm.moveItem(at: newApp, to: appURL)
        } catch {
            try? fm.moveItem(at: old, to: appURL) // put the old version back
            fail("Couldn't install the new version: \(error.localizedDescription)")
            return
        }
        // Make Finder notice the new version.
        NSWorkspace.shared.noteFileSystemChanged(appURL.path)

        // Wait for this process to exit, open the new version, then clean up.
        let script = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        /usr/bin/open "$2"
        /bin/rm -rf "$3"
        """
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier),
                              appURL.path, staging.path]
        do {
            try relaunch.run()
        } catch {
            fail("SmartLang was updated, but couldn't restart itself. Open it again from Applications.")
            return
        }
        NSApp.terminate(nil)
    }

    private func installLocationProblem(_ appURL: URL) -> String? {
        if !Updater.isAppBundle {
            return "SmartLang is running from a development build, so it can't update itself."
        }
        if appURL.path.contains("/AppTranslocation/") {
            return "macOS is running SmartLang from a temporary location. Move SmartLang.app to the Applications folder, open it from there, and try again."
        }
        let parent = appURL.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: parent.path) {
            return "SmartLang can't write to \(parent.path). Download the new version from the Releases page and install it by hand."
        }
        return nil
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdateError("\((tool as NSString).lastPathComponent) failed (exit \(p.terminationStatus)).")
        }
        return p.terminationStatus
    }

    private func fail(_ message: String) {
        state = available == nil ? .failed(message) : .available
        showError("Couldn't install the update", message)
    }

    private func failOnMain(_ message: String) {
        DispatchQueue.main.async { self.fail(message) }
    }
}

extension Updater: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if action == "install" { self.install() } else { self.showUpdateAlert() }
            completionHandler()
        }
    }
}
