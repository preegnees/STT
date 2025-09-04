import SwiftUI
import CoreData

struct SidebarView: View {
    @EnvironmentObject var svm: SidebarViewModel

    var body: some View {
        List {
            ForEach(svm.notes, id: \.objectID) { note in
                let selected = (svm.selectedNote?.objectID == note.objectID)

                Text(note.title ?? "Без названия")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading) // растянуть контент
                    .contentShape(Rectangle())                        // кликабельна вся строка
                    .onTapGesture { svm.selectedNote = note }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { svm.deleteNote(note) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .listRowBackground(                               // ← фон ДЛЯ СТРОКИ
                        selected ? Color.accentColor.opacity(0.12) : Color.clear
                    )
                    // (опционально) поджать внутренние отступы строки
                    //.listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }
        }
        .listStyle(.inset) // или .sidebar, если хочешь классический сайдбар
        .navigationTitle("Заметки")
    }
}
