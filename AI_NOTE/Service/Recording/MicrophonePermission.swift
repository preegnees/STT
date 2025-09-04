//
//  MicrophonePermission.swift
//  AI_NOTE
//
//  Created by Радмир on 04.09.2025.
//

import Foundation
import AVFoundation

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
