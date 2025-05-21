//
//  ScreenshotTimelinePreviewView.swift
//  amnesia
//

import SwiftUI
import CoreData

struct ScreenshotTimelinePreviewView: View {
    @StateObject private var viewModel: ScreenshotTimelineViewModel
    private var dataStorageService: DataStorageService // For ScreenshotThumbnailView

    init(dataStorageService: DataStorageService) {
        self.dataStorageService = dataStorageService
        _viewModel = StateObject(wrappedValue: ScreenshotTimelineViewModel(dataStorageService: dataStorageService))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else if viewModel.timelineEvents.isEmpty {
                Text("No recent captures to display in timeline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 5) {
                        ForEach(viewModel.timelineEvents) { eventVM in
                            ScreenshotThumbnailView(
                                captureEvent: eventVM,
                                dataStorageService: dataStorageService,
                                height: 60
                            )
                            .onTapGesture {
                                print("Timeline item tapped: \(eventVM.timestamp) - \(eventVM.applicationName)")
                                // TODO: RAG context priming
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 30)
                }
                .frame(height: 100)
            }
        }
        .onAppear {
            viewModel.fetchRecentEventsForTimeline()
        }
        // TODO: refresh mechanism
    }
}

@MainActor
class ScreenshotTimelineViewModel: ObservableObject {
    @Published var timelineEvents: [CaptureEventViewModel] = []
    @Published var isLoading: Bool = false
    let dataStorageService: DataStorageService
    private var dateFormatter: DateFormatter

    private var fetchTask: Task<Void, Never>?

    init(dataStorageService: DataStorageService) {
        self.dataStorageService = dataStorageService
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm" // Concise format for timeline
        print("[ScreenshotTimelineViewModel] Initialized.")
    }

    func fetchRecentEventsForTimeline(limit: Int = 15) { // Reasonable number for horizontal preview
        fetchTask?.cancel() // Cancel any ongoing fetch
        fetchTask = Task {
            if isLoading { return } // Avoid concurrent fetches
            
            isLoading = true
            print("[ScreenshotTimelineViewModel] Fetching recent events for timeline (limit: \(limit))...")
            
            let events = await dataStorageService.fetchRecentEvents(limit: limit)
            if Task.isCancelled {
                print("[ScreenshotTimelineViewModel] Fetch task cancelled.")
                isLoading = false
                return
            }

            let viewModels = events.map { eventData -> CaptureEventViewModel in
                CaptureEventViewModel(
                    id: eventData.objectID, // Use the managed object ID
                    timestamp: eventData.timestamp != nil ? dateFormatter.string(from: eventData.timestamp!) : "Unknown Time",
                    applicationName: eventData.applicationName ?? "Unknown App",
                    ocrText: eventData.ocrText,
                    screenshotPath: eventData.screenshotPath
                )
            }
            
            // Events from fetchRecentEvents are already sorted descending (most recent first)
            self.timelineEvents = viewModels
            self.isLoading = false
            print("[ScreenshotTimelineViewModel] Timeline events updated. Count: \(self.timelineEvents.count)")
        }
    }
}

#Preview {
    let dataStorage = DataStorageService(inMemory: true)
    // Task {
    //    await dataStorage.saveCaptureEvent(timestamp: Date().addingTimeInterval(-100), ocrText: "Sample OCR 1", screenshotPath: nil, applicationName: "Preview App 1", bundleIdentifier: "com.preview1")
    //    await dataStorage.saveCaptureEvent(timestamp: Date(), ocrText: "Sample OCR 2", screenshotPath: nil, applicationName: "Preview App 2", bundleIdentifier: "com.preview2")
    // }
    return ScreenshotTimelinePreviewView(dataStorageService: dataStorage)
}
