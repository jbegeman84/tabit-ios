import AVFoundation
import Foundation
import TabitFormat

@MainActor
final class TBTPlaybackController: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentSpace = 0

    private struct StringKey: Hashable {
        let track: Int
        let string: Int
    }

    private let engine = AVAudioEngine()
    private var samplers: [Int: AVAudioUnitSampler] = [:]
    private var activeNotes: [StringKey: UInt8] = [:]
    private var eventMaps: [Int: [Int: TBTNoteEvent]] = [:]
    private var tracks: [TBTTrack] = []
    private var timer: Timer?
    private var finalSpace = 0

    func play(score: TBTScore, selectedTrack: Int) throws {
        stop()

        tracks = selectedTrack == -1
            ? score.tracks
            : score.tracks.filter { $0.id == selectedTrack }
        guard !tracks.isEmpty else { return }

        for track in tracks {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            sampler.sendProgramChange(UInt8(clamping: track.midiProgram), onChannel: 0)
            samplers[track.id] = sampler
            eventMaps[track.id] = Dictionary(
                uniqueKeysWithValues: track.events.map { ($0.space, $0) }
            )
        }

        try engine.start()
        currentSpace = 0
        finalSpace = tracks.map(\.spaceCount).max() ?? 0
        isPlaying = true
        tick()

        let secondsPerSpace = max(0.015, 60.0 / Double(max(score.tempo, 30)) / 4.0)
        timer = Timer.scheduledTimer(
            timeInterval: secondsPerSpace,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        for (key, note) in activeNotes {
            samplers[key.track]?.stopNote(note, onChannel: 0)
        }
        activeNotes.removeAll()

        if engine.isRunning {
            engine.stop()
        }
        for sampler in samplers.values {
            engine.disconnectNodeInput(sampler)
            engine.detach(sampler)
        }
        samplers.removeAll()
        eventMaps.removeAll()
        tracks.removeAll()
        isPlaying = false
        currentSpace = 0
    }

    @objc private func timerFired() {
        tick()
    }

    private func tick() {
        guard currentSpace < finalSpace else {
            stop()
            return
        }

        for track in tracks {
            guard let event = eventMaps[track.id]?[currentSpace],
                  let sampler = samplers[track.id] else { continue }

            for note in event.notes {
                let key = StringKey(track: track.id, string: note.string)
                if let active = activeNotes.removeValue(forKey: key) {
                    sampler.stopNote(active, onChannel: 0)
                }

                switch note.value {
                case let .fret(fret):
                    let midiNote = midiNote(for: track, string: note.string, fret: fret)
                    sampler.startNote(midiNote, withVelocity: UInt8(clamping: track.volume), onChannel: 0)
                    activeNotes[key] = midiNote
                case .muted:
                    let midiNote = midiNote(for: track, string: note.string, fret: 0)
                    sampler.startNote(midiNote, withVelocity: UInt8(clamping: track.volume), onChannel: 0)
                    activeNotes[key] = midiNote
                case .stopped:
                    break
                }
            }
        }
        currentSpace += 1
    }

    private func midiNote(for track: TBTTrack, string: Int, fret: Int) -> UInt8 {
        if track.isDrumTrack {
            return UInt8(clamping: fret)
        }
        let standard = [40, 45, 50, 55, 59, 64, 0, 0]
        let openNote = standard.indices.contains(string) ? standard[string] : 40
        let tuning = track.tuning.indices.contains(string) ? track.tuning[string] : 0
        return UInt8(clamping: openNote + tuning + track.transpose + fret)
    }
}
