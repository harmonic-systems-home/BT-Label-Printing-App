//
//  BTLabelApp.swift
//  BTLabel
//
//  Created by Rick Wilson on 6/8/26.
//

import SwiftUI
import SwiftData

@main
struct BTLabelApp: App {
    @StateObject private var controller = PrinterController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 820, height: 560)
        // Local persistence now; automatically CloudKit-synced once the iCloud
        // capability is added in Xcode (the model is CloudKit-compatible).
        .modelContainer(for: SavedLabelModel.self)
    }
}
