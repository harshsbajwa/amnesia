//
//  DataStorageService.swift
//  amnesia
//

import Foundation
import CoreData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

actor DataStorageService {
    private let persistentContainer: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext

    init(inMemory: Bool = false) {
        persistentContainer = NSPersistentContainer(name: "Amnesia")

        if inMemory {
            persistentContainer.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
            print("[DataStorageService] Initialized in-memory data store.")
        } else {
            let storeURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("Amnesia.sqlite")
            let description = NSPersistentStoreDescription(url: storeURL)
            // description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
            persistentContainer.persistentStoreDescriptions = [description]
            print("[DataStorageService] SQLite store URL: \(storeURL.path)")
        }

        persistentContainer.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("[DataStorageService] Unresolved error loading persistent stores: \(error), \(error.userInfo)")
            }
            print("[DataStorageService] Persistent store loaded successfully: \(storeDescription.url?.path ?? "In-memory")")
        }

        backgroundContext = persistentContainer.newBackgroundContext()
        backgroundContext.automaticallyMergesChangesFromParent = true
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        print("[DataStorageService] Background context initialized and configured to merge changes.")
    }

    private func applicationSupportDirectory() -> URL {
        let appName = Bundle.main.bundleIdentifier ?? "com.unknown.amnesia"
        // Ensure Application Support directory exists
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(appName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: appSupportDir.path) {
            do {
                try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true, attributes: nil)
                print("[DataStorageService] Created application support directory at: \(appSupportDir.path)")
            } catch {
                // This is a critical failure for saving screenshots.
                print("[DataStorageService] CRITICAL: Could not create application support directory: \(error). Screenshots may fail to save.")
                // TODO: throw or handle this more gracefully.
            }
        }
        return appSupportDir
    }

    func saveScreenshot(_ image: CGImage, timestamp: Date) -> String? {
        let dirPath = applicationSupportDirectory().appendingPathComponent("Screenshots", isDirectory: true)
        do {
            // Ensure the "Screenshots" subdirectory exists
            if !FileManager.default.fileExists(atPath: dirPath.path) {
                try FileManager.default.createDirectory(at: dirPath, withIntermediateDirectories: true, attributes: nil)
                print("[DataStorageService] Created Screenshots directory at: \(dirPath.path)")
            }

            let fileNameFormatter = DateFormatter()
            fileNameFormatter.dateFormat = "yyyyMMdd_HHmmss_SSS'.png'" // Ensure unique filenames with milliseconds
            let fileName = fileNameFormatter.string(from: timestamp)
            
            let fileURL = dirPath.appendingPathComponent(fileName)

            guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                print("[DataStorageService] Failed to create CGImageDestination for URL: \(fileURL)")
                return nil
            }
            // TODO: kCGImageDestinationLossyCompressionQuality
            CGImageDestinationAddImage(destination, image, nil)
            
            guard CGImageDestinationFinalize(destination) else {
                print("[DataStorageService] Failed to finalize CGImageDestination for URL: \(fileURL)")
                // Attempt to remove partially written file if finalization fails
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            let relativePath = "Screenshots/\(fileName)"
            print("[DataStorageService] Screenshot saved successfully to: \(relativePath)")
            return relativePath
        } catch {
            print("[DataStorageService] Error saving screenshot to \(dirPath.path): \(error)")
            return nil
        }
    }

    func saveCaptureEvent(timestamp: Date, ocrText: String?, screenshotPath: String?, applicationName: String?, bundleIdentifier: String?) async {
        // This method runs on the backgroundContext's queue due to await backgroundContext.perform
        await backgroundContext.perform {
            print("[DataStorageService] Attempting to save capture event. Timestamp: \(timestamp), App: \(applicationName ?? "N/A")")
            let newEvent = CaptureEvent(context: self.backgroundContext)
            newEvent.timestamp = timestamp
            newEvent.ocrText = ocrText?.isEmpty == false ? ocrText : nil // Store nil if OCR text is empty
            newEvent.screenshotPath = screenshotPath
            newEvent.applicationName = applicationName
            newEvent.bundleIdentifier = bundleIdentifier

            do {
                if self.backgroundContext.hasChanges {
                    try self.backgroundContext.save()
                    print("[DataStorageService] Capture event saved successfully. App: \(applicationName ?? "N/A"), Timestamp: \(timestamp)")
                } else {
                    print("[DataStorageService] No changes to save for capture event. App: \(applicationName ?? "N/A")")
                }
            } catch {
                // Detailed error logging
                let nsError = error as NSError
                print("[DataStorageService] Failed to save capture event: \(nsError.localizedDescription). Code: \(nsError.code). UserInfo: \(nsError.userInfo). Event details - App: \(applicationName ?? "N/A"), Timestamp: \(timestamp)")
                // Rollback if save fails catastrophically
                self.backgroundContext.rollback()
            }
        }
    }

    func fetchRecentEvents(limit: Int) async -> [CaptureEvent] {
        // This method runs on the backgroundContext's queue
        await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<CaptureEvent> = CaptureEvent.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CaptureEvent.timestamp, ascending: false)]
            if limit > 0 { // A limit of 0 means fetch all
                 fetchRequest.fetchLimit = limit
            }
            do {
                let events = try self.backgroundContext.fetch(fetchRequest)
                print("[DataStorageService] Fetched \(events.count) recent events (limit: \(limit == 0 ? "all" : String(limit))).")
                return events
            } catch {
                print("[DataStorageService] Failed to fetch recent events: \(error.localizedDescription)")
                return []
            }
        }
    }

    func fetchEvents(containingKeywords keywords: [String]) async -> [CaptureEvent] {
        guard !keywords.isEmpty else {
            print("[DataStorageService] Fetch events by keywords called with empty keywords array.")
            return []
        }
        
        return await backgroundContext.perform {
            let fetchRequest: NSFetchRequest<CaptureEvent> = CaptureEvent.fetchRequest()

            var predicates = [NSPredicate]()
            for keyword in keywords where !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Using [cd] for case and diacritic insensitive search
                predicates.append(NSPredicate(format: "ocrText CONTAINS[cd] %@", keyword))
            }
            
            guard !predicates.isEmpty else {
                print("[DataStorageService] No valid keywords provided for search after trimming.")
                return []
            }

            fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CaptureEvent.timestamp, ascending: false)] // Most recent first

            do {
                let events = try self.backgroundContext.fetch(fetchRequest)
                print("[DataStorageService] Fetched \(events.count) events for keywords: \(keywords.joined(separator: ", "))")
                return events
            } catch {
                print("[DataStorageService] Failed to fetch events by keywords: \(error.localizedDescription)")
                return []
            }
        }
    }

    func getFullScreenshotURL(relativePath: String?) -> URL? {
        guard let relativePath = relativePath, !relativePath.isEmpty else {
            // print("[DataStorageService] Attempted to get full URL for nil or empty relative path.")
            return nil
        }
        guard !relativePath.contains("..") else {
            print("[DataStorageService] Invalid relative path (contains '..'): \(relativePath)")
            return nil
        }
        
        let fullUrl = applicationSupportDirectory().appendingPathComponent(relativePath)
        // print("[DataStorageService] Constructed full screenshot URL: \(fullUrl.path)")
        return fullUrl
    }

    // TODO: func cleanupOldData(olderThan date: Date) async { ... }
}
