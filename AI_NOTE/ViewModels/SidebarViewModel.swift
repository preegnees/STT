//
//  SidbarViewModel.swift
//  AI_NOTE
//
//  Created by Радмир on 03.09.2025.
//

import CoreData
import SwiftUI

@MainActor
final class SidebarViewModel: NSObject, ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedNote: Note?
    
    
    private let context: NSManagedObjectContext // ссылка на контекст
    private let frc: NSFetchedResultsController<Note> // объект, который следит за изменениями в базе и уведомляет через делегат
    
    init(context: NSManagedObjectContext) {
        self.context = context
        
        // Тут мы готовим штуку для запросов, через фетч реквест, который был сгенерирован
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)
        ]
        
        self.frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        super.init()
        self.frc.delegate = self
        
        do {
            try frc.performFetch()
            self.notes = frc.fetchedObjects ?? []
        } catch {
            print("FRC fetch error:", error)
            self.notes = []
        }
        selectedNote = notes[0]
    }
    
    func newNote(title: String = "Без названия") {
        let note = Note(context: context)
        note.id = UUID()
        note.title = title
        note.content = ""
        let now = Date()
        note.createdAt = now
        note.updatedAt = now
        do {
            try context.save()
            selectedNote = note
        } catch {
                print("Save error:", error)
                context.rollback()
            }
    }
    
    func updateNote(_ note: Note, _ changes: (Note) -> Void) {
        guard !note.isDeleted else { return }
        let had = note.hasPersistentChangedValues
        changes(note)
        if note.hasPersistentChangedValues || !had { // было реальное изменение
           note.updatedAt = Date()
           do { try context.save() } catch { context.rollback() }
        }
    }
    
    func deleteNote(_ note: Note) {
        context.delete(note)
        do {
            try context.save()
        } catch {
            print("Save error:", error)
            context.rollback()
        }
    }
    
    // Внутри SidebarViewModel
    func addRandomNote() {
        let titles = [
            "Идея дня", "Быстрый набросок", "Мысль вслух",
            "Черновик заметки", "Что посмотреть", "Что почитать",
            "Эксперимент", "TODO", "Инсайт", "Задача"
        ]
        let bodies = [
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
            "Список дел: 1) … 2) … 3) …",
            "Наблюдение: производительность падает после 17:00.",
            "Гипотеза: стоит вынести парсинг в бэкграунд.",
            "Идея фичи: быстрый импорт из буфера обмена.",
            "Вопрос: как кэшировать ответы модели?",
            "Нужно проверить новую библиотеку.",
            "Шорткат: Cmd+N — создать заметку.",
            "План на завтра: …",
            "Заметка для теста интерфейса."
        ]

        let title = titles.randomElement() ?? "Random Note"
        let body  = bodies.randomElement() ?? "Random content"

        let note = Note(context: context)
        note.id = UUID()
        note.title = title
        note.content = body

        let now = Date()
        note.createdAt = now
        note.updatedAt = now

        do {
            try context.save()
        } catch {
            print("Save error:", error)
            context.rollback()
        }
    }

}

extension SidebarViewModel: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        // каждый раз, когда Core Data что-то изменила в выборке,
        // мы обновляем @Published notes
        self.notes = frc.fetchedObjects ?? []
       
        if let sel = selectedNote {
            // если выбранной уже нет в списке (удалена или исчезла из выборки) — выберем первую
            let stillThere = self.notes.contains { $0.id == sel.id }
            if !stillThere { selectedNote = self.notes.first }
        } else {
            // если вообще ничего не выбрано — выберем первую, если есть
            selectedNote = self.notes.first
        }
    }
}
