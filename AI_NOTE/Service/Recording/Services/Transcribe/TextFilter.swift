import Foundation

/// Простая фильтрация «мусора» из распознавания.
enum TextFilter {

    /// Лёгкая очистка для вывода в transcript:
    /// убираем служебные токены Whisper, сжимаем пробелы и обрезаем края.
    static func sanitize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"<\|[^>]*\|>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
             .trimmingCharacters(in: .whitespacesAndNewlines)
        return t
    }

    /// Нормализация для проверок (строже, чем sanitize).
    private static func norm(_ s: String) -> String {
        var t = s
            .replacingOccurrences(of: #"<\|[^>]*\|>"#, with: "", options: .regularExpression)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
        t = t.replacingOccurrences(of: "ё", with: "е")
        // пунктуацию/символы → пробел (чтобы «угу,» и «угу» считались одинаково)
        t = t.replacingOccurrences(of: #"[\p{P}\p{S}]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t
    }

    /// Жёстко отбрасываемые подстроки (после norm) - ИСПРАВЛЕНО: убраны точки и приведено к нижнему регистру
    private static let bannedContains: [String] = [
        // служебные/шапки/хвосты/неинформативные
        "продолжение следует", "при поддержке", "спасибо за просмотр",
        "подписывайтесь", "подпишитесь", "ставьте лайк", "колокольчик",
        "ссылка в описании", "наш канал", "заставка", "спасибо",
        // шумы
        "музыка", "аплодисменты", "смех", "шум",
        // субтитровые кредиты - ИСПРАВЛЕНО: используем более гибкие варианты
        "субтитры создал", "субтитры создавал", "субтитры подогнал",
        "редактор субтитров", "корректор",
        // англ. маркеры, если вдруг всплыли
        "music", "applause", "laughter", "credits"
    ]

    /// Регексы (после norm) - ДОБАВЛЕНЫ новые паттерны
    private static let bannedPatterns: [NSRegularExpression] = {
        let raw = [
            // квадратные теги целиком в строке: [музыка], [music], [аплодисменты] и т.п.
            #"^\s*\[(music|applause|laughter|silence|noise|музыка|аплодисменты|смех|тишина|шум)\]\s*$"#,
            // упоминания «субтитровых» ролей - РАСШИРЕНО
            #"\bсубтитры\b.*\b(создал|создавал|подогнал|подогнала|подогнали|сделал|сделала|сделали)\b"#,
            #"\b(редактор|корректор)\b.*\b(субтитров|перевода)\b"#,
            // НОВОЕ: паттерн для "Субтитры сделал [любое имя]"
            #"субтитры\s+(сделал|создал|подготовил)\s+\w+"#,
            // строка — только междометие/слово-паразит (не более 1–3 слов)
            #"^(э+|ээ+|м+|мм+|а+|у+|угу|ага|ну|вот|типа|как бы|короче|значит|это самое)(\s+(э+|мм+|ну|типа|вот|ага|угу))?$"#,
            // только цифры/таймкоды
            #"^\d+([:.,]\d+)*$"#,
            // НОВОЕ: "Продолжение следует" с любыми знаками
            #"продолжение\s+следует"#,
            // НОВОЕ: просто "спасибо" в любом виде
            #"^спасибо\s*$"#
        ]
        return raw.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    /// Главная проверка: решаем, писать ли строку в transcript.
    static func shouldDrop(_ original: String) -> Bool {
        // быстрые тривиальные фильтры
        let cleaned = original.replacingOccurrences(of: #"<\|[^>]*\|>"#, with: "", options: .regularExpression)
                              .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return true }

        // нормализуем
        let t = norm(cleaned)
        if t.isEmpty { return true }
        // нет букв/цифр
        if t.range(of: #"[a-zа-я0-9]"#, options: .regularExpression) == nil { return true }
        // слишком коротко (1–2 символа «мм», «э», «а»)
        if t.count <= 2 { return true }

        // подстроки - ИСПРАВЛЕНО: теперь проверяем нормализованный текст
        if bannedContains.contains(where: { t.contains($0) }) { return true }

        // паттерны
        for re in bannedPatterns {
            if re.firstMatch(in: t, options: [], range: NSRange(t.startIndex..., in: t)) != nil {
                return true
            }
        }

        return false
    }
}
