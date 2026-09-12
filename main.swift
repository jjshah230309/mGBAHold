//  mGBAHold — holds keys inside mGBA only, in the background.
//  Events are delivered with CGEvent.postToPid() so they land in mGBA's
//  event queue and nowhere else: your other apps never see them.

import AppKit
import Carbon.HIToolbox

// ─────────────────────────────── Key names ───────────────────────────────

enum KeyMap {
    static let table: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16,
        "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40,
        ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "backspace": 51,
        "delete": 51, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "shift": 56, "control": 59, "ctrl": 59, "option": 58, "alt": 58, "command": 55, "cmd": 55,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "keypad0": 82, "keypad1": 83, "keypad2": 84, "keypad3": 85, "keypad4": 86,
        "keypad5": 87, "keypad6": 88, "keypad7": 89, "keypad8": 91, "keypad9": 92,
        "keypadenter": 76,
    ]

    static func code(_ name: String) -> CGKeyCode? {
        table[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    static func isArrow(_ code: CGKeyCode) -> Bool { (123...126).contains(code) }
}

// ─────────────────────────────── Config ───────────────────────────────

struct Step: Codable {
    var keys: [String]
    var seconds: Double
}

struct Profile: Codable {
    var hold: [String]
    var cycle: [Step]
}

struct Config: Codable {
    var targetBundleID: String
    var activeProfile: String
    var refreshMillis: Int?          // 0 = off. Re-asserts held keys; survives focus loss.
    var profiles: [String: Profile]

    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mgbahold", isDirectory: true)
    static let url = dir.appendingPathComponent("config.json")

    static let fallback = Config(
        targetBundleID: "com.endrift.mgba-qt",
        activeProfile: "tunnel",
        refreshMillis: 500,
        profiles: [
            // Short legs = ping-pong between two tiles, so you can never wall out.
            "tunnel": Profile(
                hold: ["tab"],
                cycle: [Step(keys: ["up"], seconds: 1.0), Step(keys: ["down"], seconds: 1.0)]
            ),
            // Long legs for a long corridor: tune the interval so you stop short of the walls.
            "tunnel-long": Profile(
                hold: ["tab"],
                cycle: [Step(keys: ["up"], seconds: 4.0), Step(keys: ["down"], seconds: 4.0)]
            ),
            "side-to-side": Profile(
                hold: ["tab"],
                cycle: [Step(keys: ["left"], seconds: 1.0), Step(keys: ["right"], seconds: 1.0)]
            ),
            // Mash A (mGBA default binding for A is X) to blow through dialogue.
            "mash-a": Profile(
                hold: ["tab"],
                cycle: [Step(keys: ["x"], seconds: 0.12), Step(keys: [], seconds: 0.12)]
            ),
            // No fast-forward, in case you want to watch.
            "tunnel-normal-speed": Profile(
                hold: [],
                cycle: [Step(keys: ["up"], seconds: 1.0), Step(keys: ["down"], seconds: 1.0)]
            ),
        ]
    )

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            let cfg = fallback
            cfg.save()
            return cfg
        }
        return cfg
    }

    func save() {
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Config.url)
    }

    var profile: Profile? { profiles[activeProfile] }
}

// ─────────────────────────────── Injection ───────────────────────────────

final class Injector {
    private let source = CGEventSource(stateID: .privateState)
    private(set) var held = Set<CGKeyCode>()

    /// Posts straight into mGBA's queue — no other process receives this.
    private func post(_ key: CGKeyCode, keyDown: Bool, pid: pid_t) {
        guard let ev = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { return }
        // Real arrow keys carry these flags; match hardware.
        ev.flags = KeyMap.isArrow(key) ? [.maskNumericPad, .maskSecondaryFn] : []
        // Never flag these as auto-repeat: mGBA drops auto-repeat key events.
        ev.postToPid(pid)
    }

    func press(_ keys: [CGKeyCode], pid: pid_t) {
        for k in keys where !held.contains(k) {
            post(k, keyDown: true, pid: pid)
            held.insert(k)
        }
    }

    func release(_ keys: [CGKeyCode], pid: pid_t) {
        for k in keys where held.contains(k) {
            post(k, keyDown: false, pid: pid)
            held.remove(k)
        }
    }

    /// Re-asserts every key we believe is down. mGBA clears its key state when the
    /// window loses focus, so without this a held key is silently dropped the moment
    /// you click into another app.
    func refresh(pid: pid_t) {
        for k in held { post(k, keyDown: true, pid: pid) }
    }

    /// Panic button: let go of everything, always.
    func releaseAll(pid: pid_t?) {
        guard let pid else { held.removeAll(); return }
        for k in held { post(k, keyDown: false, pid: pid) }
        held.removeAll()
    }
}

// ─────────────────────────────── Engine ───────────────────────────────

final class Engine {
    static let shared = Engine()

    private(set) var running = false
    private let injector = Injector()
    private var stepTimer: Timer?
    private var refreshTimer: Timer?
    private var stepIndex = 0
    private var pid: pid_t?
    var config = Config.load()
    var onStateChange: (() -> Void)?

    private func findTarget() -> pid_t? {
        let apps = NSWorkspace.shared.runningApplications
        if let a = apps.first(where: { $0.bundleIdentifier == config.targetBundleID }) { return a.processIdentifier }
        // Fall back to any app that looks like mGBA (dev builds, renamed bundles).
        if let a = apps.first(where: {
            ($0.bundleIdentifier ?? "").lowercased().contains("mgba")
                || ($0.localizedName ?? "").lowercased().contains("mgba")
        }) { return a.processIdentifier }
        return nil
    }

    @discardableResult
    func start() -> String? {
        guard !running else { return nil }
        guard AXIsProcessTrusted() else { return "needs-accessibility" }
        guard let target = findTarget() else { return "mGBA isn’t running." }
        guard let profile = config.profile, !profile.cycle.isEmpty || !profile.hold.isEmpty else {
            return "Profile “\(config.activeProfile)” is empty."
        }

        pid = target
        running = true
        stepIndex = 0

        injector.press(codes(profile.hold), pid: target)
        enterStep()

        let ms = config.refreshMillis ?? 0
        if ms > 0 {
            let t = Timer(timeInterval: Double(ms) / 1000.0, repeats: true) { [weak self] _ in
                guard let self, let pid = self.pid else { return }
                self.injector.refresh(pid: pid)
            }
            RunLoop.main.add(t, forMode: .common)
            refreshTimer = t
        }
        onStateChange?()
        return nil
    }

    func stop() {
        guard running else { return }
        running = false
        stepTimer?.invalidate(); stepTimer = nil
        refreshTimer?.invalidate(); refreshTimer = nil
        injector.releaseAll(pid: pid)
        pid = nil
        onStateChange?()
    }

    func toggle() -> String? {
        if running { stop(); return nil }
        return start()
    }

    private func codes(_ names: [String]) -> [CGKeyCode] { names.compactMap(KeyMap.code) }

    private func enterStep() {
        guard running, let pid, let profile = config.profile, !profile.cycle.isEmpty else { return }
        let step = profile.cycle[stepIndex % profile.cycle.count]

        // Release last step's keys that aren't part of this step or the permanent hold.
        let keep = Set(codes(step.keys) + codes(profile.hold))
        injector.release(Array(injector.held.filter { !keep.contains($0) }), pid: pid)
        injector.press(codes(step.keys), pid: pid)

        let wait = max(0.02, step.seconds)
        stepTimer?.invalidate()
        let t = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            guard let self, self.running else { return }
            // mGBA gone? Stop rather than fire events at a dead pid.
            if NSRunningApplication(processIdentifier: self.pid ?? -1) == nil {
                self.stop(); return
            }
            self.stepIndex += 1
            self.enterStep()
        }
        RunLoop.main.add(t, forMode: .common)
        stepTimer = t
    }

    func reload() {
        let wasRunning = running
        stop()
        config = Config.load()
        if wasRunning { _ = start() }
        onStateChange?()
    }
}

// ─────────────────────────────── Menu bar ───────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        Engine.shared.onStateChange = { [weak self] in self?.updateIcon() }
        updateIcon()
        installHotKey()

        // Stop cleanly if mGBA quits underneath us.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { _ in
            if Engine.shared.running,
               NSWorkspace.shared.runningApplications.first(where: {
                   $0.bundleIdentifier == Engine.shared.config.targetBundleID
               }) == nil {
                Engine.shared.stop()
            }
        }

        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }

    func applicationWillTerminate(_ note: Notification) { Engine.shared.stop() }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let on = Engine.shared.running
        let name = on ? "gamecontroller.fill" : "gamecontroller"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "mGBAHold")
        image?.isTemplate = true
        button.image = image
        // Never let the item render as an invisible zero-width blank.
        button.title = image == nil ? (on ? "GBA●" : "GBA") : (on ? " ●" : "")
    }

    // Menu is rebuilt only when opened — zero cost while idle.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let e = Engine.shared
        let mgbaUp = NSWorkspace.shared.runningApplications.contains {
            ($0.bundleIdentifier ?? "").lowercased().contains("mgba")
        }

        let status = NSMenuItem(
            title: e.running ? "Running — \(e.config.activeProfile)"
                             : (mgbaUp ? "Idle — mGBA detected" : "Idle — mGBA not running"),
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: e.running ? "Stop" : "Start",
                                action: #selector(toggleRun), keyEquivalent: "g")
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let profHeader = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profHeader.isEnabled = false
        menu.addItem(profHeader)
        for name in e.config.profiles.keys.sorted() {
            let item = NSMenuItem(title: "  \(name)", action: #selector(pickProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = (name == e.config.activeProfile) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let intervalItem = NSMenuItem(title: "Turn interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        let current = e.config.profile?.cycle.first?.seconds ?? 0
        for s in [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0, 8.0] {
            let item = NSMenuItem(title: String(format: "%.1f s", s),
                                  action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            item.state = abs(current - s) < 0.001 ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(withTitle: "Edit config…", action: #selector(editConfig), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Reload config", action: #selector(reloadConfig), keyEquivalent: "r")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit mGBAHold", action: #selector(quit), keyEquivalent: "q")
            .target = self
    }

    @objc private func toggleRun() {
        if let problem = Engine.shared.toggle() { report(problem) }
    }

    @objc private func pickProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let wasRunning = Engine.shared.running
        Engine.shared.stop()
        Engine.shared.config.activeProfile = name
        Engine.shared.config.save()
        if wasRunning, let problem = Engine.shared.start() { report(problem) }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        var cfg = Engine.shared.config
        guard var profile = cfg.profile else { return }
        profile.cycle = profile.cycle.map { Step(keys: $0.keys, seconds: seconds) }
        cfg.profiles[cfg.activeProfile] = profile
        cfg.save()
        Engine.shared.reload()
    }

    @objc private func editConfig() {
        _ = Config.load()  // make sure the file exists before opening it
        NSWorkspace.shared.open(Config.url)
    }

    @objc private func reloadConfig() { Engine.shared.reload() }

    @objc private func quit() { Engine.shared.stop(); NSApp.terminate(nil) }

    private func report(_ problem: String) {
        let alert = NSAlert()
        if problem == "needs-accessibility" {
            alert.messageText = "mGBAHold needs Accessibility access"
            alert.informativeText = "System Settings → Privacy & Security → Accessibility → enable mGBAHold, then try again."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        alert.messageText = problem
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // ⌃⌥⌘G works from any app, so you can panic-stop without switching.
    private func installHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                if let problem = Engine.shared.toggle(),
                   let delegate = NSApp.delegate as? AppDelegate {
                    delegate.report(problem)
                }
            }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x4D474248), id: 1)  // 'MGBH'
        RegisterEventHotKey(UInt32(kVK_ANSI_G),
                            UInt32(controlKey | optionKey | cmdKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
