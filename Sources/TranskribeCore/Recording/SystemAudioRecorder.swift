import AVFoundation
import ScreenCaptureKit

/// Records everything the Mac plays (calls, videos, meetings) via ScreenCaptureKit.
final class SystemAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let sampleRate = 48_000

    private var stream: SCStream?
    private var writer: AudioFileWriter?
    private let queue = DispatchQueue(label: "Transkribe.SystemAudio")
    private var onLevel: (@Sendable (Float) -> Void)?
    private var failure: FirstFailure?

    func start(
        to url: URL,
        liveCopy: URL?,
        onLevel: @escaping @Sendable (Float) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) async throws {
        failure = FirstFailure(handler: onFailure)
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecordingError.systemAudioPermissionDenied
        }
        guard let display = content.displays.first else { throw RecordingError.systemAudioPermissionDenied }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = Self.sampleRate
        configuration.channelCount = 2
        // Video can't be turned off entirely; keep it as cheap as possible.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        writer = try AudioFileWriter(url: url, sampleRate: Double(Self.sampleRate), liveCopy: liveCopy)
        self.onLevel = onLevel
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    /// Stops recording and closes the file. Returns when the first sample was captured, or nil if nothing was.
    func stop() async -> Double? {
        try? await stream?.stopCapture()
        stream = nil
        // Drain any sample buffer still being written on the capture queue.
        return queue.sync {
            defer { writer = nil }
            return writer?.finish()
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let writer,
              let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        let host = sampleBuffer.presentationTimeStamp.seconds
        do {
            onLevel?(try writer.write(buffer, hostSeconds: host))
        } catch {
            failure?.report(error)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failure?.report(error)
    }

    // MARK: - Helpers

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              var asbd = Optional(description),
              let format = AVAudioFormat(streamDescription: &asbd) else { return nil }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}
