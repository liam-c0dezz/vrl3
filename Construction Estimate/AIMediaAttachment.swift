import AVFoundation
import Foundation
import UIKit
import UniformTypeIdentifiers

enum AIAttachmentKind: String, Codable {
    case audio
    case video
}

struct PreparedAIAttachment {
    let kind: AIAttachmentKind
    let displayName: String
    let mimeType: String?
    let attachmentData: Data?
    let videoFramesJPEG: [Data]
    let videoAudioData: Data?
    let thumbnailJPEG: Data?

    var requestPayload: [String: Any] {
        var payload: [String: Any] = ["attachment_kind": kind.rawValue]
        if let mimeType { payload["attachment_mime_type"] = mimeType }
        if let attachmentData {
            payload["attachment_base64"] = attachmentData.base64EncodedString()
        }
        if !videoFramesJPEG.isEmpty {
            payload["video_frames_base64"] = videoFramesJPEG.map {
                $0.base64EncodedString()
            }
        }
        if let videoAudioData {
            payload["video_audio_base64"] = videoAudioData.base64EncodedString()
        }
        return payload
    }
}

enum AIAttachmentPreparationError: LocalizedError {
    case unsupportedType
    case fileTooLarge
    case videoTooLong
    case unreadable
    case noUsableVideoContent

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "Choose an MP3, M4A, WAV, WebM, MP4, MOV, or M4V file."
        case .fileTooLarge:
            "Choose an attachment smaller than 25 MB."
        case .videoTooLong:
            "Choose a video that is 60 seconds or shorter."
        case .unreadable:
            "That attachment couldn't be read. Try another file."
        case .noUsableVideoContent:
            "EasyBid couldn't extract usable frames or audio from that video."
        }
    }
}

enum AIAttachmentPreparer {
    static let maximumSourceBytes = 25_000_000
    static let maximumVideoSeconds = 60.0
    static let maximumVideoFrames = 6
    static let maximumFrameBytes = 2_000_000
    static let maximumCombinedFrameBytes = 8_000_000

    static func prepare(url: URL) async throws -> PreparedAIAttachment {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        guard let fileSize = values.fileSize, fileSize <= maximumSourceBytes else {
            throw AIAttachmentPreparationError.fileTooLarge
        }

        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .movie) {
            return try await prepareVideo(url: url)
        }
        if let type, type.conforms(to: .audio) {
            return try prepareAudio(url: url)
        }
        throw AIAttachmentPreparationError.unsupportedType
    }

    private static func prepareAudio(url: URL) throws -> PreparedAIAttachment {
        guard let mimeType = supportedAudioMIMEType(for: url) else {
            throw AIAttachmentPreparationError.unsupportedType
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= maximumSourceBytes else {
            throw AIAttachmentPreparationError.fileTooLarge
        }
        return PreparedAIAttachment(
            kind: .audio,
            displayName: "Audio attached",
            mimeType: mimeType,
            attachmentData: data,
            videoFramesJPEG: [],
            videoAudioData: nil,
            thumbnailJPEG: nil
        )
    }

    private static func prepareVideo(url: URL) async throws -> PreparedAIAttachment {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            throw AIAttachmentPreparationError.unreadable
        }
        guard seconds <= maximumVideoSeconds else {
            throw AIAttachmentPreparationError.videoTooLong
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)

        var frames: [Data] = []
        var combinedBytes = 0
        for index in 0..<maximumVideoFrames {
            let fraction = Double(index + 1) / Double(maximumVideoFrames + 1)
            let time = CMTime(seconds: seconds * fraction, preferredTimescale: 600)
            do {
                let (image, _) = try await generator.image(at: time)
                let uiImage = UIImage(cgImage: image)
                guard let jpeg = boundedJPEG(from: uiImage),
                      jpeg.count <= maximumFrameBytes,
                      combinedBytes + jpeg.count <= maximumCombinedFrameBytes else {
                    continue
                }
                frames.append(jpeg)
                combinedBytes += jpeg.count
            } catch {
                continue
            }
        }

        let audio = try? await extractAudio(from: asset)
        guard !frames.isEmpty || audio != nil else {
            throw AIAttachmentPreparationError.noUsableVideoContent
        }

        return PreparedAIAttachment(
            kind: .video,
            displayName: "Video attached",
            mimeType: audio == nil ? nil : "audio/mp4",
            attachmentData: nil,
            videoFramesJPEG: frames,
            videoAudioData: audio,
            thumbnailJPEG: frames.first
        )
    }

    private static func extractAudio(from asset: AVAsset) async throws -> Data {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty,
              let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
              ) else {
            throw AIAttachmentPreparationError.noUsableVideoContent
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "easybid-ai-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await exportSession.export(to: outputURL, as: .m4a)
        let data = try Data(contentsOf: outputURL, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= maximumSourceBytes else {
            throw AIAttachmentPreparationError.fileTooLarge
        }
        return data
    }

    private static func boundedJPEG(from image: UIImage) -> Data? {
        for quality in [0.72, 0.58, 0.44, 0.30] {
            if let data = image.jpegData(compressionQuality: quality),
               data.count <= maximumFrameBytes {
                return data
            }
        }
        return nil
    }

    private static func supportedAudioMIMEType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp3", "mpeg", "mpga": "audio/mpeg"
        case "m4a", "mp4": "audio/mp4"
        case "wav": "audio/wav"
        case "webm": "audio/webm"
        default: nil
        }
    }
}

