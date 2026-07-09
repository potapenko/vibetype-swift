//
//  EmojiCommandSet.swift
//  HoldType
//
//  Created by Codex on 7/7/26.
//

import Foundation

public struct EmojiCommandAlias: Equatable, Identifiable, Sendable {
    public let spokenPhrase: String
    public let replacement: String

    public init(spokenPhrase: String, replacement: String) {
        self.spokenPhrase = spokenPhrase
        self.replacement = replacement
    }

    public var id: String {
        "\(spokenPhrase)|\(replacement)"
    }
}

public struct EmojiCommand: Equatable, Identifiable, Sendable {
    public let id: String
    public let emoji: String
    public let displayName: String
    public let aliases: [String]

    public init(id: String, emoji: String, displayName: String, aliases: [String]) {
        self.id = id
        self.emoji = emoji
        self.displayName = displayName
        self.aliases = Self.normalizedSpokenPhrases(aliases)
    }

    public var primarySpokenPhrase: String {
        aliases.first ?? ""
    }

    public var secondarySpokenPhrases: [String] {
        Array(aliases.dropFirst())
    }

    public var replacementAliases: [EmojiCommandAlias] {
        aliases.map { EmojiCommandAlias(spokenPhrase: $0, replacement: emoji) }
    }

    public var promptHints: [String] {
        Array(aliases.prefix(3))
    }

    public static func normalizedSpokenPhrase(_ phrase: String) -> String {
        phrase
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public static func normalizedSpokenPhrases(_ phrases: [String]) -> [String] {
        var normalizedPhrases: [String] = []
        var seenKeys = Set<String>()

        for phrase in phrases {
            let normalizedPhrase = normalizedSpokenPhrase(phrase)
            guard !normalizedPhrase.isEmpty else {
                continue
            }

            let key = normalizedPhrase.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            )
            guard !seenKeys.contains(key) else {
                continue
            }

            seenKeys.insert(key)
            normalizedPhrases.append(normalizedPhrase)
        }

        return normalizedPhrases
    }
}

public struct CustomEmojiCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var emoji: String
    public var command: String
    public var aliases: [String]
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        emoji: String,
        command: String,
        aliases: [String] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.emoji = emoji
        self.command = command
        self.aliases = aliases
        self.isEnabled = isEnabled
    }

    public var normalizedEmoji: String {
        emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedSpokenPhrases: [String] {
        EmojiCommand.normalizedSpokenPhrases([command] + aliases)
    }

    public var displayCommand: String {
        normalizedSpokenPhrases.first ?? EmojiCommand.normalizedSpokenPhrase(command)
    }

    public var replacementAliases: [EmojiCommandAlias] {
        normalizedSpokenPhrases.map {
            EmojiCommandAlias(spokenPhrase: $0, replacement: normalizedEmoji)
        }
    }

    public var promptHints: [String] {
        Array(normalizedSpokenPhrases.prefix(3))
    }

    public var hasUsableCommand: Bool {
        !normalizedEmoji.isEmpty && !normalizedSpokenPhrases.isEmpty
    }

    public var normalizedForStorage: CustomEmojiCommand {
        let normalizedPhrases = normalizedSpokenPhrases
        let normalizedCommand = normalizedPhrases.first ?? ""
        let normalizedAliases = Array(normalizedPhrases.dropFirst())

        return CustomEmojiCommand(
            id: id,
            emoji: normalizedEmoji,
            command: normalizedCommand,
            aliases: normalizedAliases,
            isEnabled: isEnabled
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case emoji
        case command
        case aliases
        case isEnabled
    }
}

public struct EmojiCommandSet: Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let commands: [EmojiCommand]

    public init(id: String, displayName: String, commands: [EmojiCommand]) {
        self.id = id
        self.displayName = displayName
        self.commands = commands
    }

    public var aliases: [EmojiCommandAlias] {
        commands.flatMap(\.replacementAliases)
    }

    public var promptHints: [String] {
        commands.flatMap(\.promptHints)
    }

    public var previewText: String {
        guard let example = commands.first else {
            return "No commands"
        }

        return "\(example.primarySpokenPhrase) -> \(example.emoji)"
    }

    public static let builtIn: [EmojiCommandSet] = [
        EmojiCommandSet(
            id: "en",
            displayName: "English",
            commands: [
                EmojiCommand(id: "heart", emoji: "❤️", displayName: "Heart", aliases: [
                    "emoji heart", "emoji red heart",
                ]),
                EmojiCommand(id: "laugh", emoji: "😂", displayName: "Laugh", aliases: [
                    "emoji laugh", "emoji laughing", "emoji haha",
                ]),
                EmojiCommand(id: "rofl", emoji: "🤣", displayName: "ROFL", aliases: [
                    "emoji rofl", "emoji rolling laugh", "emoji rolling on the floor laughing",
                ]),
                EmojiCommand(id: "thumbs-up", emoji: "👍", displayName: "Thumbs up", aliases: [
                    "emoji thumbs up", "emoji like",
                ]),
                EmojiCommand(id: "crying", emoji: "😭", displayName: "Crying", aliases: [
                    "emoji crying", "emoji cry",
                ]),
                EmojiCommand(id: "please", emoji: "🙏", displayName: "Please", aliases: [
                    "emoji please", "emoji pray", "emoji folded hands",
                ]),
                EmojiCommand(id: "kiss", emoji: "😘", displayName: "Kiss", aliases: [
                    "emoji kiss",
                ]),
                EmojiCommand(id: "love", emoji: "🥰", displayName: "Love", aliases: [
                    "emoji love", "emoji loving face",
                ]),
                EmojiCommand(id: "heart-eyes", emoji: "😍", displayName: "Heart eyes", aliases: [
                    "emoji heart eyes",
                ]),
                EmojiCommand(id: "smile", emoji: "🙂", displayName: "Smile", aliases: [
                    "emoji smile", "emoji smiling",
                ]),
                EmojiCommand(id: "angry", emoji: "😠", displayName: "Angry", aliases: [
                    "emoji angry", "emoji mad",
                ]),
                EmojiCommand(id: "check", emoji: "✅", displayName: "Check", aliases: [
                    "emoji check", "emoji check mark",
                ]),
                EmojiCommand(id: "cross", emoji: "❌", displayName: "Cross", aliases: [
                    "emoji cross", "emoji x mark",
                ]),
                EmojiCommand(id: "fire", emoji: "🔥", displayName: "Fire", aliases: [
                    "emoji fire",
                ]),
                EmojiCommand(id: "sparkles", emoji: "✨", displayName: "Sparkles", aliases: [
                    "emoji sparkles", "emoji sparkle",
                ]),
                EmojiCommand(id: "touched", emoji: "🥹", displayName: "Touched", aliases: [
                    "emoji touched", "emoji holding back tears",
                ]),
                EmojiCommand(id: "eyes", emoji: "👀", displayName: "Eyes", aliases: [
                    "emoji eyes",
                ]),
                EmojiCommand(id: "skull", emoji: "💀", displayName: "Skull", aliases: [
                    "emoji skull",
                ]),
                EmojiCommand(id: "heart-hands", emoji: "🫶", displayName: "Heart hands", aliases: [
                    "emoji heart hands",
                ]),
                EmojiCommand(id: "melting", emoji: "🫠", displayName: "Melting", aliases: [
                    "emoji melting",
                ]),
                EmojiCommand(id: "broken-heart", emoji: "💔", displayName: "Broken heart", aliases: [
                    "emoji broken heart",
                ]),
            ]
        ),
        EmojiCommandSet(
            id: "ru",
            displayName: "Русский",
            commands: [
                EmojiCommand(id: "heart", emoji: "❤️", displayName: "Сердце", aliases: [
                    "эмодзи сердце", "эмодзи сердечко",
                ]),
                EmojiCommand(id: "laugh", emoji: "😂", displayName: "Смех", aliases: [
                    "эмодзи смех", "эмодзи смеюсь",
                ]),
                EmojiCommand(id: "rofl", emoji: "🤣", displayName: "Ржу", aliases: [
                    "эмодзи ржу", "эмодзи хохот",
                ]),
                EmojiCommand(id: "thumbs-up", emoji: "👍", displayName: "Лайк", aliases: [
                    "эмодзи лайк", "эмодзи палец вверх",
                ]),
                EmojiCommand(id: "crying", emoji: "😭", displayName: "Плачу", aliases: [
                    "эмодзи плачу", "эмодзи слезы",
                ]),
                EmojiCommand(id: "please", emoji: "🙏", displayName: "Пожалуйста", aliases: [
                    "эмодзи пожалуйста", "эмодзи молитва",
                ]),
                EmojiCommand(id: "kiss", emoji: "😘", displayName: "Поцелуй", aliases: [
                    "эмодзи поцелуй", "эмодзи чмок",
                ]),
                EmojiCommand(id: "love", emoji: "🥰", displayName: "Любовь", aliases: [
                    "эмодзи любовь", "эмодзи влюблен",
                ]),
                EmojiCommand(id: "heart-eyes", emoji: "😍", displayName: "Сердечки в глазах", aliases: [
                    "эмодзи глаза сердечки", "эмодзи влюбленные глаза",
                ]),
                EmojiCommand(id: "smile", emoji: "🙂", displayName: "Улыбка", aliases: [
                    "эмодзи смайл", "эмодзи улыбка", "эмодзи смайлик",
                ]),
                EmojiCommand(id: "angry", emoji: "😠", displayName: "Злой", aliases: [
                    "эмодзи злой", "эмодзи злость",
                ]),
                EmojiCommand(id: "check", emoji: "✅", displayName: "Галочка", aliases: [
                    "эмодзи галочка", "эмодзи чек",
                ]),
                EmojiCommand(id: "cross", emoji: "❌", displayName: "Крестик", aliases: [
                    "эмодзи крестик", "эмодзи крест",
                ]),
                EmojiCommand(id: "fire", emoji: "🔥", displayName: "Огонь", aliases: [
                    "эмодзи огонь",
                ]),
                EmojiCommand(id: "sparkles", emoji: "✨", displayName: "Искры", aliases: [
                    "эмодзи искры", "эмодзи блестки",
                ]),
                EmojiCommand(id: "touched", emoji: "🥹", displayName: "Тронут", aliases: [
                    "эмодзи тронут", "эмодзи умиление",
                ]),
                EmojiCommand(id: "eyes", emoji: "👀", displayName: "Глаза", aliases: [
                    "эмодзи глаза",
                ]),
                EmojiCommand(id: "skull", emoji: "💀", displayName: "Череп", aliases: [
                    "эмодзи череп", "эмодзи умер",
                ]),
                EmojiCommand(id: "heart-hands", emoji: "🫶", displayName: "Руки сердцем", aliases: [
                    "эмодзи руки сердцем",
                ]),
                EmojiCommand(id: "melting", emoji: "🫠", displayName: "Таю", aliases: [
                    "эмодзи таю", "эмодзи плавлюсь",
                ]),
                EmojiCommand(id: "broken-heart", emoji: "💔", displayName: "Разбитое сердце", aliases: [
                    "эмодзи разбитое сердце",
                ]),
            ]
        ),
        EmojiCommandSet(
            id: "es",
            displayName: "Español",
            commands: [
                EmojiCommand(id: "heart", emoji: "❤️", displayName: "Corazón", aliases: [
                    "emoji corazón", "emoji corazon",
                ]),
                EmojiCommand(id: "laugh", emoji: "😂", displayName: "Risa", aliases: [
                    "emoji risa", "emoji reír", "emoji reir",
                ]),
                EmojiCommand(id: "rofl", emoji: "🤣", displayName: "Carcajada", aliases: [
                    "emoji carcajada", "emoji muerto de risa",
                ]),
                EmojiCommand(id: "thumbs-up", emoji: "👍", displayName: "Pulgar arriba", aliases: [
                    "emoji pulgar arriba", "emoji me gusta",
                ]),
                EmojiCommand(id: "crying", emoji: "😭", displayName: "Llorando", aliases: [
                    "emoji llorando", "emoji llanto",
                ]),
                EmojiCommand(id: "please", emoji: "🙏", displayName: "Por favor", aliases: [
                    "emoji por favor", "emoji rezar",
                ]),
                EmojiCommand(id: "kiss", emoji: "😘", displayName: "Beso", aliases: [
                    "emoji beso",
                ]),
                EmojiCommand(id: "love", emoji: "🥰", displayName: "Enamorado", aliases: [
                    "emoji enamorado", "emoji amor",
                ]),
                EmojiCommand(id: "heart-eyes", emoji: "😍", displayName: "Ojos de corazón", aliases: [
                    "emoji ojos de corazón", "emoji ojos de corazon",
                ]),
                EmojiCommand(id: "smile", emoji: "🙂", displayName: "Sonrisa", aliases: [
                    "emoji sonrisa",
                ]),
                EmojiCommand(id: "angry", emoji: "😠", displayName: "Enojado", aliases: [
                    "emoji enojado", "emoji enfadado",
                ]),
                EmojiCommand(id: "check", emoji: "✅", displayName: "Check", aliases: [
                    "emoji check", "emoji marca de verificación", "emoji marca de verificacion",
                ]),
                EmojiCommand(id: "cross", emoji: "❌", displayName: "Cruz", aliases: [
                    "emoji cruz",
                ]),
                EmojiCommand(id: "fire", emoji: "🔥", displayName: "Fuego", aliases: [
                    "emoji fuego",
                ]),
                EmojiCommand(id: "sparkles", emoji: "✨", displayName: "Brillos", aliases: [
                    "emoji brillos", "emoji destellos",
                ]),
                EmojiCommand(id: "touched", emoji: "🥹", displayName: "Emoción", aliases: [
                    "emoji emoción", "emoji emocion",
                ]),
                EmojiCommand(id: "eyes", emoji: "👀", displayName: "Ojos", aliases: [
                    "emoji ojos",
                ]),
                EmojiCommand(id: "skull", emoji: "💀", displayName: "Calavera", aliases: [
                    "emoji calavera",
                ]),
                EmojiCommand(id: "heart-hands", emoji: "🫶", displayName: "Manos corazón", aliases: [
                    "emoji manos corazón", "emoji manos corazon",
                ]),
                EmojiCommand(id: "melting", emoji: "🫠", displayName: "Derretido", aliases: [
                    "emoji derretido",
                ]),
                EmojiCommand(id: "broken-heart", emoji: "💔", displayName: "Corazón roto", aliases: [
                    "emoji corazón roto", "emoji corazon roto",
                ]),
            ]
        ),
        EmojiCommandSet(
            id: "de",
            displayName: "Deutsch",
            commands: [
                EmojiCommand(id: "heart", emoji: "❤️", displayName: "Herz", aliases: [
                    "emoji herz",
                ]),
                EmojiCommand(id: "laugh", emoji: "😂", displayName: "Lachen", aliases: [
                    "emoji lachen", "emoji lachend",
                ]),
                EmojiCommand(id: "rofl", emoji: "🤣", displayName: "Lachflash", aliases: [
                    "emoji lachflash", "emoji totlachen",
                ]),
                EmojiCommand(id: "thumbs-up", emoji: "👍", displayName: "Daumen hoch", aliases: [
                    "emoji daumen hoch",
                ]),
                EmojiCommand(id: "crying", emoji: "😭", displayName: "Weinen", aliases: [
                    "emoji weinen", "emoji heulen",
                ]),
                EmojiCommand(id: "please", emoji: "🙏", displayName: "Bitte", aliases: [
                    "emoji bitte", "emoji beten",
                ]),
                EmojiCommand(id: "kiss", emoji: "😘", displayName: "Kuss", aliases: [
                    "emoji kuss",
                ]),
                EmojiCommand(id: "love", emoji: "🥰", displayName: "Verliebt", aliases: [
                    "emoji verliebt", "emoji liebe",
                ]),
                EmojiCommand(id: "heart-eyes", emoji: "😍", displayName: "Herzaugen", aliases: [
                    "emoji herzaugen",
                ]),
                EmojiCommand(id: "smile", emoji: "🙂", displayName: "Lächeln", aliases: [
                    "emoji lächeln", "emoji laecheln",
                ]),
                EmojiCommand(id: "angry", emoji: "😠", displayName: "Wütend", aliases: [
                    "emoji wütend", "emoji wuetend",
                ]),
                EmojiCommand(id: "check", emoji: "✅", displayName: "Haken", aliases: [
                    "emoji haken", "emoji check",
                ]),
                EmojiCommand(id: "cross", emoji: "❌", displayName: "Kreuz", aliases: [
                    "emoji kreuz",
                ]),
                EmojiCommand(id: "fire", emoji: "🔥", displayName: "Feuer", aliases: [
                    "emoji feuer",
                ]),
                EmojiCommand(id: "sparkles", emoji: "✨", displayName: "Glitzer", aliases: [
                    "emoji glitzer", "emoji funkeln",
                ]),
                EmojiCommand(id: "touched", emoji: "🥹", displayName: "Gerührt", aliases: [
                    "emoji gerührt", "emoji geruehrt",
                ]),
                EmojiCommand(id: "eyes", emoji: "👀", displayName: "Augen", aliases: [
                    "emoji augen",
                ]),
                EmojiCommand(id: "skull", emoji: "💀", displayName: "Schädel", aliases: [
                    "emoji schädel", "emoji schaedel",
                ]),
                EmojiCommand(id: "heart-hands", emoji: "🫶", displayName: "Herz Hände", aliases: [
                    "emoji herz hände", "emoji herz haende",
                ]),
                EmojiCommand(id: "melting", emoji: "🫠", displayName: "Schmelzend", aliases: [
                    "emoji schmelzend",
                ]),
                EmojiCommand(id: "broken-heart", emoji: "💔", displayName: "Gebrochenes Herz", aliases: [
                    "emoji gebrochenes herz",
                ]),
            ]
        ),
        EmojiCommandSet(
            id: "fr",
            displayName: "Français",
            commands: [
                EmojiCommand(id: "heart", emoji: "❤️", displayName: "Coeur", aliases: [
                    "emoji cœur", "emoji coeur",
                ]),
                EmojiCommand(id: "laugh", emoji: "😂", displayName: "Rire", aliases: [
                    "emoji rire",
                ]),
                EmojiCommand(id: "rofl", emoji: "🤣", displayName: "Mort de rire", aliases: [
                    "emoji mort de rire",
                ]),
                EmojiCommand(id: "thumbs-up", emoji: "👍", displayName: "Pouce levé", aliases: [
                    "emoji pouce levé", "emoji pouce leve",
                ]),
                EmojiCommand(id: "crying", emoji: "😭", displayName: "Pleure", aliases: [
                    "emoji pleure", "emoji pleurer",
                ]),
                EmojiCommand(id: "please", emoji: "🙏", displayName: "Prière", aliases: [
                    "emoji prière", "emoji priere",
                ]),
                EmojiCommand(id: "kiss", emoji: "😘", displayName: "Bisou", aliases: [
                    "emoji bisou",
                ]),
                EmojiCommand(id: "love", emoji: "🥰", displayName: "Amoureux", aliases: [
                    "emoji amoureux", "emoji amour",
                ]),
                EmojiCommand(id: "heart-eyes", emoji: "😍", displayName: "Yeux coeur", aliases: [
                    "emoji yeux cœur", "emoji yeux coeur",
                ]),
                EmojiCommand(id: "smile", emoji: "🙂", displayName: "Sourire", aliases: [
                    "emoji sourire",
                ]),
                EmojiCommand(id: "angry", emoji: "😠", displayName: "En colère", aliases: [
                    "emoji en colère", "emoji en colere",
                ]),
                EmojiCommand(id: "check", emoji: "✅", displayName: "Coche", aliases: [
                    "emoji coche", "emoji check",
                ]),
                EmojiCommand(id: "cross", emoji: "❌", displayName: "Croix", aliases: [
                    "emoji croix",
                ]),
                EmojiCommand(id: "fire", emoji: "🔥", displayName: "Feu", aliases: [
                    "emoji feu",
                ]),
                EmojiCommand(id: "sparkles", emoji: "✨", displayName: "Étincelles", aliases: [
                    "emoji étincelles", "emoji etincelles",
                ]),
                EmojiCommand(id: "touched", emoji: "🥹", displayName: "Ému", aliases: [
                    "emoji ému", "emoji emu",
                ]),
                EmojiCommand(id: "eyes", emoji: "👀", displayName: "Yeux", aliases: [
                    "emoji yeux",
                ]),
                EmojiCommand(id: "skull", emoji: "💀", displayName: "Tête de mort", aliases: [
                    "emoji tête de mort", "emoji tete de mort",
                ]),
                EmojiCommand(id: "heart-hands", emoji: "🫶", displayName: "Mains coeur", aliases: [
                    "emoji mains cœur", "emoji mains coeur",
                ]),
                EmojiCommand(id: "melting", emoji: "🫠", displayName: "Fondant", aliases: [
                    "emoji fondant",
                ]),
                EmojiCommand(id: "broken-heart", emoji: "💔", displayName: "Coeur brisé", aliases: [
                    "emoji cœur brisé", "emoji coeur brise",
                ]),
            ]
        ),
        EmojiCommandSet(
            id: "pt",
            displayName: "Português",
            commands: [
                EmojiCommand(id: "heart", emoji: "❤️", displayName: "Coração", aliases: [
                    "emoji coração", "emoji coracao",
                ]),
                EmojiCommand(id: "laugh", emoji: "😂", displayName: "Riso", aliases: [
                    "emoji riso", "emoji rir",
                ]),
                EmojiCommand(id: "rofl", emoji: "🤣", displayName: "Gargalhada", aliases: [
                    "emoji gargalhada",
                ]),
                EmojiCommand(id: "thumbs-up", emoji: "👍", displayName: "Joinha", aliases: [
                    "emoji joinha", "emoji polegar para cima",
                ]),
                EmojiCommand(id: "crying", emoji: "😭", displayName: "Chorando", aliases: [
                    "emoji chorando", "emoji choro",
                ]),
                EmojiCommand(id: "please", emoji: "🙏", displayName: "Por favor", aliases: [
                    "emoji por favor", "emoji rezar",
                ]),
                EmojiCommand(id: "kiss", emoji: "😘", displayName: "Beijo", aliases: [
                    "emoji beijo",
                ]),
                EmojiCommand(id: "love", emoji: "🥰", displayName: "Apaixonado", aliases: [
                    "emoji apaixonado", "emoji amor",
                ]),
                EmojiCommand(id: "heart-eyes", emoji: "😍", displayName: "Olhos de coração", aliases: [
                    "emoji olhos de coração", "emoji olhos de coracao",
                ]),
                EmojiCommand(id: "smile", emoji: "🙂", displayName: "Sorriso", aliases: [
                    "emoji sorriso",
                ]),
                EmojiCommand(id: "angry", emoji: "😠", displayName: "Bravo", aliases: [
                    "emoji bravo", "emoji zangado",
                ]),
                EmojiCommand(id: "check", emoji: "✅", displayName: "Marca de verificação", aliases: [
                    "emoji marca de verificação", "emoji marca de verificacao", "emoji check",
                ]),
                EmojiCommand(id: "cross", emoji: "❌", displayName: "Cruz", aliases: [
                    "emoji cruz",
                ]),
                EmojiCommand(id: "fire", emoji: "🔥", displayName: "Fogo", aliases: [
                    "emoji fogo",
                ]),
                EmojiCommand(id: "sparkles", emoji: "✨", displayName: "Brilhos", aliases: [
                    "emoji brilhos",
                ]),
                EmojiCommand(id: "touched", emoji: "🥹", displayName: "Emocionado", aliases: [
                    "emoji emocionado",
                ]),
                EmojiCommand(id: "eyes", emoji: "👀", displayName: "Olhos", aliases: [
                    "emoji olhos",
                ]),
                EmojiCommand(id: "skull", emoji: "💀", displayName: "Caveira", aliases: [
                    "emoji caveira",
                ]),
                EmojiCommand(id: "heart-hands", emoji: "🫶", displayName: "Mãos coração", aliases: [
                    "emoji mãos coração", "emoji maos coracao",
                ]),
                EmojiCommand(id: "melting", emoji: "🫠", displayName: "Derretendo", aliases: [
                    "emoji derretendo",
                ]),
                EmojiCommand(id: "broken-heart", emoji: "💔", displayName: "Coração partido", aliases: [
                    "emoji coração partido", "emoji coracao partido",
                ]),
            ]
        ),
    ]

    public static var builtInIDs: Set<String> {
        Set(builtIn.map(\.id))
    }

    public static func normalizedBuiltInIDs(_ ids: [String]) -> [String] {
        for id in ids {
            let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if builtInIDs.contains(trimmedID) {
                return [trimmedID]
            }
        }

        return []
    }
}
