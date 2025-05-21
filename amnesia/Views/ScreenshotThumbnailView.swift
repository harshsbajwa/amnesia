//
//  ScreenshotThumbnailView.swift
//  amnesia
//

import SwiftUI
import CoreGraphics

struct ScreenshotThumbnailView: View {
    let captureEvent: CaptureEventViewModel
    let dataStorageService: DataStorageService
    let height: CGFloat

    @State private var thumbnailImage: Image?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .frame(height: height)
                        .background(Color.secondary.opacity(0.1))
                } else if let image = thumbnailImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: height)
                        .clipped()
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .frame(height: height)
                        .background(Color.secondary.opacity(0.1))
                }
            }
            .cornerRadius(6)

            Text(captureEvent.applicationName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(captureEvent.timestamp)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.bottom, 6)
        .onAppear {
            if thumbnailImage == nil {
                loadThumbnail()
            }
        }
    }

    private func loadThumbnail() {
        Task {
            await SloadThumbnailAsync()
        }
    }

    @MainActor
    private func SloadThumbnailAsync() async {
        self.isLoading = true
        
        guard let path = captureEvent.screenshotPath else {
            self.isLoading = false
            print("[ScreenshotThumbnailView] Screenshot path is nil for event: \(captureEvent.id)")
            return
        }
        guard let fileURL = await dataStorageService.getFullScreenshotURL(relativePath: path) else {
            self.isLoading = false
            print("[ScreenshotThumbnailView] Could not get full screenshot URL for path: \(path)")
            return
        }

        let currentHeight = self.height
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0

        // Load Data in detached task, CGImage creation can also be here if it's thread-safe
        // For NSImage, we will only create it on MainActor from Data or CGImage.
        let cgImageResult: CGImage? = await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("[ScreenshotThumbnailView] Thumbnail file does not exist at path: \(fileURL.path)")
                return nil
            }
            
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                print("[ScreenshotThumbnailView] Failed to create CGImageSource for URL: \(fileURL)")
                return nil
            }

            let maxDimension = Int(currentHeight * scaleFactor * 1.5)
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                print("[ScreenshotThumbnailView] Failed to create thumbnail CGImage from source for URL: \(fileURL).")
                return nil
            }
            return cgImage // Return CGImage which is Sendable
        }.value
        
        // Back on MainActor to create NSImage and SwiftUI Image
        if let cgImg = cgImageResult {
            // NSImage from CGImage should be done on MainActor
            let nsImage = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
            self.thumbnailImage = Image(nsImage: nsImage)
        } else {
            print("[ScreenshotThumbnailView] Failed to load CGImage for thumbnail: \(captureEvent.id)")
        }
        self.isLoading = false
    }
}
