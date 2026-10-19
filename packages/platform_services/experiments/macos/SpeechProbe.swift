// MAC-06 research executable; not a production SpeechService adapter.
import AVFoundation
import Foundation

final class Probe: NSObject, AVSpeechSynthesizerDelegate {
    let synth = AVSpeechSynthesizer()
    let started = Date()
    var events = [[String: Any]]()
    var current = ""
    var sessions = [ObjectIdentifier: String]()
    var complete = false
    var frames: UInt64 = 0
    var sampleRate = 0.0
    var nonzero = 0
    var buffers = 0
    var pauseAccepted = false
    var resumeAccepted = false
    var pausedCallbacks = 0
    var pauseAt = 0
    var lastRange = NSRange(location: 0, length: 0)
    var staleDropped = 0
    var utterances = [ObjectIdentifier: String]()
    override init() { super.init(); synth.delegate = self }
    func event(_ type: String, _ data: [String: Any] = [:]) {
        var value = data; value["type"] = type
        value["elapsed_ms"] = Int(Date().timeIntervalSince(started) * 1000)
        events.append(value)
    }
    func utterance(_ text: String, voice: String, session: String) -> AVSpeechUtterance {
        let value = AVSpeechUtterance(string: text)
        value.voice = AVSpeechSynthesisVoice(identifier: voice)
        value.rate = 0.52
        value.volume = 0 // Playback scheduling still runs, without emitting test sound.
        sessions[ObjectIdentifier(value)] = session
        utterances[ObjectIdentifier(value)] = text
        return value
    }
    func accept(_ value: AVSpeechUtterance) -> Bool {
        let id = sessions[ObjectIdentifier(value)] ?? "unknown"
        if id != current { staleDropped += 1; return false }
        return true
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        if accept(utterance) { event("start", ["session": current]) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        guard accept(utterance) else { return }
        lastRange = range
        let ns = utterance.speechString as NSString
        if range.location + range.length <= ns.length {
            event("range", ["session": current, "start_utf16": range.location, "length_utf16": range.length, "slice": ns.substring(with: range)])
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        if accept(utterance) { event("paused", ["session": current]) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        if accept(utterance) { event("continued", ["session": current]) }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if accept(utterance) { event("finish", ["session": current]); complete = true }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if accept(utterance) { event("cancel", ["session": current]); complete = true }
    }
    func wait(_ seconds: Double, until: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && !until() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }
    func render(_ text: String, voice: String, seconds: Double) -> [String: Any] {
        complete = false; frames = 0; nonzero = 0; buffers = 0; sampleRate = 0; current = "render"
        let value = utterance(text, voice: voice, session: current); value.volume = 1
        let begin = Date()
        synth.write(value) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            // Buffer callbacks may arrive on a worker thread; all counters on main.
            let count = pcm.frameLength
            let rate = pcm.format.sampleRate
            var audible = false
            if let data = pcm.floatChannelData, count > 0 {
                for i in stride(from: 0, to: Int(count), by: 32) { if abs(data[0][i]) > 0.0001 { audible = true; break } }
            }
            DispatchQueue.main.async {
                self.frames += UInt64(count); self.sampleRate = rate; self.buffers += 1
                if audible { self.nonzero += 1 }
                if count == 0 { self.complete = true }
            }
        }
        wait(seconds, until: { self.complete })
        let result: [String: Any] = ["voice": voice, "completed": complete, "frames": frames, "sample_rate": sampleRate, "audio_seconds": sampleRate > 0 ? Double(frames) / sampleRate : 0, "nonzero_buffers": nonzero, "buffers": buffers, "wall_seconds": Date().timeIntervalSince(begin)]
        synth.stopSpeaking(at: .immediate); wait(0.1)
        return result
    }
    func run(output: String, soak: Double) throws {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") }
        let inventory: [[String: Any]] = voices.map { ["id": $0.identifier, "language": $0.language, "name": $0.name, "quality": $0.quality.rawValue] }
        let cn = voices.first { $0.identifier == "com.apple.voice.compact.zh-CN.Tingting" }
        let tw = voices.first { $0.identifier == "com.apple.voice.compact.zh-TW.Meijia" }
        var renders = [[String: Any]]()
        for voice in [cn, tw].compactMap({ $0 }) { renders.append(render("山间来信，山間來信。雨后山路很安静。📖 e\u{301}，下一句继续。", voice: voice.identifier, seconds: 25)) }
        let voice = cn?.identifier ?? "missing"
        current = "A"; complete = false
        synth.speak(utterance(String(repeating: "山间的信带来清晨的消息。📖 e\u{301}，林舟继续前行。", count: 10), voice: voice, session: "A"))
        wait(1.2)
        pauseAccepted = synth.pauseSpeaking(at: .immediate)
        event("pause_requested", ["accepted": pauseAccepted])
        wait(0.3); pauseAt = events.filter { $0["type"] as? String == "range" }.count
        wait(1.0); pausedCallbacks = events.filter { $0["type"] as? String == "range" }.count - pauseAt
        resumeAccepted = synth.continueSpeaking()
        event("resume_requested", ["accepted": resumeAccepted]); wait(1.3)
        let captured = lastRange
        // Invalidate before stop, then start another book/session.
        current = "B"; complete = false
        let stopAccepted = synth.stopSpeaking(at: .immediate)
        event("switch_book", ["stop_accepted": stopAccepted, "old_cursor_utf16": captured.location])
        synth.speak(utterance("新书开始。繁體中文與📖，仍然保留原文。", voice: voice, session: "B"))
        wait(15, until: { self.complete })
        let shortFinished = complete
        synth.stopSpeaking(at: .immediate)
        // Real-time synthesis scheduling soak, volume zero; bounded queue, no files.
        let soakBegin = Date(); var cycles = 0
        while Date().timeIntervalSince(soakBegin) < soak {
            current = "soak-\(cycles)"; complete = false
            synth.speak(utterance("山间来信，雨后山路。新的一天慢慢开始。", voice: voice, session: current))
            wait(min(12, max(0, soak - Date().timeIntervalSince(soakBegin))), until: { self.complete })
            cycles += 1
        }
        current = "stopped"; synth.stopSpeaking(at: .immediate); wait(0.3)
        let result: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString, "voices": inventory, "renders": renders, "pause_accepted": pauseAccepted, "resume_accepted": resumeAccepted, "ranges_during_settled_pause": pausedCallbacks, "short_B_finished": shortFinished, "stale_callbacks_dropped": staleDropped, "offset_unit": "UTF-16 code units (NSRange)", "missing_voice_returns_nil": AVSpeechSynthesisVoice(identifier: "local.yueqi.missing") == nil, "soak_wall_seconds": Date().timeIntervalSince(soakBegin), "soak_cycles": cycles, "events": events, "limits": ["volume-zero playback: no listening-quality claim", "network denial applies to probe process, not proven for system XPC speech daemon", "sleep/wake and hardware audio route not tested"]]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: output))
        print("Speech probe complete: \(inventory.count) Chinese voices, \(cycles) soak cycles")
    }
}
let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "/tmp/yueqi-speech-result.json"
let seconds = args.count > 2 ? Double(args[2]) ?? 120 : 120
let probe = Probe()
do { try probe.run(output: output, soak: seconds) } catch { fputs("speech_probe_failed\n", stderr); exit(1) }
