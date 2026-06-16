//
//  NudgeApp.swift
//  Nudge
//
//  Created by sunkwon on 6/16/26.
//

import SwiftUI

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
