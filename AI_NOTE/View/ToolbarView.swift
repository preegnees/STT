//
//  ToolbarView.swift
//  AI_NOTE
//
//  Created by Радмир on 03.09.2025.
//

import SwiftUI

struct ToolbarView: ToolbarContent {
    @EnvironmentObject var svm: SidebarViewModel
    @EnvironmentObject var rvm: RecordViewModel
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                svm.newNote()
            } label: {
                Image(systemName: "note.text.badge.plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        ToolbarItem(placement: .navigation) {
            Button {
                switch rvm.status {
                case .idle:
                    if let note = svm.selectedNote {
                        rvm.start(note: note)
                    } else {
                        // нет выбранной заметки — создаём новую
                        svm.newNote()
                        // если newNote() сразу выставляет selectedNote,
                        // можно попробовать стартануть ещё раз (без ожиданий):
                        if let note = svm.selectedNote {
                            rvm.start(note: note)
                        }
                    }
                case .recording:
                    rvm.stop()
                case .loading:
                    break
                }
            } label: {
                if rvm.status == .loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: rvm.status.iconName)
                        .foregroundColor(rvm.status.iconColor)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(rvm.status == .loading)   
        }
        
        ToolbarItem(placement: .primaryAction) {
            MoreView()
        }
    }
}

#Preview {
    ContentView() // у вас внутри уже подключён ToolbarView
}
