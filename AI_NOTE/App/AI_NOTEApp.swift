//
//  AI_NOTEApp.swift
//  AI_NOTE
//
//  Created by Радмир on 03.09.2025.
//

import SwiftUI

@main
struct AI_NOTEApp: App {
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
