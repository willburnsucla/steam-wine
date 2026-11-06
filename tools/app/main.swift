// OpenRunner: a Mac app that starts Windows Steam on this project's Wine (scripts/steam.sh) and
// stops Steam and everything it started when you quit. The project folder is read from
// Contents/Resources/root.txt, written by scripts/build-app.sh.
//
// The app stays open as long as anything runs in Steam's Wine, not just the steam.exe it
// started: Steam restarts itself as a new process after every update, and Wine starts each
// Windows process detached from its parent, so the first process ending doesn't mean Steam
// has. `steam.sh --wait` blocks until Wine's server for Steam's prefix exits.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let root: String
    private var log: FileHandle?
    private var launch: Process?   // steam.sh, which becomes the first steam.exe
    private var waiter: Process?   // steam.sh --wait, once that steam.exe has exited
    private var launchedAt = Date()
    private var quitting = false

    init(root: String) { self.root = root }

    private var logPath: String { "\(root)/logs/openrunner.log" }

    // Append-only log, so every process writing to it (steam.sh, Wine, --stop) adds instead of
    // overwriting. Started over once it passes 5 MB.
    private func openLog() {
        let dir = "\(root)/logs"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: false)
        if let size = (try? FileManager.default.attributesOfItem(atPath: logPath))?[.size] as? Int,
           size > 5_000_000 {
            try? FileManager.default.removeItem(atPath: logPath)
        }
        let fd = open(logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }
        log = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try? log?.write(contentsOf: "\n=== OpenRunner started \(Date()) ===\n".data(using: .utf8)!)
    }

    private func note(_ text: String) {
        // try?: a log that can't be written (a full disk) must not take the app down with it.
        try? log?.write(contentsOf: "OpenRunner: \(text)\n".data(using: .utf8)!)
    }

    private func runScript(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["\(root)/scripts/steam.sh"] + args
        // Finder gives apps a bare PATH; steam.sh needs Homebrew's tools only to rebuild its wrapper.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        if let log = log {
            p.standardOutput = log
            p.standardError = log
        }
        return p
    }

    private func runAndWait(_ args: [String]) {
        let p = runScript(args)
        guard (try? p.run()) != nil else { return }
        p.waitUntilExit()
    }

    // Quit on a fresh pass of the run loop, never from inside a DispatchQueue.main block: Quit
    // waits for applicationShouldTerminate's reply, which arrives as a main-queue block, and the
    // main queue doesn't run another block until the current one returns.
    private func quitSoon() {
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        guard !root.isEmpty, FileManager.default.fileExists(atPath: "\(root)/scripts/steam.sh") else {
            alert("OpenRunner can't find its project folder",
                  "It was built for \(root.isEmpty ? "an unknown folder" : root), which no longer has "
                  + "scripts/steam.sh. If you moved the project, run scripts/build-all.sh and then "
                  + "scripts/build-app.sh --install from its new location.")
            NSApp.terminate(nil)
            return
        }
        openLog()
        let p = runScript([])
        p.terminationHandler = { proc in
            DispatchQueue.main.async { self.launchEnded(status: proc.terminationStatus) }
        }
        do {
            try p.run()
            launch = p
            launchedAt = Date()
        } catch {
            alert("OpenRunner couldn't start Steam", "\(root)/scripts/steam.sh: \(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    // The first steam.exe has exited. Steam may still be running (it restarted itself, or the app
    // was opened while Steam was already up), so stay open until Wine has nothing left running.
    private func launchEnded(status: Int32) {
        note("steam.sh exited with status \(status); waiting for everything in Wine to exit")
        guard !quitting else { return }
        let w = runScript(["--wait"])
        let failedEarly = status != 0 && Date().timeIntervalSince(launchedAt) < 30
        let waitStarted = Date()
        w.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.note("nothing left running in Wine")
                guard !self.quitting else { return }
                // Nothing was left running and steam.sh itself failed: say why we're closing.
                if failedEarly && Date().timeIntervalSince(waitStarted) < 2 {
                    self.alert("Steam didn't start",
                               "scripts/steam.sh exited with status \(status). The details are in "
                               + "\(self.logPath).")
                }
                self.quitSoon()
            }
        }
        if (try? w.run()) != nil {
            waiter = w
        } else {
            quitSoon()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        note("quitting")
        quitting = true
        guard let launch = launch else { return .terminateNow }
        // Ask Steam to exit on its own (so Steam Cloud syncs), then stop everything Wine still runs.
        // steam.sh may not have started Wine yet when Quit comes right after opening, so keep
        // stopping until steam.sh has exited. Then wait for Wine's server to go, stopping again if
        // something (a Steam that was restarting itself) brought it back. Give up after 30 s.
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(30)
            self.runAndWait(["--quit"])
            while launch.isRunning && Date() < deadline {
                self.runAndWait(["--stop"])
                usleep(500_000)
            }
            if launch.isRunning {
                kill(launch.processIdentifier, SIGKILL)
                self.runAndWait(["--stop"])
            }
            while Date() < deadline {
                let w = self.runScript(["--wait"])
                guard (try? w.run()) != nil else { break }
                let until = Date().addingTimeInterval(3)
                while w.isRunning && Date() < until { usleep(100_000) }
                if !w.isRunning { break }
                w.terminate()
                self.runAndWait(["--stop"])
            }
            self.note("stopped")
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    // Clicking the Dock icon brings Steam's window forward: a second steam.exe hands over to the
    // running one and exits. Launch mode, so a Steam that isn't running starts with its fixes.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !quitting { try? runScript([]).run() }
        return false
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
