import SwiftUI
import CoreData

enum Tab: Int { case editor, summary, transcript }

struct DetailsView: View {
    @State private var selectedTab: Tab = .editor
    @State private var transcriptText: String = "Транскрипт пока пуст"
    @EnvironmentObject var svm: SidebarViewModel
    @StateObject private var summaryVM: SummaryViewModel
    
    init() {
        _summaryVM = StateObject(wrappedValue: SummaryViewModel(context: PersistenceController.shared.container.viewContext))
    }
    
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
    private func updateTranscriptText() {
        guard let note = svm.selectedNote else {
            transcriptText = "Нет выбранной заметки"
            return
        }
        
        let recordings = note.recordings?.allObjects as? [Recording] ?? []
        let activeRecordings = recordings.filter { $0.statusEnum != .failed }
        
        if activeRecordings.isEmpty {
            transcriptText = "Нет записей для этой заметки"
            return
        }
        
        var fullTranscript = ""
        
        for recording in activeRecordings {
            // Микрофонный транскрипт
            if let micTranscript = recording.micTranscript,
               let micText = micTranscript.fullText, !micText.isEmpty {
                fullTranscript += "🎤 Микрофон:\n"
                fullTranscript += micText + "\n\n"
            }
            
            // Системный транскрипт
            if let sysTranscript = recording.systemTranscript,
               let sysText = sysTranscript.fullText, !sysText.isEmpty {
                fullTranscript += "🔊 Системный звук:\n"
                fullTranscript += sysText + "\n\n"
            }
        }
        
        transcriptText = fullTranscript.isEmpty ? "Транскрипт пока пуст" : fullTranscript
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header с табами
            headerView
            
            Divider()
            
            // Содержимое вкладок
            tabContentView
        }
        .navigationTitle("")
        .onAppear {
            updateTranscriptText()
        }
        .onChange(of: svm.selectedNote) { _ in
            updateTranscriptText()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            // Обновляем транскрипт каждые 2 секунды при активной записи
            if selectedTab == .transcript {
                updateTranscriptText()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack(spacing: 10) {
            TextField("Название заметки", text: bindingTitle)
                .font(.title3)
                .textFieldStyle(.plain)
                .padding(.horizontal)
            
            Spacer()
            
            tabButtons
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
    
    private var tabButtons: some View {
        HStack(spacing: 8) {
            TabButton(
                tab: .editor,
                selectedTab: $selectedTab,
                systemName: "square.and.pencil",
                help: "Редактор"
            )
            
            TabButton(
                tab: .summary,
                selectedTab: $selectedTab,
                systemName: "doc.text.magnifyingglass",
                help: "Саммари"
            )
            
            TabButton(
                tab: .transcript,
                selectedTab: $selectedTab,
                systemName: "captions.bubble",
                help: "Транскрипт"
            )
        }
    }
    
    @ViewBuilder
    private var tabContentView: some View {
        switch selectedTab {
        case .editor:
            TextEditor(text: bindingContent)
                .font(.body)
                
        case .summary:
            SummaryTabView()
                .environmentObject(summaryVM)
                
        case .transcript:
            transcriptView
        }
    }
    
    private var transcriptView: some View {
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

// MARK: - TabButton

private struct TabButton: View {
    let tab: Tab
    @Binding var selectedTab: Tab
    let systemName: String
    let help: String
    
    private var isSelected: Bool {
        selectedTab == tab
    }
    
    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: systemName)
                .symbolVariant(isSelected ? .fill : .none)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

#Preview {
    ContentView()
}
