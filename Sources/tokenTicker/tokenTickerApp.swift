// Sources/tokenTicker/tokenTickerApp.swift
import SwiftUI

@main
struct tokenTickerApp: App {
    var body: some Scene {
        MenuBarExtra("tokenTicker", systemImage: "circle.dotted") {
            Text("Loading...")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
