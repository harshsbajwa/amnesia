//
//  ChatView.swift
//  amnesia
//

import AVFoundation
import AVKit
import SwiftUI

struct NoLeadingArrowDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label // The custom label view
            if configuration.isExpanded {
                configuration.content // The content of the DisclosureGroup
            }
        }
    }
}

// Extracted System Prompt Section
struct SystemPromptSectionView: View {
    @Binding var isExpanded: Bool
    @Binding var editableSystemPrompt: String
    var vm: ChatViewModel
    // This now correctly expects the FocusState.Binding type
    var editorFocusStateBinding: FocusState<Bool>.Binding

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading) {
                Text("This instruction guides the AI model's behavior. Changes are saved automatically when you tap away or press Save.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                TextEditor(text: $editableSystemPrompt)
                    .frame(minHeight: 60, maxHeight: 150)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .cornerRadius(4)
                    .font(.system(.body, design: .monospaced))
                    // Use the passed-in FocusState.Binding directly
                    .focused(editorFocusStateBinding)
                    .onSubmit { // Triggered by Enter/Return key
                        if editableSystemPrompt != vm.currentModelInstruction {
                            vm.currentModelInstruction = editableSystemPrompt
                        }
                        // To change focus, assign to the wrappedValue of the FocusState.Binding
                        editorFocusStateBinding.wrappedValue = false
                    }

                HStack {
                    Spacer()
                    Button("Save") {
                        vm.currentModelInstruction = editableSystemPrompt
                        editorFocusStateBinding.wrappedValue = false // Dismiss focus
                        isExpanded = false // Collapse after save
                    }
                    .disabled(editableSystemPrompt == vm.currentModelInstruction)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 5)
        } label: {
            HStack {
                Text("System Prompt")
                    .font(.headline)
                Image(systemName: isExpanded ? "chevron.down.circle" : "chevron.right.circle")
                    .foregroundColor(.accentColor)
                Text("(Model Instructions)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal) // Ensure the label area is also padded
            .contentShape(Rectangle()) // Makes the entire HStack tappable
            .onTapGesture {
                withAnimation {
                   isExpanded.toggle()
                }
                if !isExpanded { // Logic after toggle (now collapsed)
                    editorFocusStateBinding.wrappedValue = false // Ensure focus is removed
                    if editableSystemPrompt != vm.currentModelInstruction { // Save if changed and collapsed
                        vm.currentModelInstruction = editableSystemPrompt
                    }
                } else { // Now expanded
                    editableSystemPrompt = vm.currentModelInstruction
                }
            }
        }
        .disclosureGroupStyle(NoLeadingArrowDisclosureGroupStyle())
        .padding(.vertical, 8)
    }
}


struct ChatView: View {
    @Bindable private var vm: ChatViewModel
    @EnvironmentObject var appDelegate: AppDelegate
    @FocusState private var isSystemPromptEditorFocused: Bool // The source of truth for focus

    @State private var showingScreenshotGallery = false
    private var dataStorageService: DataStorageService

    @State private var editableSystemPrompt: String
    @State private var isSystemPromptExpanded: Bool = false

    init(viewModel: ChatViewModel, dataStorageService: DataStorageService) {
        self.vm = viewModel
        self.dataStorageService = dataStorageService
        _editableSystemPrompt = State(initialValue: viewModel.currentModelInstruction)
    }

    // Extracted content of the main VStack
    @ViewBuilder
    private var chatContent: some View {
        ScreenshotTimelinePreviewView(dataStorageService: self.dataStorageService)
            .frame(height: 100)
            .padding(.bottom, 5)
        Divider()

        SystemPromptSectionView(
            isExpanded: $isSystemPromptExpanded,
            editableSystemPrompt: $editableSystemPrompt,
            vm: vm,
            // Pass the FocusState.Binding directly
            editorFocusStateBinding: $isSystemPromptEditorFocused
        )

        Divider()

        ConversationView(messages: vm.messages)

        Divider()

        if !vm.mediaSelection.isEmpty {
            MediaPreviewsView(mediaSelection: vm.mediaSelection)
        }

        PromptField(
            prompt: $vm.prompt,
            sendButtonAction: vm.generate,
            mediaButtonAction: vm.selectedModel.isVisionModel
                ? { vm.mediaSelection.isShowing = true }
                : nil
        )
        .padding()
    }
    
    // Extracted toolbar content
    @ToolbarContentBuilder
    private var chatToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ChatToolbarView(vm: vm)

            Button {
                showingScreenshotGallery = true
            } label: {
                Label("View All Captures", systemImage: "photo.stack")
            }
            .help("Open the full screenshot gallery")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatContent
            }
            .navigationTitle("Amnesia Chat")
            .toolbar {
                chatToolbarContent
            }
            .fileImporter(
                isPresented: $vm.mediaSelection.isShowing,
                allowedContentTypes: [.image, .movie],
                onCompletion: vm.addMedia
            )
            .onAppear {
                if editableSystemPrompt != vm.currentModelInstruction {
                    editableSystemPrompt = vm.currentModelInstruction
                }
            }
            .onChange(of: vm.currentModelInstruction) { _, newValue in
                 if editableSystemPrompt != newValue {
                     editableSystemPrompt = newValue
                 }
            }
            .sheet(isPresented: $showingScreenshotGallery) {
                ScreenshotGalleryView(dataStorageService: self.dataStorageService)
            }
        }
    }
}

// --- Previews ---
@MainActor
private func setupPreviewDependencies(sampleData: Bool = false) -> (ChatViewModel, DataStorageService, AppDelegate) {
    let dataStorage = DataStorageService(inMemory: true)
    let mlx = MLXService()
    let ocr = OCRService()
    let permissions = PermissionsManager()

    let chatViewModel = ChatViewModel(mlxService: mlx, dataStorageService: dataStorage)
    if sampleData {
        // This assumes SampleData.conversation includes a system message or that ChatViewModel handles it
        chatViewModel.messages = SampleData.conversation
        // Also update currentModelInstruction if SampleData changes the system prompt
        if let systemMsg = SampleData.conversation.first(where: { $0.role == .system }) {
            chatViewModel.currentModelInstruction = systemMsg.content
        }
    }

    let screenCapture = ScreenCaptureService(ocrService: ocr, dataStorageService: dataStorage)

    let previewAppDelegate = AppDelegate()
    previewAppDelegate.dataStorageService = dataStorage
    previewAppDelegate.ocrService = ocr
    previewAppDelegate.screenCaptureService = screenCapture
    previewAppDelegate.permissionsManager = permissions
    previewAppDelegate.chatViewModel = chatViewModel

    return (chatViewModel, dataStorage, previewAppDelegate)
}

#Preview("ChatView Default") {
    let (vm, dataService, appDelegate) = setupPreviewDependencies(sampleData: false)
    return ChatView(viewModel: vm, dataStorageService: dataService)
        .environmentObject(appDelegate)
        .frame(width: 500, height: 700)
}

#Preview("ChatView With Sample Data") {
    let (vm, dataService, appDelegate) = setupPreviewDependencies(sampleData: true)
    return ChatView(viewModel: vm, dataStorageService: dataService)
        .environmentObject(appDelegate)
        .frame(width: 500, height: 700)
}
