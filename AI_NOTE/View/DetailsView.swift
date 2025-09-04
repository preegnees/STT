import SwiftUI

enum Tab: Int { case editor, summary, transcript }

struct DetailsView: View {
    @State private var selectedTab: Tab = .editor
    @State private var noteText = "Основной текст заметки..."
    @EnvironmentObject var svm: SidebarViewModel
    
    private var bindingTitle: Binding<String> {
        Binding (
            get: {
                svm.selectedNote?.title ?? ""
            },
            set: { newValue in
                guard let note = svm.selectedNote else { return }
                svm.updateNote(note) { note in
                    note.title = newValue
                }
            }
        )

    }
    
    private var bindingContent: Binding<String> {
        Binding (
            get: {
                svm.selectedNote?.content ?? ""
            },
            set: { newValue in
                guard let note = svm.selectedNote else { return }
                svm.updateNote(note) { note in
                    note.content = newValue
                }
            }
        )

    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Название заметки", text: bindingTitle)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .padding(.horizontal)
                
                Spacer()
                
                Button { selectedTab = .editor } label: {
                    Image(systemName: "square.and.pencil")
                        .symbolVariant(selectedTab == .editor ? .fill : .none)
                        .foregroundStyle(selectedTab == .editor ? .primary : .secondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == .editor ? Color.accentColor.opacity(0.12) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help("Редактор")
                
                Button { selectedTab = .summary } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .symbolVariant(selectedTab == .summary ? .fill : .none)
                        .foregroundStyle(selectedTab == .summary ? .primary : .secondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == .summary ? Color.accentColor.opacity(0.12) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help("Саммари")
                
                Button { selectedTab = .transcript } label: {
                    Image(systemName: "captions.bubble")
                        .symbolVariant(selectedTab == .transcript ? .fill : .none)
                        .foregroundStyle(selectedTab == .transcript ? .primary : .secondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == .transcript ? Color.accentColor.opacity(0.12) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help("Транскрипт")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            
            Divider()
            
            Group {
                switch selectedTab {
                case .editor:
                    TextEditor(text: bindingContent)
                        .font(.body)
                        
                case .summary:
                    VStack(spacing: 12) {
                        Text("Пока саммари нет")
                            .foregroundStyle(.secondary)
                        Button("Сделать саммари") {

                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .transcript:
                    ScrollView {
                        Text("Траскрипт")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.gray.opacity(0.1))
                            )
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("")
    }
}

#Preview {
    ContentView()
}
