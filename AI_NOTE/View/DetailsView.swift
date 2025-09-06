import SwiftUI
import CoreData

enum Tab: Int { case editor, summary, transcript }

struct DetailsView: View {
    @State private var selectedTab: Tab = .editor
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
    
    // Получаем весь транскрипт из всех записей заметки
    private var transcriptText: String {
        guard let note = svm.selectedNote else { return "Нет выбранной заметки" }
        
        let recordings = note.recordings?.allObjects as? [Recording] ?? []
        let activeRecordings = recordings.filter { $0.statusEnum != .failed }
        
        if activeRecordings.isEmpty {
            return "Нет записей для этой заметки"
        }
        
        var fullTranscript = ""
        
        for recording in activeRecordings {
            // Микрофонный транскрипт
            if let micTranscript = recording.micTranscript,
               let micText = micTranscript.fullText, !micText.isEmpty {
                fullTranscript += "🎤 Микрофон:\n"
                fullTranscript += micText + "\n\n"
            }
            
//            // Системный транскрипт
//            if let sysTranscript = recording.systemTranscript, !sysTranscript.fullText.isEmpty {
//                fullTranscript += "🔊 Системный звук:\n"
//                fullTranscript += sysTranscript.fullText + "\n\n"
//            }
        }
        
        return fullTranscript.isEmpty ? "Транскрипт пока пуст" : fullTranscript
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
                            // TODO: Implement summary generation
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                case .transcript:
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(transcriptText)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(NSColor.textBackgroundColor))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                    .id("transcriptContent")
                            }
                            .padding()
                        }
                        .onChange(of: transcriptText) { _ in
                            // Автоскролл к низу при обновлении транскрипта
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("transcriptContent", anchor: .bottom)
                            }
                        }
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
