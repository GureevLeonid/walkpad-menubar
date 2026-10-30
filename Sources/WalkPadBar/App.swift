import ServiceManagement
import SwiftUI
import WalkPadCore

@main
struct WalkPadBarApp: App {
    // Plain global instead of @State: the CLT toolchain lacks the SwiftUI macro plugin.
    private let pad = sharedPad

    var body: some Scene {
        MenuBarExtra {
            StatsPanel(pad: pad)
        } label: {
            MenuBarLabel(pad: pad)
        }
        .menuBarExtraStyle(.window)
    }
}

private let sharedPad = WalkPad()

@Observable
final class LoginItem {
    var enabled = SMAppService.mainApp.status == .enabled {
        didSet {
            guard enabled != oldValue else { return }
            do { try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
            catch { enabled = SMAppService.mainApp.status == .enabled }
        }
    }
}

private let loginItem = LoginItem()

// MARK: - Formatting

enum Fmt {
    static func speed(_ v: Double?) -> String { v.map { String(format: "%.1f km/h", $0) } ?? "—" }
    static func km(_ m: Int?) -> String { m.map { String(format: "%.2f km", Double($0) / 1000) } ?? "—" }
    static func incline(_ v: Double?) -> String { v.map { String(format: "%g%%", $0) } ?? "—" }
    static func steps(_ v: Int?) -> String { v.map { $0.formatted(.number) } ?? "—" }
    static func kcal(_ v: Int?) -> String { v.map { "\($0) kcal" } ?? "—" }
    static func time(_ s: Int?) -> String {
        guard let s else { return "—" }
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Menu bar label

/// Which stats appear next to the icon while walking.
enum BarField: String, CaseIterable, Identifiable {
    case speed, steps, distance, incline, time
    var id: String { rawValue }
    var title: String {
        switch self {
        case .speed: "Speed"
        case .steps: "Steps"
        case .distance: "Distance"
        case .incline: "Incline"
        case .time: "Time"
        }
    }
    var defaultOn: Bool { self == .speed || self == .steps || self == .distance }
    var key: String { "bar.\(rawValue)" }

    func text(_ s: TreadmillSample) -> String {
        switch self {
        case .speed: Fmt.speed(s.speedKmh)
        case .steps: Fmt.steps(s.steps)
        case .distance: Fmt.km(s.distanceMeters)
        case .incline: Fmt.incline(s.inclinePercent)
        case .time: Fmt.time(s.elapsedSeconds)
        }
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? defaultOn }
}

struct MenuBarLabel: View {
    let pad: WalkPad
    @AppStorage("bar.whenIdle") private var showWhenIdle = false
    // Read so the label re-renders when field toggles change.
    @AppStorage("bar.speed") private var a = true
    @AppStorage("bar.steps") private var b = true
    @AppStorage("bar.distance") private var c = true
    @AppStorage("bar.incline") private var d = false
    @AppStorage("bar.time") private var e = false

    var body: some View {
        // No TimelineView here: inside a MenuBarExtra label it spins the main thread.
        let running = pad.isRunning
        let showText = running || (showWhenIdle && pad.link == .connected)
        let text = BarField.allCases.filter(\.enabled).map { $0.text(pad.stats) }.joined(separator: " · ")
        HStack(spacing: 4) {
            Image(systemName: symbol(running: running))
            if showText && !text.isEmpty { Text(text).monospacedDigit() }
        }
    }

    private func symbol(running: Bool) -> String {
        if running { return "figure.walk.motion" }
        return pad.link == .connected ? "figure.walk" : "figure.stand"
    }
}

// MARK: - Panel

struct StatsPanel: View {
    let pad: WalkPad
    @AppStorage("bar.whenIdle") private var showWhenIdle = false
    @Bindable private var login = loginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow { stat("Speed", Fmt.speed(pad.stats.speedKmh)); stat("Incline", Fmt.incline(pad.stats.inclinePercent)) }
                GridRow { stat("Distance", Fmt.km(pad.stats.distanceMeters)); stat("Steps", Fmt.steps(pad.stats.steps)) }
                GridRow { stat("Time", Fmt.time(pad.stats.elapsedSeconds)); stat("Energy", Fmt.kcal(pad.stats.kcal)) }
            }
            Divider()
            controls
            Divider()
            Text("Show in menu bar").font(.caption).foregroundStyle(.secondary)
            ForEach(BarField.allCases) { f in FieldToggle(field: f) }
            Toggle("Show stats when not walking", isOn: $showWhenIdle)
            Divider()
            Toggle("Launch at login", isOn: $login.enabled)
            HStack {
                Button("Reconnect") { pad.reconnect() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .frame(width: 280)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { pad.startBelt() } label: { Label("Start", systemImage: "play.fill") }
                Button { pad.pauseBelt() } label: { Label("Pause", systemImage: "pause.fill") }
                Button { pad.stopBelt() } label: { Label("Stop", systemImage: "stop.fill") }
            }
            HStack {
                Stepper("Speed") {
                    pad.changeSpeed(by: pad.speedRange.step)
                } onDecrement: {
                    pad.changeSpeed(by: -pad.speedRange.step)
                }
                Spacer()
                Stepper("Incline") {
                    pad.changeIncline(by: pad.inclineRange.step)
                } onDecrement: {
                    pad.changeIncline(by: -pad.inclineRange.step)
                }
            }
            if let err = pad.commandError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .disabled(!pad.canControl)
    }

    private var header: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(pad.name ?? "Walking pad").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch pad.link {
        case .bluetoothUnavailable(let why): why
        case .searching: "Searching…"
        case .connecting: "Off · waiting for pad"
        case .connected: pad.isRunning ? "Walking" : pad.isPaused ? "Paused" : "On · stopped"
        }
    }

    private var statusColor: Color {
        if pad.isRunning { return .green }
        return pad.link == .connected ? .yellow : .gray
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
        }
    }
}

private struct FieldToggle: View {
    let field: BarField
    @AppStorage private var on: Bool

    init(field: BarField) {
        self.field = field
        _on = AppStorage(wrappedValue: field.defaultOn, field.key)
    }

    var body: some View { Toggle(field.title, isOn: $on) }
}
