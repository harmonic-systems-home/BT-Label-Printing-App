//
//  BTLabelApp.swift
//  BTLabel
//
//  Created by Rick Wilson on 6/8/26.
//

import SwiftUI
import SwiftData
import AppKit

/// Quit the app when its window is closed (single-window utility).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

@main
struct BTLabelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = PrinterController()
    private let container = BTLabelApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 820, height: 560)
        .modelContainer(container)
    }

    /// Prefer a CloudKit-synced store; fall back to a local-only store if iCloud
    /// isn't fully configured yet (e.g. no container selected), so the app never
    /// crashes on launch.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([SavedLabelModel.self, AppSettings.self])
        do {
            return try ModelContainer(for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
        } catch {
            return try! ModelContainer(for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        }
    }
}
