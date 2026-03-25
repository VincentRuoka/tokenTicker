// Sources/tokenTicker/tokenTickerApp.swift
import SwiftUI

@main
struct tokenTickerApp: App {
    // @State private var appState = AppState()  // wired in Task 3

    var body: some Scene {
        MenuBarExtra("tokenTicker", systemImage: "circle.dotted") {
            Text("Loading...")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
