import AppKit
import UniformTypeIdentifiers

/// File choose panels - the only place with `NSOpenPanel`. Views say what they
/// are looking for and what to tell the user; the panel settings are here.
@MainActor
enum FilePanels {
    /// Audio files that can be added (other formats go through conversion).
    static let audioTypes: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]

    /// One image. We read through ImageIO, so we take everything macOS opens.
    static func chooseImage(message: String, prompt: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = message
        if let prompt { panel.prompt = prompt }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// One audio file.
    static func chooseAudioFile(message: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = audioTypes
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Audio files and album folders.
    static func chooseAudio(message: String, prompt: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = audioTypes + [.folder]
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// One folder. `canCreate`: with a new folder button (for copies).
    static func chooseFolder(message: String, prompt: String, startingIn directory: URL? = nil,
                             canCreate: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = canCreate
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        if let directory { panel.directoryURL = directory }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
