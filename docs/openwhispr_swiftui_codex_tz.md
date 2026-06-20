# ТЗ для Codex-агента: macOS SwiftUI rewrite минимального OpenWhispr-like диктовочного приложения

## Цель

Создать новый нативный macOS-проект на Swift / SwiftUI, вдохновлённый OpenWhispr, но без Electron, React, Node.js, подписок, аккаунтов, cloud sync, локальных LLM, meeting transcription, semantic notes и прочего лишнего функционала.

Нужен минимальный, быстрый, локальный macOS menu bar app для диктовки:

1. Пользователь нажимает глобальную горячую клавишу.
2. Приложение записывает голос с микрофона.
3. После отпускания клавиши или повторного нажатия запись останавливается.
4. Аудио отправляется в OpenAI transcription API.
5. Полученный текст вставляется в текущее активное приложение в позицию курсора.
6. Настройки доступны из menu bar.
7. API key хранится локально в macOS Keychain.
8. Никаких аккаунтов, подписок, серверной части, аналитики и телеметрии.

## Важное архитектурное решение

Не портировать существующий Electron/React-код построчно.

OpenWhispr использовать только как reference implementation для понимания поведения:

- global hotkey flow
- recording flow
- auto-paste flow
- settings UX
- edge cases
- naming of concepts

Новый проект должен быть самостоятельным macOS-native приложением.

## Технологии

Использовать:

- Swift
- SwiftUI
- AppKit interop там, где SwiftUI недостаточно
- AVFoundation для записи аудио
- Accessibility APIs / pasteboard / keyboard event simulation для вставки текста
- Keychain Services для хранения OpenAI API key
- URLSession для HTTP-запросов к OpenAI API
- UserDefaults для простых настроек
- Swift Package Manager, если нужны зависимости

Не использовать:

- Electron
- React
- TypeScript
- Node.js runtime
- Tailwind
- WebView UI
- Tauri
- Rust на первом этапе
- локальные модели
- whisper.cpp
- sherpa-onnx
- llama.cpp / llama-server
- qdrant
- cloud sync
- subscriptions
- accounts
- telemetry
- analytics

## Название проекта

Рабочее название: `OpenWhisprSwift` или `DictationBar`.

Создать новый Xcode/macOS project:

- Platform: macOS
- App type: SwiftUI App
- Deployment target: macOS 14+, желательно macOS 13+ если не усложняет
- App mode: Menu Bar app with optional Settings window

## Базовый UX

Приложение должно жить в menu bar.

Menu bar menu:

- Start Recording / Stop Recording
- Settings
- Last Transcript
- Copy Last Transcript
- Quit

Settings window:

- OpenAI API Key
- Transcription model
- Language setting: Auto / English / Russian / Custom
- Hotkey display
- Auto-paste toggle
- Copy to clipboard toggle
- Play sound on start/stop toggle
- Show floating recording indicator toggle
- Optional prompt / vocabulary hint field

## MVP-функции

### 1. Menu bar app

Реализовать menu bar app через SwiftUI `MenuBarExtra` или AppKit `NSStatusItem`, если нужен больший контроль.

Требования:

- app icon/status item always visible
- status changes during recording
- menu item changes from Start Recording to Stop Recording
- Quit works correctly

### 2. Permissions

При первом запуске приложение должно корректно запросить или объяснить необходимость:

- Microphone permission
- Accessibility permission, если auto-paste требует симуляции Cmd+V или работы с активным приложением

Если разрешения нет:

- не падать
- показывать понятное сообщение
- давать кнопку/инструкцию открыть System Settings

### 3. Audio recording

Создать `AudioRecorderService`.

Функции:

- `startRecording()`
- `stopRecording() async throws -> URL`
- `cancelRecording()`
- `isRecording state`

Записывать во временный файл.

Предпочтительный формат:

- m4a или wav
- формат должен быть совместим с OpenAI transcription API
- файл удалять после успешной отправки, если не включён debug режим

Важно:

- обработать отсутствие микрофона
- обработать отказ permission
- не блокировать main thread
- аккуратно очищать temp files

### 4. OpenAI transcription

Создать `OpenAITranscriptionService`.

Функции:

- `transcribe(audioFileURL: URL, settings: TranscriptionSettings) async throws -> String`

Настройки:

- apiKey
- model
- language optional
- prompt optional

По умолчанию использовать современную OpenAI speech-to-text модель. Название модели вынести в настройку, чтобы легко менять без изменения кода.

HTTP:

- использовать URLSession
- multipart/form-data upload
- нормальная обработка ошибок:
  - no API key
  - invalid API key
  - network error
  - rate limit
  - unsupported file
  - empty transcription

Не логировать API key.

### 5. Auto-paste into current app

Создать `TextInsertionService`.

MVP-реализация:

1. Сохранить текущий clipboard.
2. Положить transcript в clipboard.
3. Сымитировать Cmd+V через CGEvent.
4. Опционально восстановить старый clipboard через небольшую задержку.

Настройка:

- autoPaste: true/false
- copyToClipboard: true/false
- restorePreviousClipboard: true/false

Если Accessibility permission не выдан:

- fallback: только copy to clipboard
- показать понятную ошибку в menu/status

### 6. Global hotkey

Создать `GlobalHotkeyService`.

MVP:

- default hotkey: Control + Space или Option + Space
- режим: hold-to-record предпочтительно
- fallback: toggle recording, если hold mode сложно реализовать стабильно

Желаемое поведение:

- key down -> start recording
- key up -> stop recording, transcribe, paste
- повторное нажатие не должно создавать параллельные recordings
- во время обработки показывать статус `Transcribing...`

Если полноценная настройка hotkey займёт много времени, сделать default hotkey hardcoded и оставить TODO.

### 7. Floating indicator

Минимальный floating indicator:

- small borderless window / panel
- visible during recording
- visible during transcription with different text
- не перехватывает фокус
- не мешает активному приложению

Состояния:

- Idle
- Recording
- Transcribing
- Error
- Done

Можно реализовать через AppKit `NSPanel` + SwiftUI view.

### 8. Settings storage

Создать `AppSettings`.

Хранить в UserDefaults:

- selected model
- language
- autoPaste
- copyToClipboard
- restoreClipboard
- soundEnabled
- showFloatingIndicator
- prompt/vocabulary hint

API key хранить только в Keychain.

Создать `KeychainService`:

- `saveAPIKey(_:)`
- `loadAPIKey() -> String?`
- `deleteAPIKey()`

### 9. Error handling

Создать единый `AppError`.

Ошибки должны отображаться пользователю через:

- menu bar status
- settings screen
- optional notification

Не должно быть silent failures.

Обязательные кейсы:

- microphone permission denied
- accessibility permission denied
- missing API key
- OpenAI request failed
- transcription returned empty text
- recording too short
- network unavailable

### 10. Minimal transcript history

MVP optional, но желательно:

Хранить последние 20 транскриптов локально в UserDefaults или JSON-файле.

Поля:

- date
- text
- model
- duration optional

Не использовать SQLite на первом этапе, если нет необходимости.

## Структура проекта

Предложенная структура:

```text
DictationBar/
  DictationBarApp.swift
  AppState.swift

  Services/
    AudioRecorderService.swift
    OpenAITranscriptionService.swift
    TextInsertionService.swift
    GlobalHotkeyService.swift
    KeychainService.swift
    PermissionsService.swift
    TranscriptHistoryService.swift

  Models/
    AppSettings.swift
    TranscriptionSettings.swift
    TranscriptItem.swift
    AppError.swift
    RecordingState.swift

  Views/
    MenuBarView.swift
    SettingsView.swift
    FloatingIndicatorView.swift
    TranscriptHistoryView.swift

  Utilities/
    Logger.swift
    ClipboardSnapshot.swift
```

## Основной flow

Реализовать центральный `AppState` или `DictationController`.

Псевдологика:

```swift
func hotkeyDown() {
    guard !isRecording && !isTranscribing else { return }
    startRecording()
}

func hotkeyUp() {
    guard isRecording else { return }

    Task {
        do {
            let audioURL = try await recorder.stopRecording()
            state = .transcribing

            let text = try await openAI.transcribe(audioFileURL: audioURL, settings: settings)

            lastTranscript = text
            history.add(text)

            if settings.autoPaste {
                try await textInsertion.insert(text)
            } else if settings.copyToClipboard {
                textInsertion.copyToClipboard(text)
            }

            state = .done
        } catch {
            state = .error(error)
        }
    }
}
```

## Что взять из OpenWhispr

Изучить исходники OpenWhispr и выписать, как там сделаны:

- hotkey activation
- recording lifecycle
- paste into active app
- settings model
- transcription provider abstraction
- handling permissions
- UI states around recording/transcribing

Но не переносить:

- Electron IPC
- React components
- web UI structure
- subscription/account code
- local model downloaders
- meeting features
- notes/semantic search
- multi-provider complexity

## Что удалить / игнорировать из OpenWhispr

Полностью игнорировать в новом MVP:

- accounts
- subscriptions
- billing
- cloud sync
- Neon/Postgres
- Qdrant
- semantic search
- notes
- AI agents
- local LLM
- llama-server
- local Whisper / Parakeet
- model download managers
- meeting transcription
- diarization
- speaker identification
- React UI
- Electron preload bridge
- analytics/telemetry if present
- auto-updater for now

## Acceptance criteria

Проект считается рабочим MVP, если:

1. Приложение запускается как macOS menu bar app.
2. Можно ввести и сохранить OpenAI API key.
3. Можно нажать глобальную горячую клавишу.
4. Запись начинается и останавливается.
5. Аудиофайл отправляется в OpenAI transcription API.
6. Возвращённый текст появляется в текущем активном приложении.
7. Если auto-paste отключён, текст копируется в clipboard.
8. Ошибки отображаются понятно.
9. Приложение не требует Node.js/Electron.
10. Проект собирается в Xcode без ручных внешних шагов.
11. Нет аккаунтов, подписок, telemetry и серверной части.
12. Код разделён на сервисы, а не написан целиком в одном View.

## Development stages

### Stage 1: Project skeleton

- Создать новый SwiftUI macOS project.
- Добавить menu bar app.
- Добавить Settings window.
- Добавить AppState.
- Добавить UserDefaults settings.
- Добавить Keychain API key storage.

Результат: app opens, menu works, settings are saved.

### Stage 2: Recording

- Добавить microphone permission handling.
- Реализовать AVFoundation recording to temp file.
- Добавить Start/Stop Recording из menu bar.
- Показать recording state в UI.

Результат: можно записать аудиофайл и увидеть путь/debug info.

### Stage 3: OpenAI transcription

- Реализовать multipart upload.
- Добавить model/language/prompt settings.
- Отобразить last transcript в menu/settings.

Результат: записанный голос превращается в текст.

### Stage 4: Clipboard and paste

- Реализовать copy to clipboard.
- Реализовать Cmd+V simulation.
- Добавить Accessibility permission handling.
- Добавить auto-paste toggle.

Результат: текст вставляется в активное приложение.

### Stage 5: Global hotkey

- Добавить global hotkey.
- Реализовать hold-to-record или toggle mode.
- Защититься от race conditions.

Результат: app работает без открытия menu/settings.

### Stage 6: Floating indicator and polish

- Добавить floating recording/transcribing indicator.
- Добавить transcript history.
- Улучшить error messages.
- Очистить temp files.
- Добавить README.

Результат: приложение можно использовать ежедневно.

## Non-goals for MVP

Не делать в первой версии:

- Windows/Linux support
- Rust core
- local Whisper
- streaming realtime transcription
- subscriptions
- user accounts
- cloud sync
- meeting recorder
- diarization
- semantic notes
- auto-update
- notarization
- App Store packaging

## README для нового проекта

Создать README с разделами:

- What is this
- Why native Swift instead of Electron
- Requirements
- Setup
- OpenAI API key
- Permissions
- Hotkey
- Build from source
- Privacy
- Current limitations

В privacy явно написать:

- audio is sent only to OpenAI when using OpenAI transcription
- no telemetry
- no accounts
- API key is stored in Keychain
- transcripts are stored locally only if history is enabled

## Code quality requirements

- Использовать async/await.
- Не блокировать main thread.
- API key не логировать.
- Сервисы должны быть тестируемыми.
- UI не должен напрямую содержать HTTP/audio/clipboard логику.
- Все platform-specific вызовы изолировать в сервисах.
- Добавить понятные TODO только там, где реально следующий этап.
- Не добавлять тяжёлые зависимости без необходимости.

## First task for the agent

1. Clone/read the OpenWhispr repository only as reference.
2. Identify the minimal dictation flow in the original code.
3. Create a new SwiftUI macOS project from scratch.
4. Implement Stage 1 and Stage 2 first.
5. Do not attempt to port all features.
6. After Stage 2, report:
   - created files
   - build status
   - what works
   - what remains for Stage 3

## Additional hard constraint

Do not preserve compatibility with original OpenWhispr.

Do not build abstractions for multi-provider, local models, meetings, cloud sync, accounts, subscriptions, or semantic notes until a later explicit request.

The first product must be a small native macOS dictation utility.
