//
//  ScreenCaptureService.swift
//  amnesia
//

import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit
import VideoToolbox
import Combine

@MainActor
class ScreenCaptureService: NSObject, SCStreamOutput, SCStreamDelegate, ObservableObject {
    private var stream: SCStream?
    private var captureTimer: Timer?

    @Published var captureInterval: TimeInterval {
        didSet {
            if isCapturing {
                captureTimer?.invalidate()
                captureTimer = Timer.scheduledTimer(withTimeInterval: self.captureInterval, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    Task { await self.processLatestFrameInternal() }
                }
                print("[ScreenCaptureService] Capture interval updated to \(self.captureInterval)s and timer reset.")
            }
            // If not capturing, the new interval will be used when capture next starts.
        }
    }

    private let ocrService: OCRService
    private let dataStorageService: DataStorageService

    private var latestFrame: CGImage?
    private let imageProcessingQueue = DispatchQueue(label: "com.amnesia.imageProcessingQueue", qos: .utility)

    @Published var isCapturing: Bool = false

    init(ocrService: OCRService, dataStorageService: DataStorageService) {
        self.ocrService = ocrService
        self.dataStorageService = dataStorageService
        self.captureInterval = UserDefaults.standard.double(forKey: UserDefaultsKeys.captureInterval) > 0 ? UserDefaults.standard.double(forKey: UserDefaultsKeys.captureInterval) : 10.0
        super.init()
        print("[ScreenCaptureService] Initialized with capture interval: \(self.captureInterval)s")
    }

    private func setLatestFrame(_ image: CGImage?) {
        self.latestFrame = image
    }

    private func clearLatestFrame() {
        self.latestFrame = nil
    }

    func startCapturing() async {
        print("[ScreenCaptureService] startCapturing: ATTEMPTING ENTRY. Current self.isCapturing: \(self.isCapturing)")
        guard !isCapturing else {
            print("[ScreenCaptureService] Attempted to start capture, but already capturing.")
            return
        }
        print("[ScreenCaptureService] --- Attempting to start capture sequence ---")

        print("[ScreenCaptureService] 1. Checking screen capture access via CGPreflightScreenCaptureAccess().")
        guard CGPreflightScreenCaptureAccess() else {
            print("[ScreenCaptureService] ERROR: Screen recording permission NOT GRANTED (CGPreflightScreenCaptureAccess failed). Cannot start capture.")
            self.isCapturing = false
            return
        }
        print("[ScreenCaptureService] OK: Screen recording permission IS GRANTED (CGPreflightScreenCaptureAccess succeeded).")

        do {
            print("[ScreenCaptureService] 2. Getting current shareable content (SCShareableContent.current)...")
            let content = try await SCShareableContent.current
            print("[ScreenCaptureService] OK: Got shareable content. Displays: \(content.displays.count), Applications: \(content.applications.count)")

            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                print("[ScreenCaptureService] ERROR: No display found to capture.")
                self.isCapturing = false
                return
            }
            print("[ScreenCaptureService] OK: Selected display for capture: ID \(display.displayID), \(display.width)x\(display.height)")

            let excludedBundleIDs = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedAppBundleIDs) ?? []
            let applicationsToExclude = content.applications.filter { app in
                excludedBundleIDs.contains(app.bundleIdentifier)
            }
            print("[ScreenCaptureService] Applications to exclude: \(applicationsToExclude.map(\.applicationName).joined(separator: ", "))")

            let filter = SCContentFilter(display: display, excludingApplications: applicationsToExclude, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 5) // Capture at most 5 FPS
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 5 // Number of frames to queue
            config.showsCursor = true
            config.capturesAudio = false // Explicitly false

            print("[ScreenCaptureService] 3. Initializing SCStream with filter and configuration...")
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            
            print("[ScreenCaptureService] 4. Adding stream output...")
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: imageProcessingQueue)
            
            print("[ScreenCaptureService] 5. Starting stream capture (stream.startCapture())...")
            try await stream?.startCapture()
            print("[ScreenCaptureService] OK: Stream capture started successfully.")

            self.isCapturing = true // Set after successful start
            print("[ScreenCaptureService] --- Capture started successfully on display \(display.displayID). Interval: \(self.captureInterval)s. ---")

            self.captureTimer?.invalidate()
            self.captureTimer = Timer.scheduledTimer(withTimeInterval: self.captureInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.processLatestFrameInternal()
                }
            }
        } catch {
            print("[ScreenCaptureService] CATCH_ERROR: Error during startCapture sequence: \(error.localizedDescription)")
            print("[ScreenCaptureService] CATCH_ERROR_DETAILS: \(error)") // Log the full error
            self.isCapturing = false
            if let stream = self.stream {
              print("[ScreenCaptureService] Attempting to stop potentially partially started stream...")
              Task { try? await stream.stopCapture() }
            }
            self.stream = nil
        }
    }

    func stopCapturing() async {
        guard isCapturing else {
            print("[ScreenCaptureService] Attempted to stop capture, but not active.")
            return
        }
        print("[ScreenCaptureService] --- Attempting to stop capture sequence ---")

        captureTimer?.invalidate()
        captureTimer = nil

        if let streamToStop = stream {
            do {
                try await streamToStop.stopCapture()
                print("[ScreenCaptureService] OK: Stream stopped successfully.")
            } catch {
                print("[ScreenCaptureService] ERROR: Error stopping stream: \(error.localizedDescription)")
            }
        }
        self.isCapturing = false // Set after successful stop or failure handling
        self.clearLatestFrame()
        self.stream = nil // Clear the stream reference
        print("[ScreenCaptureService] --- Capture stopped. ---")
    }

    private func getActiveWindowTitle() async -> String? {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
             print("[ScreenCaptureService] Frontmost app: \(frontApp.localizedName ?? "N/A"). Window title detection is limited.")
        }
        return nil
    }


    private func checkExclusion(applicationName: String?, bundleIdentifier: String?) async -> Bool {
        let defaults = UserDefaults.standard
        let activeWindowTitle = await getActiveWindowTitle()

        if let excludedIDs = defaults.stringArray(forKey: UserDefaultsKeys.excludedAppBundleIDs),
           let bundleID = bundleIdentifier,
           excludedIDs.contains(bundleID) {
            print("[ScreenCaptureService] Exclusion: App \(bundleID) is in excluded bundle IDs.")
            return true
        }

        if let excludedKeywords = defaults.stringArray(forKey: UserDefaultsKeys.excludedWindowTitleKeywords),
           let title = activeWindowTitle?.lowercased() {
            for keyword in excludedKeywords {
                if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.contains(keyword.lowercased()) {
                    print("[ScreenCaptureService] Exclusion: Window title '\(title)' contains excluded keyword '\(keyword)'.")
                    return true
                }
            }
        }

        if defaults.bool(forKey: UserDefaultsKeys.ignoreIncognitoWindows), let title = activeWindowTitle?.lowercased() {
            let incognitoTerms = ["incognito", "private browsing", "inprivate"]
            for term in incognitoTerms {
                if title.contains(term) {
                    print("[ScreenCaptureService] Exclusion: Window title '\(title)' suggests incognito mode.")
                    return true
                }
            }
        }
        return false
    }

    private func processLatestFrameInternal() async {
        guard let frameToProcess = latestFrame else {
            return
        }

        setLatestFrame(nil) // Clear immediately to avoid reprocessing
        print("[ScreenCaptureService] Processing new frame. Timestamp: \(Date())")

        let timestamp = Date()
        let activeAppInfo = await MainActor.run { () -> (name: String?, id: String?) in
            let activeApp = NSWorkspace.shared.frontmostApplication
            return (activeApp?.localizedName, activeApp?.bundleIdentifier)
        }

        if await self.checkExclusion(applicationName: activeAppInfo.name, bundleIdentifier: activeAppInfo.id) {
            print("[ScreenCaptureService] Frame processing skipped due to exclusion rules for app: \(activeAppInfo.name ?? activeAppInfo.id ?? "Unknown")")
            return
        }

        let ocrText = await ocrService.performOCR(on: frameToProcess)
        if ocrText != nil {
            print("[ScreenCaptureService] OCR completed. Text length: \(ocrText?.count ?? 0).")
        } else {
            print("[ScreenCaptureService] OCR returned no text or failed.")
        }

        let screenshotPath = await dataStorageService.saveScreenshot(frameToProcess, timestamp: timestamp)
        if screenshotPath != nil {
            print("[ScreenCaptureService] Screenshot saved to path: \(screenshotPath!).")
        } else {
            print("[ScreenCaptureService] Failed to save screenshot.")
        }

        await dataStorageService.saveCaptureEvent(
            timestamp: timestamp,
            ocrText: ocrText,
            screenshotPath: screenshotPath,
            applicationName: activeAppInfo.name,
            bundleIdentifier: activeAppInfo.id
        )
        print("[ScreenCaptureService] Capture event persistence initiated for app: \(activeAppInfo.name ?? "N/A").")
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer), CMSampleBufferGetNumSamples(sampleBuffer) == 1 else {
            if type != .screen { print("[ScreenCaptureService] Stream: Received non-screen sample buffer.") }
            if !CMSampleBufferIsValid(sampleBuffer) { print("[ScreenCaptureService] Stream: Received invalid sample buffer.") }
            if CMSampleBufferGetNumSamples(sampleBuffer) != 1 { print("[ScreenCaptureService] Stream: Received sample buffer with unexpected number of samples: \(CMSampleBufferGetNumSamples(sampleBuffer))") }
            return
        }

        guard let cvImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("[ScreenCaptureService] Stream: Failed to get CVPixelBuffer from sample buffer.")
            return
        }

        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(cvImageBuffer, options: nil, imageOut: &cgImage)

        guard status == kCVReturnSuccess, let finalImage = cgImage else {
            print("[ScreenCaptureService] Stream: Failed to create CGImage from CVPixelBuffer, VT status: \(status). Image was nil: \(cgImage == nil)")
            return
        }
        
        Task { @MainActor [weak self] in
            self?.setLatestFrame(finalImage)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCaptureService] Stream stopped with error: \(error.localizedDescription). Full error: \(error)")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // If stream stops with error, ensure isCapturing is false and cleanup happens
            if self.isCapturing { // Check if we thought we were capturing
                 await self.stopCapturing() // This will also set isCapturing to false
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didUpdateContentRect rect: NSRect) {
        // print("[ScreenCaptureService] Stream content rectangle updated to: \(rect)")
    }
}
