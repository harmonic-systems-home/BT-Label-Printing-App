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
    @StateObject private var store = StoreManager()
    private let container = BTLabelApp.makeContainer()

    /// App Store numeric Apple ID, from App Store Connect → App Information →
    /// "Apple ID". Used for the Help → Rate BTLabel deep link.
    /// TODO: replace the placeholder with the real ID.
    static let appStoreID = "0000000000"

    /// Open the Mac App Store directly to BTLabel's write-a-review sheet.
    static func openWriteReview() {
        let s = "macappstore://apps.apple.com/app/id\(appStoreID)?action=write-review"
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 820, height: 560)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .help) {
                Button("BTLabel Help") { controller.showHelp = true }
                    .keyboardShortcut("?", modifiers: .command)
                Button("Rate BTLabel") { BTLabelApp.openWriteReview() }
            }
        }
    }

    /// Prefer a CloudKit-synced store; fall back to a local-only store if iCloud
    /// isn't fully configured yet (e.g. no container selected), so the app never
    /// crashes on launch.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([SavedLabelModel.self, AppSettings.self, FavoriteFolder.self])
        do {
            return try ModelContainer(for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic))
        } catch {
            return try! ModelContainer(for: schema,
                configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        }
    }
}
