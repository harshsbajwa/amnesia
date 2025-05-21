//
//  ScreenshotGalleryView.swift
//  amnesia
//
//  Created by Harsh Bajwa on 2025-05-19.
//

import SwiftUI
import CoreData

struct ScreenshotGalleryView: View {
    @StateObject private var viewModel: ScreenshotGalleryViewModel
    @Environment(\.dismiss) var dismiss


    private let columns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 8), count: 3)
    private let thumbnailHeight: CGFloat = 150


    init(dataStorageService: DataStorageService) {
        _viewModel = StateObject(wrappedValue: ScreenshotGalleryViewModel(dataStorageService: dataStorageService))
    }

    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isLoading {
                    ProgressView("Loading Captures...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.allCaptureEvents.isEmpty {
                    Text("No captures found.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(viewModel.allCaptureEvents) { event in
                                ScreenshotThumbnailView(
                                    captureEvent: event,
                                    dataStorageService: viewModel.dataStorageService,
                                    height: thumbnailHeight
                                )
                                .onTapGesture {
                                    viewModel.selectedEvent = event
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .navigationTitle("Screenshot Gallery")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { // Changed placement
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.fetchAllEvents()
            }
            .sheet(item: $viewModel.selectedEvent) { event in
                ScreenshotDetailView(event: event, dataStorageService: viewModel.dataStorageService)
            }
        }
        .frame(minWidth: 600, idealWidth: 800, minHeight: 500, idealHeight: 700) // Provide a frame for the sheet
    }
}

@MainActor
class ScreenshotGalleryViewModel: ObservableObject {
    @Published var allCaptureEvents: [CaptureEventViewModel] = []
    @Published var selectedEvent: CaptureEventViewModel?
    @Published var isLoading: Bool = false
    let dataStorageService: DataStorageService

    private var dateFormatter: DateFormatter

    init(dataStorageService: DataStorageService) {
        self.dataStorageService = dataStorageService
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "MMM d, yyyy HH:mm:ss"
    }

    func fetchAllEvents() {
        isLoading = true
        Task {
            let events = await dataStorageService.fetchRecentEvents(limit: 0) // Fetch all
            let viewModels = events.map { event in
                CaptureEventViewModel(
                    id: event.objectID, // NSManagedObjectID should be handled carefully if crossing actor boundaries. Here, it's okay as VM is MainActor.
                    timestamp: event.timestamp != nil ? dateFormatter.string(from: event.timestamp!) : "Unknown Time",
                    applicationName: event.applicationName ?? "Unknown App",
                    ocrText: event.ocrText,
                    screenshotPath: event.screenshotPath
                )
            }
            
            // Ensure updates are on the main actor, though Task from @MainActor func already is.
            // This explicit self. is fine.
            self.allCaptureEvents = viewModels
            self.isLoading = false
            print("[ScreenshotGalleryViewModel] Fetched all events. Count: \(self.allCaptureEvents.count)")
        }
    }
}


struct CaptureEventViewModel: Identifiable {
    let id: NSManagedObjectID
    let timestamp: String
    let applicationName: String
    let ocrText: String?
    let screenshotPath: String?
}

struct ScreenshotDetailView: View {
    let event: CaptureEventViewModel
    let dataStorageService: DataStorageService
    @State private var image: Image?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Capture Details")
                    .font(.title2)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(.bottom)

            if let image = image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .cornerRadius(8)
            } else {
                ProgressView("Loading image...")
                    .frame(height: 200)
            }

            Text("Time: \(event.timestamp)")
            Text("Application: \(event.applicationName)")
            if let ocr = event.ocrText, !ocr.isEmpty {
                ScrollView {
                    Text("OCR Text: \(ocr)")
                        .font(.caption)
                }
                .frame(maxHeight: 150)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.1)) // Use NSColor for adaptability
                .cornerRadius(5)
            } else {
                Text("OCR Text: Not available or empty.")
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, idealWidth: 500, minHeight: 300, idealHeight: 600)
        .onAppear {
            Task {
                await loadImage()
            }
        }
    }

    @MainActor
    private func loadImage() async {
        guard let path = event.screenshotPath else {
            print("[ScreenshotDetailView] Screenshot path is nil for event ID: \(event.id).")
            return
        }

        guard let fileURL = await dataStorageService.getFullScreenshotURL(relativePath: path) else {
            print("[ScreenshotDetailView] Could not get full screenshot URL for path: \(path)")
            return
        }

        // Load image data in a detached task
        let imageData: Data? = await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("[ScreenshotDetailView] Image file does not exist at path: \(fileURL.path)")
                return nil
            }
            do {
                return try Data(contentsOf: fileURL)
            } catch {
                print("[ScreenshotDetailView] Failed to load image data from URL: \(fileURL), error: \(error)")
                return nil
            }
        }.value

        // Create NSImage and SwiftUI Image on the main actor
        if let data = imageData, let nsImage = NSImage(data: data) {
            self.image = Image(nsImage: nsImage)
            print("[ScreenshotDetailView] Image loaded successfully for event ID: \(event.id).")
        } else {
            // Consider setting a placeholder error image or state
            print("[ScreenshotDetailView] Failed to create NSImage from data or data was nil for event ID: \(event.id).")
        }
    }
}


#Preview {
    let inMemoryDataStorage = DataStorageService(inMemory: true)
    // Populate with some sample data for preview if desired
    // Task {
    //     await SampleData.addSampleCaptureEvents(to: inMemoryDataStorage, count: 5)
    // }
    return ScreenshotGalleryView(dataStorageService: inMemoryDataStorage)
}
