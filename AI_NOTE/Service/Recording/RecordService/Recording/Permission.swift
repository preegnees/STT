//
//  MicrophonePermission.swift
//  AI_NOTE
//
//  Created by Радмир on 04.09.2025.
//

import Foundation
import AVFoundation
import ScreenCaptureKit

enum MicrophonePermission: LocalizedError {
    case denied, restricted, undetermined

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Нет доступа к микрофону. Разрешите в Настройках → Конфиденциальность и безопасность → Микрофон."
        case .restricted:
            return "Доступ к микрофону ограничен системной политикой."
        case .undetermined:
            return "Не удалось запросить доступ к микрофону."
        }
    }
}

/// Просит/проверяет доступ к микрофону. Бросает понятную ошибку, если доступа нет.
func ensureMicrophonePermission() async throws {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    switch status {
    case .authorized:
        return
    case .notDetermined:
        let ok = await AVCaptureDevice.requestAccess(for: .audio)
        if ok { return } else { throw MicrophonePermission.denied }
    case .denied:
        // тут мы выбрасываем значение, а выше будем ловаить ошибку
        throw MicrophonePermission.denied
    case .restricted:
        throw MicrophonePermission.restricted
    @unknown default:
        throw MicrophonePermission.undetermined
    }
}

// Доступ для Системного аудио
@available(macOS 13.0, *)
enum SystemAudioPermission: LocalizedError {
    case denied, restricted, unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Нет доступа к записи системного звука. Разрешите в Настройках → Конфиденциальность и безопасность → Запись экрана."
        case .restricted:
            return "Доступ к записи системного звука ограничен системной политикой."
        case .unavailable:
            return "Запись системного звука недоступна на этой версии macOS."
        }
    }
}

/// Проверяет и запрашивает доступ к записи системного звука через ScreenCaptureKit
@available(macOS 13.0, *)
func ensureSystemAudioPermission() async throws {
    // Проверяем доступность ScreenCaptureKit
    guard #available(macOS 13.0, *) else {
        throw SystemAudioPermission.unavailable
    }
    
    do {
        // Попытка получить контент экрана покажет, есть ли доступ
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Если контент получен без ошибок, доступ есть
        if content.displays.isEmpty {
            throw SystemAudioPermission.restricted
        }
        
        // Дополнительная проверка: попробуем создать тестовый поток
        guard let display = content.displays.first else {
            throw SystemAudioPermission.restricted
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.width = 1
        config.height = 1
        
        // Если удалось создать поток, значит доступ есть
        let _ = SCStream(filter: filter, configuration: config, delegate: nil)
        
    } catch {
        // Если ошибка связана с отсутствием разрешений
        if error.localizedDescription.contains("not authorized") ||
           error.localizedDescription.contains("permission") {
            throw SystemAudioPermission.denied
        }
        
        // Другие ошибки считаем ограничением системы
        throw SystemAudioPermission.restricted
    }
}
