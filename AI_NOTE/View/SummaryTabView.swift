import SwiftUI

struct SummaryTabView: View {
    @EnvironmentObject var svm: SidebarViewModel
    @EnvironmentObject var summaryVM: SummaryViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            if let note = svm.selectedNote {
                switch summaryVM.getSummaryStatus(for: note) {
                case .idle:
                    EmptySummaryView()
                case .pending:
                    LoadingSummaryView()
                case .ready:
                    ReadySummaryView(summary: note.summary ?? "")
                case .failed:
                    FailedSummaryView()
                }
            } else {
                NoNoteSelectedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Subviews

private struct EmptySummaryView: View {
    @EnvironmentObject var svm: SidebarViewModel
    @EnvironmentObject var summaryVM: SummaryViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Саммари пока нет")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("Создайте краткое содержание ваших записей")
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            Button("Создать саммари") {
                if let note = svm.selectedNote {
                    summaryVM.generateSummary(for: note)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!summaryVM.canGenerateSummary(for: svm.selectedNote) || summaryVM.isGenerating)
            
            if !summaryVM.canGenerateSummary(for: svm.selectedNote) {
                Text("Нет готовых записей для создания саммари")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            if let error = summaryVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top)
            }
        }
    }
}

private struct LoadingSummaryView: View {
    @EnvironmentObject var svm: SidebarViewModel
    @EnvironmentObject var summaryVM: SummaryViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
            
            Text("Создаём саммари...")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text("Это может занять некоторое время")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Button("Отменить") {
                if let note = svm.selectedNote {
                    summaryVM.cancelGeneration(for: note)
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ReadySummaryView: View {
    @EnvironmentObject var svm: SidebarViewModel
    @EnvironmentObject var summaryVM: SummaryViewModel
    let summary: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Саммари")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Обновить") {
                    if let note = svm.selectedNote {
                        summaryVM.generateSummary(for: note)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(summaryVM.isGenerating)
            }
            
            ScrollView {
                Text(summary)
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
            }
            
            if let note = svm.selectedNote, let updatedAt = note.summaryUpdatedAt {
                Text("Обновлено: \(updatedAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let error = summaryVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct FailedSummaryView: View {
    @EnvironmentObject var svm: SidebarViewModel
    @EnvironmentObject var summaryVM: SummaryViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Ошибка создания саммари")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            if let error = summaryVM.errorMessage {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Попробовать снова") {
                if let note = svm.selectedNote {
                    summaryVM.generateSummary(for: note)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(summaryVM.isGenerating)
        }
    }
}

private struct NoNoteSelectedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Выберите заметку")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("Выберите заметку для просмотра или создания саммари")
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
