import AVFoundation
import CoreGraphics

public enum RecordingSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case microphone
    case system
    case both

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .microphone: "Microphone"
        case .system: "System Audio"
        case .both: "Mic + System"
        }
    }

    public var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .system: "speaker.wave.2.fill"
        case .both: "person.2.wave.2.fill"
        }
    }

    var usesMicrophone: Bool { self != .system }
    var usesSystemAudio: Bool { self != .microphone }
}

public enum RecordingError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case systemAudioPermissionDenied
    case noMicrophone
    case nothingRecorded

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Transkribe needs microphone access. Allow it in System Settings → Privacy & Security → Microphone."
        case .systemAudioPermissionDenied:
            "To record system audio, allow Transkribe in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
        case .noMicrophone:
            "No microphone was found."
        case .nothingRecorded:
            "Nothing was recorded. If you chose System Audio, make sure something was playing."
        }
    }

    /// Deep link to the relevant privacy pane in System Settings.
    public var settingsURL: URL? {
        switch self {
        case .microphonePermissionDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .systemAudioPermissionDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        default:
            nil
        }
    }
}

/// Captures microphone and/or system audio into separate tracks inside `directory`.
public final class RecordingSession: @unchecked Sendable {
    public static let microphoneFile = "microphone.m4a"
    public static let systemFile = "system.m4a"

    public let source: RecordingSource
    private let directory: URL
    private let microphone = MicrophoneRecorder()
    private let system = SystemAudioRecorder()

    public init(source: RecordingSource, directory: URL) {
        self.source = source
        self.directory = directory
    }

    public static func requestPermissions(for source: RecordingSource) async throws {
        if source.usesMicrophone {
            let granted: Bool = switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: true
            case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
            default: false
            }
            guard granted else { throw RecordingError.microphonePermissionDenied }
        }
        if source.usesSystemAudio, !CGPreflightScreenCaptureAccess() {
            // Shows the system prompt the first time; afterwards the user must flip the switch in Settings.
            guard CGRequestScreenCaptureAccess() else { throw RecordingError.systemAudioPermissionDenied }
        }
    }

    /// `onLevel` reports the louder of the active inputs (0...1), on an arbitrary thread.
    public func start(onLevel: @escaping @Sendable (Float) -> Void, onFailure: @escaping @Sendable (Error) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if source.usesSystemAudio {
            try await system.start(to: directory.appendingPathComponent(Self.systemFile), onLevel: onLevel, onFailure: onFailure)
        }
        if source.usesMicrophone {
            do {
                try microphone.start(
                    to: directory.appendingPathComponent(Self.microphoneFile),
                    echoCancellation: source == .both,
                    onLevel: onLevel,
                    onFailure: onFailure
                )
            } catch {
                _ = await system.stop()
                throw error
            }
        }
    }

    /// Stops capture and returns the tracks that contain audio, aligned on a shared timeline.
    public func stop() async throws -> [AudioTrack] {
        var starts: [(file: String, speaker: Speaker, start: Double)] = []
        if source.usesMicrophone, let start = microphone.stop() {
            starts.append((Self.microphoneFile, .me, start))
        }
        if source.usesSystemAudio, let start = await system.stop() {
            starts.append((Self.systemFile, .others, start))
        }
        guard let origin = starts.map(\.start).min() else { throw RecordingError.nothingRecorded }
        return starts.map { AudioTrack(fileName: $0.file, speaker: $0.speaker, offset: $0.start - origin) }
    }
}
