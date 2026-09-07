// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Vision

/// Screen OCR: the user picks an area on the app's own capture surface, the
/// text in it is recognized offline with Vision and lands on the clipboard.
/// Needs Screen Recording, requested contextually on first use.
///
/// The picking and the capture both happen here rather than through the
/// system's capture command. A separate command is judged by macOS on its own
/// standing, which on recent versions can be refused even while this app is
/// allowed, and a refused command writes no file and says nothing: the tool
/// looked dead with no crosshair, no message and nothing to fix (issue #364).
final class ScreenTextService: ObservableObject {
    static let shared = ScreenTextService()

    private var recognitionGeneration = 0

    private init() {}

    func syncWithPreferences() {
        guard AppFeature.screenOCR.isAvailable else {
            cancelSession()
            return
        }
    }

    func suspend() {
        cancelSession()
    }

    private func cancelSession() {
        recognitionGeneration += 1
    }

    func capture() {
        ScreenCaptureService.shared.capture(initial: .text)
    }

    func receiveUnifiedCapture(_ capture: ScreenshotSelectionController.Capture) {
        recognitionGeneration += 1
        recognize(capture.image)
    }

    /// What a captured region turned out to hold.
    enum Outcome: Equatable {
        case qr(BarcodeDetector.Reading)
        case text(String)
        case empty
    }

    private func recognize(_ image: CGImage) {
        let generation = recognitionGeneration
        let detectQRCodes = UserDefaults.standard.bool(forKey: DefaultsKey.screenOCRDetectQRCodes)
        let fallbackLanguages = MediaSupport.recognitionLanguages(for: L10n.shared.language.rawValue)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = ScreenTextService.outcome(for: image,
                                                    detectQRCodes: detectQRCodes,
                                                    fallbackLanguages: fallbackLanguages)
            DispatchQueue.main.async { [weak self] in
                guard self?.recognitionGeneration == generation else { return }
                let strings = L10n.shared.s
                switch outcome {
                case .qr(let reading):
                    // Show what the code holds instead of copying it blindly;
                    // the panel offers copy and, for a link, open.
                    QRResultController.shared.show(reading: reading)
                case .text(let text):
                    Self.copyToPasteboard(text)
                    QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrCopied)
                case .empty:
                    QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrNoText)
                }
            }
        }
    }

    /// Decides what a captured region holds. A QR code wins over the text:
    /// it is the thing the user pointed at, and the scan is a fast pass that
    /// falls through to text recognition when no code is found. Pure enough
    /// to exercise directly on a known image.
    static func outcome(for image: CGImage,
                        detectQRCodes: Bool,
                        fallbackLanguages: [String] = ["en-US"]) -> Outcome {
        if detectQRCodes, let reading = BarcodeDetector.read(image) {
            return .qr(reading)
        }

        // Pass 1: Accurate with automatic language detection (all languages)
        var lines = recognizedLines(in: image,
                                    level: .accurate,
                                    automaticallyDetectLanguage: true,
                                    usesLanguageCorrection: true)
        
        // Pass 2: Accurate with explicit fallback languages and no language correction (handles code, numbers, passwords)
        if lines.isEmpty {
            lines = recognizedLines(in: image,
                                    level: .accurate,
                                    automaticallyDetectLanguage: false,
                                    usesLanguageCorrection: false,
                                    preferredLanguages: fallbackLanguages)
        }

        // Pass 3: Fast recognition fallback
        if lines.isEmpty {
            lines = recognizedLines(in: image,
                                    level: .fast,
                                    automaticallyDetectLanguage: false,
                                    usesLanguageCorrection: false,
                                    preferredLanguages: fallbackLanguages)
        }
        let text = QuickToolsSupport.joinedRecognizedText(lines)
        return text.isEmpty ? .empty : .text(text)
    }

    private static func recognizedLines(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        automaticallyDetectLanguage: Bool,
        usesLanguageCorrection: Bool = true,
        preferredLanguages: [String] = []
    ) -> [QuickToolsSupport.RecognizedLine] {
        let request = VNRecognizeTextRequest()
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        request.recognitionLevel = level
        request.usesLanguageCorrection = usesLanguageCorrection
        request.automaticallyDetectsLanguage = automaticallyDetectLanguage

        if !automaticallyDetectLanguage && !preferredLanguages.isEmpty,
           let supported = try? request.supportedRecognitionLanguages() {
            let available = preferredLanguages.filter { supported.contains($0) }
            if !available.isEmpty { request.recognitionLanguages = available }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        return (request.results ?? []).compactMap { observation -> QuickToolsSupport.RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return QuickToolsSupport.RecognizedLine(text: candidate.string,
                                                    x: observation.boundingBox.minX,
                                                    y: observation.boundingBox.midY)
        }
    }

    private static func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
