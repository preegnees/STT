//
//  ContentView.swift
//  AI_NOTE
//
//  Created by Радмир on 03.09.2025.
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) var managedObjectContext: NSManagedObjectContext
    @StateObject private var svm: SidebarViewModel
    @StateObject private var rvm: RecordViewModel
    
    init() {
        // Если managedObjectContext не прокинут из App, можно так:
        // _sidebarVM = StateObject(wrappedValue: SidebarViewModel(context: PersistenceController.shared.container.viewContext))
        // Но раз мы берём его из Environment, инициализируем позже:
        _svm = StateObject(wrappedValue: SidebarViewModel(context: PersistenceController.shared.container.viewContext))
        _rvm = StateObject(wrappedValue: RecordViewModel())
    }
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailsView()
                .toolbar {
                    ToolbarView()
                }
        }
        .environmentObject(svm) // Как вот это работает?
        .environmentObject(rvm)
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext,
                     PersistenceController.shared.container.viewContext)
}
