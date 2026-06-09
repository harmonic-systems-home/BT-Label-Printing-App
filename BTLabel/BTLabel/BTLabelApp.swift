//
//  BTLabelApp.swift
//  BTLabel
//
//  Created by Rick Wilson on 6/8/26.
//

import SwiftUI

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
    }
}
