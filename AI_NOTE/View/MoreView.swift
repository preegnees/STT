//
//  MoreView.swift
//  AI_NOTE
//
//  Created by Радмир on 03.09.2025.
//

import SwiftUI

struct MoreView: View {
    var body: some View {
        Menu {
            Button("Настройки") {
                print("Открыть настройки")
            }
            Button("Справка") {
                print("Открыть справку")
            }
            Divider()
            Button("Выйти", role: .destructive) {
                print("Выход")
            }
        } label: {
            Label("", systemImage: "ellipsis.circle")
        }
    }
}
