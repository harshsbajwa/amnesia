//
//  amnesiaApp.swift
//  amnesia
//

import SwiftUI

@main
struct amnesiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("Settings.")
                .frame(width: 300, height: 200)
        }
    }
}
