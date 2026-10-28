// OpenRunner: a Mac app that starts Windows Steam on this project's Wine (scripts/steam.sh) and
// stops Steam and everything it started when you quit. The project folder is read from
// Contents/Resources/root.txt, written by scripts/build-app.sh.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let root: String
    private var steam: Process?
    private var quitting = false

    init(root: String) { self.root = root }

    private func runScript(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(root)/scripts/steam.sh"] + args
        // Finder gives apps a bare PATH; steam.sh needs Homebrew's tools only to rebuild its wrapper.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let logURL = URL(fileURLWithPath: "\(root)/logs/openrunner.log")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: logURL) {
            log.seekToEndOfFile()
            p.standardOutput = log
            p.standardError = log
        }
        return p
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let p = runScript([])
        p.terminationHandler = { [weak self] _ in
            // Steam quit on its own (its own Exit menu): close the app too.
            DispatchQueue.main.async {
                if self?.quitting == false { NSApp.terminate(nil) }
            }
        }
        do {
            try p.run()
            steam = p
        } catch {
            let alert = NSAlert()
            alert.messageText = "OpenRunner couldn't start Steam"
            alert.informativeText = "\(root)/scripts/steam.sh: \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true
        guard let steam = steam, steam.isRunning else { return .terminateNow }
        // Stop Steam and everything Wine started, then give it up to 15 s to exit.
        DispatchQueue.global().async {
            let stop = self.runScript(["--stop"])
            try? stop.run()
            stop.waitUntilExit()
            let deadline = Date().addingTimeInterval(15)
            while steam.isRunning && Date() < deadline { usleep(200_000) }
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    private func buildMenu() {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }
}

let rootURL = Bundle.main.url(forResource: "root", withExtension: "txt")
let root = (rootURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
    .trimmingCharacters(in: .whitespacesAndNewlines)
let app = NSApplication.shared
let delegate = AppDelegate(root: root)
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
