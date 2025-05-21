//
//  ChatToolbarView.swift
//  amnesia
//

import SwiftUI

struct ChatToolbarView: View {
    @Bindable var vm: ChatViewModel

    var body: some View {
        if let errorMessage = vm.errorMessage {
            ErrorView(errorMessage: errorMessage)
        }

        if let progress = vm.modelDownloadProgress, !progress.isFinished {
            DownloadProgressView(progress: progress)
        }

        Button {
            vm.clear([.chat, .meta])
        } label: {
            Label("Clear Chat", systemImage: "trash")
        }
        .help("Clear chat history and generation info")

        GenerationInfoView(
            tokensPerSecond: vm.tokensPerSecond
        )
        .help("Tokens per second from last generation")
        
        Picker("Model", selection: $vm.selectedModel) {
            ForEach(MLXService.availableModels) { model in
                Text(model.displayName)
                    .tag(model)
            }
        }
        .help("Select Language Model")
    }
}
