//
//  EmojiCommandReplacementService.swift
//  HoldTypeDomain
//
//  Created by Codex on 7/7/26.
//

import Foundation

public struct EmojiCommandReplacementService: Sendable {
    public init() {}

    public static func normalizedSpokenPhraseKey(
        _ phrase: String
    ) -> String? {
        let tokens = normalizedWordTokens(from: phrase)
        return tokens.isEmpty ? nil : tokens.joined(separator: " ")
    }

    public func process(
        _ text: String,
        commandSets: [EmojiCommandSet],
        customCommands: [CustomEmojiCommand] = []
    ) -> String {
        let aliases = Self.normalizedAliases(
            commandSets: commandSets,
            customCommands: customCommands
        )
        guard !aliases.isEmpty else {
            return text
        }

        let tokens = Self.tokenize(text)
        guard !tokens.isEmpty else {
            return text
        }

        var processedText = ""
        var tokenIndex = tokens.startIndex

        while tokenIndex < tokens.endIndex {
            if tokens[tokenIndex].kind == .word,
               let match = Self.firstMatch(in: tokens, startingAt: tokenIndex, aliases: aliases) {
                processedText.append(match.replacement)
                tokenIndex = match.endIndex
            } else {
                processedText.append(tokens[tokenIndex].text)
                tokenIndex = tokens.index(after: tokenIndex)
            }
        }

        return processedText
    }

    private static func normalizedAliases(
        commandSets: [EmojiCommandSet],
        customCommands: [CustomEmojiCommand]
    ) -> [MatcherAlias] {
        let rawAliases = customCommands
            .filter { $0.isEnabled && $0.hasUsableCommand }
            .flatMap(\.replacementAliases)
            + commandSets.flatMap(\.aliases)

        var matcherAliases: [MatcherAlias] = []
        var seenPhraseKeys = Set<String>()

        for alias in rawAliases {
            guard let matcherAlias = MatcherAlias(alias: alias) else {
                continue
            }

            let phraseKey = matcherAlias.normalizedWordTokens.joined(separator: " ")
            guard !seenPhraseKeys.contains(phraseKey) else {
                continue
            }

            seenPhraseKeys.insert(phraseKey)
            matcherAliases.append(matcherAlias)
        }

        return matcherAliases.sorted { lhs, rhs in
            if lhs.normalizedWordTokens.count != rhs.normalizedWordTokens.count {
                return lhs.normalizedWordTokens.count > rhs.normalizedWordTokens.count
            }

            return lhs.sourceCharacterCount > rhs.sourceCharacterCount
        }
    }

    private static func firstMatch(
        in tokens: [Token],
        startingAt startIndex: Int,
        aliases: [MatcherAlias]
    ) -> Match? {
        for alias in aliases {
            if let endIndex = match(alias, in: tokens, startingAt: startIndex) {
                return Match(replacement: alias.replacement, endIndex: endIndex)
            }
        }

        return nil
    }

    private static func match(
        _ alias: MatcherAlias,
        in tokens: [Token],
        startingAt startIndex: Int
    ) -> Int? {
        guard tokens[startIndex].kind == .word else {
            return nil
        }

        var tokenIndex = startIndex

        for aliasTokenIndex in alias.normalizedWordTokens.indices {
            if aliasTokenIndex > alias.normalizedWordTokens.startIndex {
                while tokenIndex < tokens.endIndex, tokens[tokenIndex].kind == .separator {
                    tokenIndex = tokens.index(after: tokenIndex)
                }
            }

            guard tokenIndex < tokens.endIndex,
                  tokens[tokenIndex].kind == .word,
                  let normalizedText = tokens[tokenIndex].normalizedText,
                  normalizedText == alias.normalizedWordTokens[aliasTokenIndex] else {
                return nil
            }

            tokenIndex = tokens.index(after: tokenIndex)
        }

        return tokenIndex
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var currentText = ""
        var currentKind: Token.Kind?

        for character in text {
            let kind: Token.Kind = isWord(character) ? .word : .separator

            if let existingKind = currentKind, existingKind != kind {
                tokens.append(Token(text: currentText, kind: existingKind))
                currentText = ""
            }

            currentKind = kind
            currentText.append(character)
        }

        if let currentKind, !currentText.isEmpty {
            tokens.append(Token(text: currentText, kind: currentKind))
        }

        return tokens
    }

    private static func normalizedWordTokens(from text: String) -> [String] {
        tokenize(text)
            .filter { $0.kind == .word }
            .compactMap(\.normalizedText)
    }

    private static func normalizedText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func isWord(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            wordScalarSet.contains(scalar)
        }
    }

    private static let wordScalarSet = CharacterSet.alphanumerics
        .union(.nonBaseCharacters)

    private struct Token {
        enum Kind {
            case word
            case separator
        }

        let text: String
        let kind: Kind

        var normalizedText: String? {
            guard kind == .word else {
                return nil
            }

            return EmojiCommandReplacementService.normalizedText(text)
        }
    }

    private struct MatcherAlias {
        let normalizedWordTokens: [String]
        let replacement: String
        let sourceCharacterCount: Int

        init?(alias: EmojiCommandAlias) {
            let wordTokens = EmojiCommandReplacementService.normalizedWordTokens(
                from: alias.spokenPhrase
            )
            guard !wordTokens.isEmpty else {
                return nil
            }

            self.normalizedWordTokens = wordTokens
            self.replacement = alias.replacement
            self.sourceCharacterCount = alias.spokenPhrase.count
        }
    }

    private struct Match {
        let replacement: String
        let endIndex: Int
    }
}
