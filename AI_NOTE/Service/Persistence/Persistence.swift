import CoreData

/// Контроллер Core Data для всего приложения (без превью и демо-данных)
struct PersistenceController {
    /// Один общий экземпляр на всё приложение
    static let shared = PersistenceController()

    /// Контейнер Core Data: модель + стор + контексты
    let container: NSPersistentContainer

    /// Инициализация стека Core Data
    init(inMemory: Bool = false) {
        // Имя ДОЛЖНО совпадать с названием твоей .xcdatamodeld (AI_NOTE.xcdatamodeld)
        container = NSPersistentContainer(name: "AI_NOTE")

        // Опционально: режим "только в памяти" (удобно для тестов, но не обязателен)
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Загружаем persistent store (создаёт/открывает AI_NOTE.sqlite)
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error: \(error), \(error.userInfo)")
            }
        }

        // Главный контекст автоматически подхватывает изменения из фона
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Политика слияния: локальные изменения в этом контексте главнее
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
