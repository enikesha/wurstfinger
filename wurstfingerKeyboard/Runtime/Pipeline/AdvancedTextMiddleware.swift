//
//  AdvancedTextMiddleware.swift
//  Wurstfinger
//
//  Handles text actions that require more than a simple proxy call:
//  delete-forward, capitalize-word, word-cursor movement, and clipboard.
//

import UIKit

/// Handles advanced text-input actions that `TextInputMiddleware` leaves
/// as pass-through: word delete, delete-forward, capitalize-word,
/// word-boundary cursor movement, and clipboard (copy/paste/cut).
///
/// These actions need multi-step proxy interaction (e.g. read context,
/// delete, re-insert) and are therefore separated from the basic middleware
/// to keep each middleware focused and independently testable.
struct AdvancedTextMiddleware: ActionMiddleware {
    private let targetProvider: () -> TextInputTarget?
    private let localeProvider: () -> Locale

    init(target: @escaping () -> TextInputTarget?, locale: @escaping () -> Locale) {
        targetProvider = target
        localeProvider = locale
    }

    func process(_ context: ActionContext, next: (ActionContext) -> Void) {
        if let target = targetProvider() {
            apply(action: context.action, to: target)
        }
        next(context)
    }

    private func apply(action: KeyAction, to target: TextInputTarget) {
        switch action {
        case .deleteWordBackward:
            deleteWordBackward(target: target)
        case .deleteForward:
            deleteForward(target: target)
        case let .capitalizeWord(uppercased):
            capitalizeWord(target: target, uppercased: uppercased)
        case .copy:
            handleCopy(target: target)
        case .paste:
            handlePaste(target: target)
        case .cut:
            handleCut(target: target)
        default:
            break
        }
    }

    // MARK: - Deletion

    private func deleteWordBackward(target: TextInputTarget) {
        guard let context = target.documentContextBeforeInput, !context.isEmpty else { return }
        let deleteCount = Self.previousWordDeleteCount(in: context)
        guard deleteCount > 0 else { return }

        for _ in 0 ..< deleteCount {
            target.deleteBackward()
        }
    }

    private func deleteForward(target: TextInputTarget) {
        guard let after = target.documentContextAfterInput, !after.isEmpty else { return }
        target.adjustTextPosition(byCharacterOffset: 1)
        target.deleteBackward()
    }

    // MARK: - Capitalize Word

    private func capitalizeWord(target: TextInputTarget, uppercased: Bool) {
        guard let context = target.documentContextBeforeInput, !context.isEmpty else { return }

        var characters: [Character] = []
        for character in context.reversed() {
            if character.isLetter {
                characters.append(character)
            } else {
                break
            }
        }
        guard !characters.isEmpty else { return }

        let word = String(characters.reversed())
        let locale = localeProvider()
        let transformed = uppercased ? word.uppercased(with: locale) : word.lowercased(with: locale)

        for _ in 0 ..< word.count {
            target.deleteBackward()
        }
        target.insertText(transformed)
    }

    // MARK: - Clipboard

    private func handleCopy(target: TextInputTarget) {
        guard target.hasFullAccess else { return }
        if let selected = target.selectedText, !selected.isEmpty {
            UIPasteboard.general.string = selected
        }
    }

    private func handlePaste(target: TextInputTarget) {
        guard target.hasFullAccess else { return }
        if let text = UIPasteboard.general.string, !text.isEmpty {
            target.insertText(text)
        }
    }

    private func handleCut(target: TextInputTarget) {
        guard target.hasFullAccess else { return }
        if let selected = target.selectedText, !selected.isEmpty {
            UIPasteboard.general.string = selected
            target.deleteBackward()
        }
    }

    static func previousWordDeleteCount(in context: String) -> Int {
        let characters = Array(context)
        var index = characters.count

        while index > 0, characters[index - 1].isWhitespace {
            index -= 1
        }

        if index == 0 {
            return characters.count
        }

        if isWordCharacter(characters[index - 1]) {
            while index > 0, isWordCharacter(characters[index - 1]) {
                index -= 1
            }
        } else {
            while index > 0,
                  !characters[index - 1].isWhitespace,
                  !isWordCharacter(characters[index - 1]) {
                index -= 1
            }
        }

        return characters.count - index
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
