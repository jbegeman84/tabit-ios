import Foundation

public struct TBTScore: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var transcribedBy: String
    public var comment: String
    public var tempo: Int
    public var tracks: [TBTTrack]
    public var barLines: [TBTBarLine]
}

public struct TBTTrack: Equatable, Identifiable, Sendable {
    public let id: Int
    public var name: String
    public var spaceCount: Int
    public var stringCount: Int
    public var midiProgram: Int
    public var volume: Int
    public var pan: Int
    public var transpose: Int
    public var tuning: [Int]
    public var isDrumTrack: Bool
    public var events: [TBTNoteEvent]
    /// Start position of each physical space on the shared 1/16-note timeline.
    public var timelinePositions: [Double]

    public var instrumentName: String {
        if isDrumTrack { return "Drums" }
        return GeneralMIDI.name(forProgram: midiProgram)
    }
}

public struct TBTNoteEvent: Equatable, Identifiable, Sendable {
    public var space: Int
    public var notes: [TBTStringNote]
    public var topText: Character?
    public var bottomText: Character?

    public var id: Int { space }

    public init(
        space: Int,
        notes: [TBTStringNote],
        topText: Character?,
        bottomText: Character?
    ) {
        self.space = space
        self.notes = notes
        self.topText = topText
        self.bottomText = bottomText
    }
}

public struct TBTStringNote: Equatable, Identifiable, Sendable {
    public enum Value: Equatable, Sendable {
        case fret(Int)
        case muted
        case stopped
    }

    public var string: Int
    public var value: Value
    public var effect: TBTNoteEffect?

    public var id: Int { string }

    public init(string: Int, value: Value, effect: TBTNoteEffect?) {
        self.string = string
        self.value = value
        self.effect = effect
    }
}

public enum TBTNoteEffect: UInt8, Equatable, Sendable {
    case soft = 0x28
    case slideUp = 0x2f
    case harmonic = 0x3c
    case slideDown = 0x5c
    case bendUp = 0x5e
    case bend = 0x62
    case hammerOn = 0x68
    case pullOff = 0x70
    case releaseBend = 0x72
    case slap = 0x73
    case tap = 0x74
    case whammyBend = 0x77
    case tremolo = 0x7b
    case vibrato = 0x7e
}

public struct TBTBarLine: Equatable, Identifiable, Sendable {
    public var space: Int
    public var isDouble: Bool
    public var opensRepeat: Bool
    public var closesRepeat: Bool
    public var repeatCount: Int

    public var id: Int { space }
}

public enum GeneralMIDI {
    private static let names = [
        "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano",
        "Honky-tonk Piano", "Electric Piano 1", "Electric Piano 2", "Harpsichord",
        "Clavinet", "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
        "Marimba", "Xylophone", "Tubular Bells", "Dulcimer", "Drawbar Organ",
        "Percussive Organ", "Rock Organ", "Church Organ", "Reed Organ", "Accordion",
        "Harmonica", "Tango Accordion", "Acoustic Guitar (nylon)",
        "Acoustic Guitar (steel)", "Electric Guitar (jazz)",
        "Electric Guitar (clean)", "Electric Guitar (muted)", "Overdriven Guitar",
        "Distortion Guitar", "Guitar Harmonics", "Acoustic Bass",
        "Electric Bass (finger)", "Electric Bass (pick)", "Fretless Bass",
        "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2", "Violin",
        "Viola", "Cello", "Contrabass", "Tremolo Strings", "Pizzicato Strings",
        "Orchestral Harp", "Timpani", "String Ensemble 1", "String Ensemble 2",
        "Synth Strings 1", "Synth Strings 2", "Choir Aahs", "Voice Oohs",
        "Synth Voice", "Orchestra Hit", "Trumpet", "Trombone", "Tuba",
        "Muted Trumpet", "French Horn", "Brass Section", "Synth Brass 1",
        "Synth Brass 2", "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax",
        "Oboe", "English Horn", "Bassoon", "Clarinet", "Piccolo", "Flute",
        "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle",
        "Ocarina", "Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)",
        "Lead 4 (chiff)", "Lead 5 (charang)", "Lead 6 (voice)",
        "Lead 7 (fifths)", "Lead 8 (bass + lead)", "Pad 1 (new age)",
        "Pad 2 (warm)", "Pad 3 (polysynth)", "Pad 4 (choir)", "Pad 5 (bowed)",
        "Pad 6 (metallic)", "Pad 7 (halo)", "Pad 8 (sweep)", "FX 1 (rain)",
        "FX 2 (soundtrack)", "FX 3 (crystal)", "FX 4 (atmosphere)",
        "FX 5 (brightness)", "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)",
        "Sitar", "Banjo", "Shamisen", "Koto", "Kalimba", "Bag Pipe", "Fiddle",
        "Shanai", "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
        "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
        "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
        "Telephone Ring", "Helicopter", "Applause", "Gunshot",
    ]

    public static func name(forProgram program: Int) -> String {
        guard names.indices.contains(program) else { return "MIDI Program \(program + 1)" }
        return names[program]
    }
}
