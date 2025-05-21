//
//  ChatViewModel.swift
//  amnesia
//

import Foundation
import MLXLMCommon
import UniformTypeIdentifiers
import Combine

@Observable
@MainActor
class ChatViewModel {
    private let mlxService: MLXService
    private let dataStorageService: DataStorageService

    var prompt: String = ""
    var messages: [Message] = []
    var selectedModel: LMModel = MLXService.availableModels.first!
    var mediaSelection = MediaSelection()
    var isGenerating = false
    private var generateTask: Task<Void, any Error>?
    private var generateCompletionInfo: GenerateCompletionInfo?

    var currentModelInstruction: String

    var tokensPerSecond: Double {
        generateCompletionInfo?.tokensPerSecond ?? 0
    }

    var modelDownloadProgress: Progress? {
        mlxService.modelDownloadProgress
    }

    var errorMessage: String?

    init(mlxService: MLXService, dataStorageService: DataStorageService) {
        self.mlxService = mlxService
        self.dataStorageService = dataStorageService

        let defaultSystemPrompt = "You are a helpful assistant. Users will provide queries, and sometimes, preceding their query, a section of recent screen context will be provided for your awareness. Use this screen context to inform your response if it is relevant to the user's query. Do not explicitly state that you are using recalled context unless the user asks about memory or context. Focus on answering the user's query directly."

        // 1. Initialize currentModelInstruction first, potentially with a default.
        //    We can't access self.messages yet.
        //    For now, let's assume messages is empty or we set a default.
        //    If messages were loaded from persistence *before* this init, that's a different pattern.
        //    Given the current structure, we'll set a default for currentModelInstruction
        //    and then adjust `messages` based on it.

        // Check if `messages` (which is already initialized to []) contains a system message.
        // This part is tricky because `messages` might be populated by a persistence layer
        // *outside* this init, or it might just be its default empty array.
        // For robustness, let's try to find it, but have a fallback.
        
        var _: String?
        // Since `messages` could be modified by other parts (e.g. loading from disk)
        // it's better to initialize `currentModelInstruction` without relying on `self.messages`
        // and then reconcile `self.messages` *after* all stored properties are set.

        // Initialize all stored properties first
        self.currentModelInstruction = defaultSystemPrompt // Initialize with default

        // Now that all stored properties are initialized, we can safely use `self`
        if let existingSystemMessage = self.messages.first(where: { $0.role == .system }) {
            // If messages somehow already had a system message (e.g. loaded externally before init), use it.
            self.currentModelInstruction = existingSystemMessage.content
        } else {
            // Otherwise, ensure the messages array starts with the currentModelInstruction (which is defaultSystemPrompt here)
            if self.messages.isEmpty {
                self.messages.append(.system(self.currentModelInstruction))
            } else {
                // If messages exist but no system prompt, remove any other system prompts and add ours at the start.
                self.messages.removeAll { $0.role == .system }
                self.messages.insert(.system(self.currentModelInstruction), at: 0)
            }
        }
    }

    private func buildContextPreamble() async -> String {
        let recentEvents = await dataStorageService.fetchRecentEvents(limit: 5)

        guard !recentEvents.isEmpty else { return "" }

        var contextText = ""
        for event in recentEvents.reversed() { // Reversed to show oldest first in context block
            let appName = event.applicationName ?? "Unknown App"
            let ocr = event.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200) ?? "No text captured"
            let eventTime = event.timestamp?.formatted(date: .omitted, time: .shortened) ?? "Unknown time"
            contextText += "[\(eventTime) - \(appName)]: \(ocr)\n...\n"
        }
        return contextText
    }

    func generate() async {
        if let existingTask = generateTask {
            existingTask.cancel()
            generateTask = nil
        }

        isGenerating = true
        errorMessage = nil

        let userTypedPrompt = self.prompt
        let mediaForUserMessage = mediaSelection


        messages.append(.user(userTypedPrompt, images: mediaForUserMessage.images, videos: mediaForUserMessage.videos))


        clear(.prompt) // Clear input field and media selection

        var messagesForLLM: [Message] = []

        // 1. Add the current system instruction
        messagesForLLM.append(.system(self.currentModelInstruction))

        // 2. Add relevant history
        if messages.count > 2 {
            let history = messages.dropFirst().dropLast()
            messagesForLLM.append(contentsOf: history)
        }

        // 3. Construct and add the final user message with context
        let contextPreamble = await buildContextPreamble()
        var finalUserPromptContent = ""

        if !contextPreamble.isEmpty {
            finalUserPromptContent += "Relevant Screen Context (for your awareness, most recent is last):\n---\n"
            finalUserPromptContent += contextPreamble
            finalUserPromptContent += "---\nUser Query:\n"
        }
        finalUserPromptContent += userTypedPrompt

        messagesForLLM.append(.user(finalUserPromptContent, images: mediaForUserMessage.images, videos: mediaForUserMessage.videos))


        // Prepare for assistant's response in UI
        let assistantMessageIndexInUI = messages.count
        messages.append(.assistant(""))


        generateTask = Task {
            var accumulatedResponse = ""
            var finalInfo: GenerateCompletionInfo?

            do {
                for await generation in try await mlxService.generate(
                    messages: messagesForLLM,
                    model: selectedModel)
                {
                    switch generation {
                    case .chunk(let chunk):
                        accumulatedResponse += chunk
                        if messages.indices.contains(assistantMessageIndexInUI) {
                            messages[assistantMessageIndexInUI].content = accumulatedResponse
                        }
                    case .info(let info):
                        finalInfo = info
                    }
                }
                if let finalInfo = finalInfo {
                    generateCompletionInfo = finalInfo
                }

            } catch {
                 Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                    if messages.indices.contains(assistantMessageIndexInUI) {
                        if messages[assistantMessageIndexInUI].content.isEmpty {
                            messages[assistantMessageIndexInUI].content = "[Error: \(error.localizedDescription)]"
                        } else {
                            messages[assistantMessageIndexInUI].content += "\n[Error: \(error.localizedDescription)]"
                        }
                    } else {
                         self.messages.append(.assistant("[Error: \(error.localizedDescription)]"))
                    }
                 }
            }
        }

        do {
            try await withTaskCancellationHandler {
                try await generateTask?.value
            } onCancel: {
                Task { @MainActor in
                    generateTask?.cancel()
                    if self.messages.indices.contains(assistantMessageIndexInUI) {
                         if self.messages[assistantMessageIndexInUI].content.isEmpty {
                            self.messages[assistantMessageIndexInUI].content = "[Cancelled]"
                         } else if !self.messages[assistantMessageIndexInUI].content.contains("[Cancelled]") {
                            self.messages[assistantMessageIndexInUI].content += "\n[Cancelled]"
                         }
                    }
                }
            }
        } catch {
            // Error is handled inside the Task
        }

        isGenerating = false
        generateTask = nil
    }

    func addMedia(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            if let mediaType = UTType(filenameExtension: url.pathExtension) {
                if mediaType.conforms(to: .image) {
                    mediaSelection.images = [url]
                } else if mediaType.conforms(to: .movie) {
                    mediaSelection.videos = [url]
                }
            }
        } catch {
            errorMessage = "Failed to load media item.\n\nError: \(error)"
        }
    }

    func clear(_ options: ClearOption) {
        if options.contains(.prompt) {
            prompt = ""
            mediaSelection = .init()
        }

        if options.contains(.chat) {
            messages = [.system(self.currentModelInstruction)]
            generateTask?.cancel()
        }

        if options.contains(.meta) {
            generateCompletionInfo = nil
        }
        errorMessage = nil
    }
}


@Observable
class MediaSelection {
    var isShowing = false
    var images: [URL] = []
    var videos: [URL] = []
    var isEmpty: Bool {
        images.isEmpty && videos.isEmpty
    }
}


struct ClearOption: RawRepresentable, OptionSet {
    let rawValue: Int

    static let prompt = ClearOption(rawValue: 1 << 0)
    static let chat = ClearOption(rawValue: 1 << 1)
    static let meta = ClearOption(rawValue: 1 << 2)

    static let allChatData: ClearOption = [.prompt, .chat, .meta]
}
