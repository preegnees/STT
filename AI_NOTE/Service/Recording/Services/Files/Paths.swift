import Foundation

/*
 Тут создает папка сессии
 Изначально должна папка создаться, при ошибке должна удалиться
 */

// Как объект для передачи данных путей
struct SessionPaths {
    let root: URL
    let mic: URL
    let system: URL
}

// Сессии должны копироваться, поэтому можно сделать структурой
enum SessionFS {
    /// Создаёт уникальную папку сессии в Application Support, вместе с подпапками mic/ и system/.
    static func makeSessionFolder(bundleID: String? = Bundle.main.bundleIdentifier) throws -> SessionPaths {
        // 1) База: ~/Library/Application Support/<bundle-id>/sessions/
        let appSup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSup.appendingPathComponent(bundleID ?? "AI_NOTE", isDirectory: true)
        let sessions = appDir.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        // 2) Уникальное имя сессии
        let ts = timestamp()
        let short = UUID().uuidString.prefix(8)
        let name = "session_\(ts)_\(short)"
        var root = sessions.appendingPathComponent(name, isDirectory: true)

        // 3) Создаём корень и подпапки
        let mic = root.appendingPathComponent("mic", isDirectory: true)
        let system = root.appendingPathComponent("system", isDirectory: true)

        try FileManager.default.createDirectory(at: mic, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)

        // 4) (необязательно) исключаем из бэкапов iCloud/Time Machine
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? root.setResourceValues(rv)

        return SessionPaths(root: root, mic: mic, system: system)
    }

    /// Удаляет папку сессии рекурсивно (используй при откатах).
    static func removeSessionFolder(_ paths: SessionPaths) {
        try? FileManager.default.removeItem(at: paths.root)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }
}
