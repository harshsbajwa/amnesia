//
//  amnesiaApp.swift
//  amnesia
//

import SwiftUI

@main
struct amnesiaApp: App {
    var body: some Scene {
        WindowGroup {
            ChatView(viewModel: ChatViewModel(mlxService: MLXService()))
        }
    }
}
