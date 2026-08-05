import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: QLabMonitor
    @State private var oscPasscode = ""
    @State private var showingDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            header
            PlaybackSurface(
                samples: monitor.samples,
                activeCue: monitor.cue,
                displayedCue: monitor.displayedCue
            )
            .opacity(monitor.cue == nil ? 0.42 : 1)
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .background(Color(red: 0.18, green: 0.18, blue: 0.18))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(monitor.displayedCue?.name ?? "QLab Waveform")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if shouldOfferOSCConnection {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        SecureField("OSC passcode", text: $oscPasscode, onCommit: connectOSC)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 120)
                        Button(monitor.isOSCConnected ? "Reconnect" : "Connect") { connectOSC() }
                            .disabled(oscPasscode.isEmpty || monitor.oscConnectionState == .connecting)
                    }
                    if let guidance = oscFailureGuidance {
                        Text(guidance)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 360, alignment: .trailing)
                    }
                }
            }
            statusBadge.fixedSize()
            monitoringModeBadge.fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private func connectOSC() {
        monitor.connectOSC(passcode: oscPasscode)
        oscPasscode = ""
    }

    private var shouldOfferOSCConnection: Bool {
        !monitor.isOSCConnected || (monitor.cue != nil && !monitor.isOSCTimingActive)
    }

    private var oscFailureGuidance: String? {
        guard case .failed = monitor.oscConnectionState else { return nil }
        return "No reply from QLab. Check that QLab is running, OSC connections are enabled, and the passcode is correct."
    }

    private var statusBadge: some View {
        HStack(spacing: 7) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    private var monitoringModeBadge: some View {
        Button {
            showingDiagnostics.toggle()
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(monitoringModeColor)
                    .frame(width: 8, height: 8)
                Text(monitoringModeText)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.09)))
        }
        .buttonStyle(PlainButtonStyle())
        .help(monitoringModeHelp)
        .popover(isPresented: $showingDiagnostics, arrowEdge: .top) {
            MonitoringDiagnosticsView(
                isConnected: monitor.isOSCConnected,
                isTimingActive: monitor.isOSCTimingActive,
                connectionState: monitor.oscConnectionState,
                diagnostics: monitor.diagnostics
            )
        }
    }

    private var monitoringModeText: String {
        if monitor.isOSCTimingActive { return "OSC" }
        switch monitor.oscConnectionState {
        case .connecting: return "OSC…"
        case .connected: return "OSC"
        case .failed: return "OSC Failed"
        default: return "AppleScript"
        }
    }

    private var monitoringModeColor: Color {
        switch monitor.oscConnectionState {
        case .failed: return .red
        case .connecting: return .orange
        case .connected: return Color(red: 0, green: 0.75, blue: 0.85)
        case .disconnected: return .secondary
        }
    }

    private var monitoringModeHelp: String {
        if monitor.isOSCTimingActive { return "OSC timing is active" }
        switch monitor.oscConnectionState {
        case .failed(let message): return "OSC connection failed: \(message)"
        case .connecting: return "Authenticating with QLab"
        case .connected: return monitor.cue == nil ? "OSC is connected and waiting for an Audio cue" : "Using AppleScript fallback"
        case .disconnected: return "Using AppleScript fallback"
        }
    }

    private var statusText: String {
        switch monitor.status {
        case .connecting: return "Connecting"
        case .waiting(let message): return message
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .error(let message): return message
        }
    }

    private var statusColor: Color {
        switch monitor.status {
        case .playing: return .green
        case .paused: return .orange
        case .error: return .red
        default: return .secondary
        }
    }
}

private struct MonitoringDiagnosticsView: View {
    let isConnected: Bool
    let isTimingActive: Bool
    let connectionState: OSCConnectionState
    let diagnostics: MonitorDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monitoring diagnostics").font(.headline)
            diagnosticRow("Current mode", isTimingActive ? "OSC timing" : "AppleScript fallback")
            diagnosticRow("OSC connection", connectionDescription)
            Divider()
            diagnosticRow("AppleScript polls", "\(diagnostics.appleScriptPollsLastMinute) / min")
            diagnosticRow("OSC timing replies", "\(diagnostics.oscTimingRepliesLastMinute) / min")
            diagnosticRow("OSC QLab events", "\(diagnostics.oscEventsLastMinute) / min")
            diagnosticRow("Last OSC checkpoint", checkpointAge)
            Text("Counts cover the most recent 60 seconds.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 310)
    }

    private var connectionDescription: String {
        switch connectionState {
        case .disconnected: return "Not connected"
        case .connecting: return "Authenticating…"
        case .connected: return isConnected ? "Authenticated" : "Connected"
        case .failed(let message): return message
        }
    }

    private var checkpointAge: String {
        guard let age = diagnostics.lastOSCCheckpointAge else { return "Never" }
        if age < 1 { return "\(Int(age * 1_000)) ms ago" }
        return String(format: "%.1f s ago", age)
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(.callout, design: .monospaced))
        }
    }
}

private struct PlaybackSurface: NSViewRepresentable {
    let samples: [Float]
    let activeCue: ActiveAudioCue?
    let displayedCue: ActiveAudioCue?

    func makeNSView(context: Context) -> PlaybackSurfaceNSView {
        PlaybackSurfaceNSView()
    }

    func updateNSView(_ view: PlaybackSurfaceNSView, context: Context) {
        view.samples = samples
        view.activeCue = activeCue
        view.displayedCue = displayedCue
        view.needsDisplay = true
    }
}

@MainActor
private final class PlaybackSurfaceNSView: NSView {
    var samples: [Float] = []
    var activeCue: ActiveAudioCue?
    var displayedCue: ActiveAudioCue?
    private var animationTimer: Timer?
    private var countdownCueID: String?
    private var previousCountdownRemaining: Double?
    private var countdownFlashStartedAt: TimeInterval?
    private var countdownFlashThreshold: Double?

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, animationTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(redrawPlayback), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if window == nil {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    @objc private func redrawPlayback() {
        if activeCue != nil { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let waveformRect = NSRect(x: 0, y: 0, width: max(1, bounds.width), height: max(80, bounds.height - 38))
        drawWaveform(in: waveformRect)
        drawTimeline(below: waveformRect)
    }

    private func drawWaveform(in rect: NSRect) {
        let outline = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.stroke()

        guard !samples.isEmpty else {
            drawCenteredText("Start an Audio cue in QLab", in: rect, color: .tertiaryLabelColor)
            return
        }

        let progress = projectedProgress
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        if let progress {
            NSColor.systemGreen.withAlphaComponent(0.28).setFill()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let now = ProcessInfo.processInfo.systemUptime
        if let cue = activeCue {
            let remaining = max(0, cue.duration - cue.projectedElapsed(at: now))
            updateCountdownFlash(cueID: cue.id, remaining: remaining, at: now)
        }
        drawCountdownFlashBackground(in: rect, at: now)

        let middle = rect.midY
        let step = rect.width / CGFloat(max(1, samples.count - 1))
        let path = NSBezierPath()
        path.lineWidth = max(1, step)
        for (index, sample) in samples.enumerated() {
            let x = rect.minX + CGFloat(index) * step
            let halfHeight = max(0.5, CGFloat(sample) * (rect.height / 2 - 8))
            path.move(to: NSPoint(x: x, y: middle - halfHeight))
            path.line(to: NSPoint(x: x, y: middle + halfHeight))
        }
        NSColor(calibratedRed: 0.16, green: 0.58, blue: 1.0, alpha: activeCue == nil ? 0.35 : 0.96).setStroke()
        path.stroke()

        if let progress {
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: rect.minX, y: rect.minY, width: rect.width * progress, height: rect.height).clip()
            NSColor(calibratedRed: 0.38, green: 0.72, blue: 0.88, alpha: 0.84).setStroke()
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        drawMinuteGuides(in: rect)
        drawAutoFollow(in: rect)
        drawPlaybackTimers(in: rect)
    }

    private var projectedProgress: CGFloat? {
        guard let cue = activeCue, cue.duration > 0 else { return nil }
        let elapsed = cue.projectedElapsed(at: ProcessInfo.processInfo.systemUptime)
        return CGFloat(min(1, max(0, elapsed / cue.duration)))
    }

    private func drawMinuteGuides(in rect: NSRect) {
        guard let duration = displayedCue?.duration, duration >= 60 else { return }
        NSColor.white.withAlphaComponent(0.07).setStroke()
        for minute in 1...Int(duration / 60) {
            let time = Double(minute * 60)
            guard duration - time > 0.05 else { continue }
            let x = rect.minX + CGFloat(time / duration) * rect.width
            let line = NSBezierPath()
            line.lineWidth = 1
            line.move(to: NSPoint(x: x, y: rect.minY))
            line.line(to: NSPoint(x: x, y: rect.maxY))
            line.stroke()
        }
    }

    private func drawAutoFollow(in rect: NSRect) {
        guard let cue = displayedCue else { return }
        let text = cue.isAutoFollow ? "AUTO-FOLLOW ON" : "AUTO-FOLLOW OFF"
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let size = text.size(withAttributes: [.font: font])
        let badge = NSRect(x: rect.maxX - size.width - 28, y: rect.minY + 12, width: size.width + 16, height: 24)
        NSColor.windowBackgroundColor.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 12, yRadius: 12).fill()
        drawText(text, at: NSPoint(x: badge.minX + 8, y: badge.minY + 5), font: font, color: cue.isAutoFollow ? .systemOrange : .secondaryLabelColor)
    }

    private func drawPlaybackTimers(in rect: NSRect) {
        guard let cue = activeCue else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = cue.projectedElapsed(at: now)
        let remaining = max(0, cue.duration - elapsed)
        let showFractions = remaining <= 30
        let displayedElapsed = showFractions ? elapsed : floor(elapsed)
        let displayedRemaining = showFractions ? remaining : floor(remaining)
        let fontSize = max(16, rect.height * 0.20)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        let countUp = formatPlaybackTime(displayedElapsed)
        let countDown = "−" + formatPlaybackTime(displayedRemaining)
        let countUpSize = countUp.size(withAttributes: [.font: font])
        let countDownSize = countDown.size(withAttributes: [.font: font])
        let textHeight = max(countUpSize.height, countDownSize.height)
        let y = rect.maxY - textHeight - 12
        drawText(countUp, at: NSPoint(x: rect.minX + 12, y: y), font: font, color: .white)
        drawCountdownText(countDown, at: NSPoint(x: rect.maxX - countDownSize.width - 12, y: y), font: font, at: now)
    }

    private func updateCountdownFlash(cueID: String, remaining: Double, at now: TimeInterval) {
        if countdownCueID != cueID {
            countdownCueID = cueID
            previousCountdownRemaining = remaining
            countdownFlashStartedAt = nil
            countdownFlashThreshold = nil
            return
        }
        if let previousCountdownRemaining,
           let threshold = [30.0, 15.0, 10.0, 5.0, 4.0, 3.0, 2.0, 1.0]
            .first(where: { previousCountdownRemaining > $0 && remaining <= $0 }) {
            countdownFlashStartedAt = now
            countdownFlashThreshold = threshold
        }
        previousCountdownRemaining = remaining
    }

    private func drawCountdownFlashBackground(in rect: NSRect, at now: TimeInterval) {
        guard let strength = countdownFlashStrength(at: now) else { return }
        let flashRect = NSRect(
            x: rect.minX + rect.width * 0.85,
            y: rect.minY,
            width: rect.width * 0.15,
            height: rect.height
        )
        guard let gradient = NSGradient(colors: [
            NSColor.systemOrange.withAlphaComponent(0),
            NSColor.systemOrange.withAlphaComponent(0.28 * strength),
            NSColor.systemOrange.withAlphaComponent(0.58 * strength)
        ]) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).addClip()
        gradient.draw(in: flashRect, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func countdownFlashStrength(at now: TimeInterval) -> CGFloat? {
        guard let started = countdownFlashStartedAt else { return nil }
        let fade = min(1, max(0, (now - started) / 0.75))
        if fade >= 1 {
            countdownFlashStartedAt = nil
            countdownFlashThreshold = nil
            return nil
        }
        return CGFloat(1 - fade)
    }

    private func drawCountdownText(_ text: String, at point: NSPoint, font: NSFont, at now: TimeInterval) {
        drawText(text, at: point, font: font, color: .white)
    }

    private func drawTimeline(below waveform: NSRect) {
        guard let duration = displayedCue?.duration, duration > 0 else {
            drawText("--:--", at: NSPoint(x: waveform.minX, y: waveform.maxY + 18), font: .monospacedDigitSystemFont(ofSize: 14, weight: .regular), color: .secondaryLabelColor)
            return
        }
        var marks: [(Double, String, Bool)] = [(0, "0:00", false)]
        if duration >= 60 {
            for minute in 1...Int(duration / 60) {
                let time = Double(minute * 60)
                if duration - time > 0.05 { marks.append((time, duration - time > 40 ? "\(minute):00" : "", false)) }
            }
        }
        if duration > 30 { marks.append((duration - 30, "−0:30", true)) }
        if duration > 15 { marks.append((duration - 15, "−0:15", true)) }
        if duration > 10 { marks.append((duration - 10, "", true)) }
        if duration > 5 { marks.append((duration - 5, "", true)) }
        marks.append((duration, formatDuration(duration), false))
        marks.sort { $0.0 < $1.0 }

        for (index, mark) in marks.enumerated() {
            let x = waveform.minX + CGFloat(mark.0 / duration) * waveform.width
            let tick = NSBezierPath()
            tick.lineWidth = mark.2 ? 2 : 1
            tick.move(to: NSPoint(x: x, y: waveform.maxY))
            tick.line(to: NSPoint(x: x, y: waveform.maxY + 10))
            (mark.2 ? NSColor.systemOrange : NSColor.secondaryLabelColor).setStroke()
            tick.stroke()
            guard !mark.1.isEmpty else { continue }
            let font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
            let size = mark.1.size(withAttributes: [.font: font])
            let labelX: CGFloat
            if index == 0 { labelX = waveform.minX }
            else if index == marks.count - 1 { labelX = waveform.maxX - size.width }
            else { labelX = x - size.width / 2 }
            drawText(mark.1, at: NSPoint(x: labelX, y: waveform.maxY + 15), font: font, color: mark.2 ? .systemOrange : .secondaryLabelColor)
        }
    }

    private func formatPlaybackTime(_ seconds: Double) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%05.2f", Int(value) / 60, value.truncatingRemainder(dividingBy: 60))
    }

    private func formatDuration(_ seconds: Double) -> String {
        String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        text.draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawCenteredText(_ text: String, in rect: NSRect, color: NSColor) {
        let font = NSFont.systemFont(ofSize: 18)
        let size = text.size(withAttributes: [.font: font])
        drawText(text, at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), font: font, color: color)
    }
}
