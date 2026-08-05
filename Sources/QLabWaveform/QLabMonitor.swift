import AppKit
import AVFoundation
import Combine
import Foundation

struct ActiveAudioCue: Equatable {
    let id: String
    let name: String
    let fileURL: URL
    let startTime: Double
    let endTime: Double
    let elapsed: Double
    let isPaused: Bool
    let isAutoFollow: Bool
    let observedAt: TimeInterval

    var duration: Double { max(0, endTime - startTime) }
    var fileTime: Double { min(endTime, max(startTime, startTime + elapsed)) }
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    func projectedElapsed(at uptime: TimeInterval) -> Double {
        let projection = isPaused ? elapsed : elapsed + max(0, uptime - observedAt)
        return min(duration, max(0, projection))
    }
}

enum MonitorStatus: Equatable {
    case connecting
    case waiting(String)
    case playing
    case paused
    case error(String)
}

struct MonitorDiagnostics: Equatable {
    var appleScriptPollsLastMinute = 0
    var oscTimingRepliesLastMinute = 0
    var oscEventsLastMinute = 0
    var lastOSCCheckpointAge: Double?
}

enum OSCConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

@MainActor
final class QLabMonitor: ObservableObject {
    @Published private(set) var cue: ActiveAudioCue?
    @Published private(set) var displayedCue: ActiveAudioCue?
    @Published private(set) var samples: [Float] = []
    @Published private(set) var status: MonitorStatus = .connecting
    @Published private(set) var isOSCConnected = false
    @Published private(set) var isOSCTimingActive = false
    @Published private(set) var diagnostics = MonitorDiagnostics()
    @Published private(set) var oscConnectionState: OSCConnectionState = .disconnected

    private var timer: Timer?
    private lazy var scriptWorker = QLabScriptWorker(source: Self.pollScript)
    private let oscClient = OSCClient()
    private var waveformKey: String?
    private var isPolling = false
    private var lastAppleScriptPoll: TimeInterval = 0
    private var lastOSCUpdate: TimeInterval = 0
    private var appleScriptPollTimes: [TimeInterval] = []
    private var oscTimingReplyTimes: [TimeInterval] = []
    private var oscEventTimes: [TimeInterval] = []
    private var oscConnectionAttempt = 0

    func start() {
        guard timer == nil else { return }
        oscClient.onMessage = { [weak self] message in
            Task { @MainActor [weak self] in self?.handleOSC(message) }
        }
        oscClient.start()
        poll(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func connectOSC(passcode: String) {
        guard !passcode.isEmpty else { return }
        oscConnectionAttempt += 1
        let attempt = oscConnectionAttempt
        oscConnectionState = .connecting
        oscClient.authenticate(passcode: passcode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.oscConnectionAttempt == attempt,
                  self.oscConnectionState == .connecting else { return }
            self.oscConnectionState = .failed("No authentication reply")
        }
    }

    private func poll(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        let oscIsHealthy = now - lastOSCUpdate < 1.0
        if isOSCTimingActive != oscIsHealthy { isOSCTimingActive = oscIsHealthy }
        updateDiagnostics(at: now)
        let oscIsAuthenticatedAndIdle = isOSCConnected && cue == nil
        let interval = (oscIsHealthy || oscIsAuthenticatedAndIdle) ? 1.0 : 0.10
        guard force || now - lastAppleScriptPoll >= interval else { return }
        guard !isPolling else { return }
        lastAppleScriptPoll = now
        appleScriptPollTimes.append(now)
        updateDiagnostics(at: now)
        isPolling = true
        scriptWorker.execute { [weak self] response, errorMessage in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPolling = false
                if let errorMessage {
                    self.status = .error(errorMessage)
                    return
                }
                self.handle(response ?? "")
            }
        }
    }

    private func handle(_ response: String) {
        if response.hasPrefix("WAIT\u{001e}") {
            cue = nil
            oscClient.monitor(cueID: nil)
            status = .waiting(String(response.dropFirst(5)))
            return
        }
        if response.hasPrefix("ERROR\u{001e}") {
            cue = nil
            oscClient.monitor(cueID: nil)
            status = .error(String(response.dropFirst(6)))
            return
        }

        guard let nextCue = Self.parse(response) else {
            cue = nil
            oscClient.monitor(cueID: nil)
            status = .waiting("No running Audio cue")
            return
        }

        cue = nextCue
        displayedCue = nextCue
        oscClient.monitor(cueID: nextCue.id)
        status = nextCue.isPaused ? .paused : .playing

        let key = "\(nextCue.fileURL.path)|\(nextCue.startTime)|\(nextCue.endTime)"
        if key != waveformKey {
            waveformKey = key
            do {
                samples = try WaveformReader.samples(
                    from: nextCue.fileURL,
                    startTime: nextCue.startTime,
                    endTime: nextCue.endTime,
                    binCount: 2_000
                )
            } catch {
                samples = []
                status = .error("Waveform: \(error.localizedDescription)")
            }
        }
    }

    private func handleOSC(_ message: OSCMessage) {
        if message.address.hasPrefix("/qlab/event/workspace/") {
            oscEventTimes.append(ProcessInfo.processInfo.systemUptime)
            poll(force: true)
            return
        }
        if message.address.hasSuffix("/connect") {
            if oscReplySucceeded(message) {
                isOSCConnected = true
                oscConnectionState = .connected
            } else {
                isOSCConnected = false
                oscConnectionState = .failed("Passcode rejected")
            }
        }
        guard let current = cue else { return }
        if message.address.hasSuffix("/actionElapsed"), let elapsed = oscNumber(from: message) {
            lastOSCUpdate = ProcessInfo.processInfo.systemUptime
            oscTimingReplyTimes.append(lastOSCUpdate)
            isOSCConnected = true
            isOSCTimingActive = true
            oscConnectionState = .connected
            updateDiagnostics(at: lastOSCUpdate)
            let updated = replacing(current, elapsed: elapsed, isPaused: current.isPaused)
            cue = updated
            displayedCue = updated
            status = updated.isPaused ? .paused : .playing
        }
    }

    private func updateDiagnostics(at now: TimeInterval) {
        let cutoff = now - 60
        appleScriptPollTimes.removeAll { $0 < cutoff }
        oscTimingReplyTimes.removeAll { $0 < cutoff }
        oscEventTimes.removeAll { $0 < cutoff }
        diagnostics = MonitorDiagnostics(
            appleScriptPollsLastMinute: appleScriptPollTimes.count,
            oscTimingRepliesLastMinute: oscTimingReplyTimes.count,
            oscEventsLastMinute: oscEventTimes.count,
            lastOSCCheckpointAge: lastOSCUpdate > 0 ? max(0, now - lastOSCUpdate) : nil
        )
    }

    private func oscNumber(from message: OSCMessage) -> Double? {
        if let number = message.arguments.first?.number { return number }
        return oscReplyData(from: message) as? Double
            ?? (oscReplyData(from: message) as? NSNumber)?.doubleValue
    }

    private func oscReplyData(from message: OSCMessage) -> Any? {
        guard case .string(let json)? = message.arguments.first,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["status"] as? String == "ok" else { return nil }
        return object["data"]
    }

    private func oscReplySucceeded(_ message: OSCMessage) -> Bool {
        guard case .string(let json)? = message.arguments.first,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["status"] as? String == "ok"
    }

    private func replacing(_ cue: ActiveAudioCue, elapsed: Double, isPaused: Bool) -> ActiveAudioCue {
        ActiveAudioCue(
            id: cue.id,
            name: cue.name,
            fileURL: cue.fileURL,
            startTime: cue.startTime,
            endTime: cue.endTime,
            elapsed: elapsed,
            isPaused: isPaused,
            isAutoFollow: cue.isAutoFollow,
            observedAt: ProcessInfo.processInfo.systemUptime
        )
    }

    private static func parse(_ value: String) -> ActiveAudioCue? {
        let fields = value.components(separatedBy: "\u{001e}")
        guard fields.count == 8,
              let start = Double(fields[3]),
              let end = Double(fields[4]),
              let elapsed = Double(fields[5]) else { return nil }

        return ActiveAudioCue(
            id: fields[0],
            name: fields[1],
            fileURL: URL(fileURLWithPath: fields[2]),
            startTime: start,
            endTime: end,
            elapsed: elapsed,
            isPaused: fields[6] == "true",
            isAutoFollow: fields[7] == "true",
            observedAt: ProcessInfo.processInfo.systemUptime
        )
    }

    private static let pollScript = #"""
    on qlabWaveformPOSIXPath(cueFile)
        return POSIX path of cueFile
    end qlabWaveformPOSIXPath

    set separator to ASCII character 30
    tell application "QLab"
        if (count of workspaces) is 0 then return "WAIT" & separator & "Open a QLab workspace"
        tell front workspace
            repeat with cueReference in (get active cues)
                set activeCue to contents of cueReference
                if (q type of activeCue is "Audio") then
                    try
                        set cueFile to file target of activeCue
                        set cuePath to my qlabWaveformPOSIXPath(cueFile)
                        set cueName to q display name of activeCue
                        set cueID to uniqueID of activeCue
                        set cueStart to start time of activeCue
                        set cueEnd to end time of activeCue
                        set cueElapsed to action elapsed of activeCue
                        set cuePaused to paused of activeCue
                        set cueAutoFollow to (continue mode of activeCue is auto_follow)
                        return cueID & separator & cueName & separator & cuePath & separator & cueStart & separator & cueEnd & separator & cueElapsed & separator & cuePaused & separator & cueAutoFollow
                    on error errorMessage number errorNumber
                        return "ERROR" & separator & errorNumber & ": " & errorMessage
                    end try
                end if
            end repeat
        end tell
    end tell
    return "WAIT" & separator & "No running Audio cue"
    """#
}

/// NSAppleScript is synchronous and not Sendable. This wrapper owns one script
/// on one serial queue, keeping every Apple event round-trip away from the UI.
final class QLabScriptWorker: @unchecked Sendable {
    private let source: String
    private let queue = DispatchQueue(label: "nz.net.duncan.qlab-waveform.applescript", qos: .userInteractive)
    private var script: NSAppleScript?

    init(source: String) {
        self.source = source
    }

    func execute(completion: @escaping @Sendable (String?, String?) -> Void) {
        queue.async { [self] in
            autoreleasepool {
                if script == nil {
                    script = NSAppleScript(source: source)
                }
                var error: NSDictionary?
                let result = script?.executeAndReturnError(&error)
                let errorMessage = error?[NSAppleScript.errorMessage] as? String
                    ?? (result == nil ? "Could not communicate with QLab" : nil)
                completion(result?.stringValue, errorMessage)
            }
        }
    }
}

enum WaveformReader {
    static func samples(from url: URL, startTime: Double, endTime: Double, binCount: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let firstFrame = max(0, AVAudioFramePosition(startTime * sampleRate))
        let requestedEnd = AVAudioFramePosition(endTime * sampleRate)
        let lastFrame = min(file.length, max(firstFrame, requestedEnd))
        let frameCount = lastFrame - firstFrame
        guard frameCount > 0, binCount > 0 else { return [] }

        file.framePosition = firstFrame
        var peaks = Array(repeating: Float.zero, count: binCount)
        // At full-track scale, inspecting every source frame adds substantial work
        // without adding visible detail. Eight observations per display bin retains
        // useful peak variation while making first-time waveform generation fast.
        let targetObservations = AVAudioFramePosition(binCount * 8)
        let sampleStride = max(1, frameCount / targetObservations)
        let bufferSize: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else { return [] }
        var processed: AVAudioFramePosition = 0

        while processed < frameCount {
            let wanted = AVAudioFrameCount(min(AVAudioFramePosition(bufferSize), frameCount - processed))
            try file.read(into: buffer, frameCount: wanted)
            let count = Int(buffer.frameLength)
            guard count > 0 else { break }

            if let channels = buffer.floatChannelData {
                let stride = Int(sampleStride)
                let firstSample = Int((sampleStride - (processed % sampleStride)) % sampleStride)
                for frame in Swift.stride(from: firstSample, to: count, by: stride) {
                    var magnitude: Float = 0
                    for channel in 0..<Int(format.channelCount) {
                        magnitude = max(magnitude, abs(channels[channel][frame]))
                    }
                    let absoluteFrame = processed + AVAudioFramePosition(frame)
                    let bin = min(binCount - 1, Int(absoluteFrame * AVAudioFramePosition(binCount) / frameCount))
                    peaks[bin] = max(peaks[bin], magnitude)
                }
            }
            processed += AVAudioFramePosition(count)
        }

        let maximum = peaks.max() ?? 0
        return maximum > 0 ? peaks.map { $0 / maximum } : peaks
    }
}
