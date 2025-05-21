//
//  OCRService.swift
//  amnesia
//

import Foundation
import Vision
import CoreGraphics

actor OCRService {

    func performOCR(on image: CGImage) async -> String? {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNRecognizeTextRequest()

        // Configure recognition level from UserDefaults
        let recognitionLevelSetting = UserDefaults.standard.string(forKey: UserDefaultsKeys.ocrRecognitionLevel) ?? "accurate"
        if recognitionLevelSetting.lowercased() == "fast" {
            request.recognitionLevel = .fast
            print("[OCRService] Using FAST recognition level.")
        } else {
            request.recognitionLevel = .accurate // Default
            print("[OCRService] Using ACCURATE recognition level.")
        }
        
        // request.recognitionLanguages = ["en-US"] // Prioritize English
        request.usesLanguageCorrection = true

        do {
            try requestHandler.perform([request])
            guard let observations = request.results else {
                print("[OCRService] OCR perform: No observations found.")
                return nil
            }

            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            let resultText = recognizedStrings.joined(separator: "\n")
            if resultText.isEmpty {
                 print("[OCRService] OCR completed but no text was recognized.")
                 return nil // Return nil if nothing was recognized
            }
            print("[OCRService] OCR successfully recognized \(resultText.count) characters.")
            return resultText
        } catch {
            print("[OCRService] OCR Error: \(error.localizedDescription). Image details (e.g., size): \(image.width)x\(image.height)")
            return nil
        }
    }
}
