import AVFoundation
import Foundation
import TabitFormat

@MainActor
final class TBTPlaybackController: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTimelinePosition = 0.0

    private struct StringKey: Hashable {
        let track: Int
        let string: Int
    }

    private struct ScheduledEvent {
        let timelinePosition: Double
        let track: TBTTrack
        let event: TBTNoteEvent
    }

    private let engine = AVAudioEngine()
    private var samplers: [Int: AVAudioUnitSampler] = [:]
    private var activeNotes: [StringKey: UInt8] = [:]
    private var scheduledEvents: [ScheduledEvent] = []
    private var nextEventIndex = 0
    private var timer: Timer?
    private var playbackStartTime = 0.0
    private var secondsPerSpace = 0.1
    private var finalTimelinePosition = 0.0

    func play(score: TBTScore, selectedTrack: Int) throws {
        stop(resetPosition: true)

        let tracks = selectedTrack == -1
            ? score.tracks
            : score.tracks.filter { $0.id == selectedTrack }
        guard !tracks.isEmpty else { return }

        for track in tracks {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            sampler.sendProgramChange(UInt8(clamping: track.midiProgram), onChannel: 0)
            samplers[track.id] = sampler
            scheduledEvents.append(contentsOf: track.events.map { event in
                ScheduledEvent(
                    timelinePosition: timelinePosition(for: event.space, in: track),
                    track: track,
                    event: event
                )
            })
        }
        scheduledEvents.sort {
            if $0.timelinePosition == $1.timelinePosition {
                return $0.track.id < $1.track.id
            }
            return $0.timelinePosition < $1.timelinePosition
        }

        try engine.start()
        currentTimelinePosition = 0
        finalTimelinePosition = tracks.compactMap {
            $0.timelinePositions.last.map { $0 + 1 }
        }.max() ?? 0
        secondsPerSpace = max(0.015, 60.0 / Double(max(score.tempo, 30)) / 4.0)
        playbackStartTime = ProcessInfo.processInfo.systemUptime
        nextEventIndex = 0
        isPlaying = true
        tick()

        timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    func stop() {
        stop(resetPosition: false)
    }

    private func stop(resetPosition: Bool) {
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
        scheduledEvents.removeAll()
        nextEventIndex = 0
        isPlaying = false
        if resetPosition {
            currentTimelinePosition = 0
        }
    }

    @objc private func timerFired() {
        tick()
    }

    private func tick() {
        let elapsed = ProcessInfo.processInfo.systemUptime - playbackStartTime
        currentTimelinePosition = min(elapsed / secondsPerSpace, finalTimelinePosition)

        while nextEventIndex < scheduledEvents.count,
              scheduledEvents[nextEventIndex].timelinePosition <= currentTimelinePosition {
            play(scheduledEvents[nextEventIndex])
            nextEventIndex += 1
        }

        if currentTimelinePosition >= finalTimelinePosition {
            stop(resetPosition: false)
        }
    }

    private func play(_ scheduled: ScheduledEvent) {
        guard let sampler = samplers[scheduled.track.id] else {
            return
        }

        for note in scheduled.event.notes {
            let key = StringKey(track: scheduled.track.id, string: note.string)
            if let active = activeNotes.removeValue(forKey: key) {
                sampler.stopNote(active, onChannel: 0)
            }

            switch note.value {
            case let .fret(fret):
                let midiNote = midiNote(
                    for: scheduled.track,
                    string: note.string,
                    fret: fret
                )
                sampler.startNote(
                    midiNote,
                    withVelocity: UInt8(clamping: scheduled.track.volume),
                    onChannel: 0
                )
                activeNotes[key] = midiNote
            case .muted:
                let midiNote = midiNote(for: scheduled.track, string: note.string, fret: 0)
                sampler.startNote(
                    midiNote,
                    withVelocity: UInt8(clamping: scheduled.track.volume),
                    onChannel: 0
                )
                activeNotes[key] = midiNote
            case .stopped:
                break
            }
        }
    }

    private func timelinePosition(for space: Int, in track: TBTTrack) -> Double {
        guard track.timelinePositions.indices.contains(space) else {
            return Double(space)
        }
        return track.timelinePositions[space]
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
