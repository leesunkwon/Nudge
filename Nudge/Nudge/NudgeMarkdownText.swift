//
//  NudgeMarkdownText.swift
//  Nudge
//
//  Created by Codex on 6/16/26.
//

import SwiftUI

struct NudgeMarkdownText: View {
    let markdown: String

    private var blocks: [NudgeMarkdownBlock] {
        NudgeMarkdownParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(for block: NudgeMarkdownBlock) -> some View {
        switch block.kind {
        case let .heading(level, text):
            HStack(alignment: .center, spacing: 9) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.33, green: 0.62, blue: 1.0),
                                Color(red: 0.78, green: 0.38, blue: 1.0),
                                Color(red: 1.0, green: 0.48, blue: 0.66)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: level == 1 ? 20 : 17)

                Text(inlineAttributedString(
                    normalizedInlineMarkdown(text),
                    fontSize: headingFontSize(for: level),
                    regularWeight: .semibold,
                    emphasizedWeight: .bold
                ))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .textSelection(.enabled)
            }
            .padding(.top, level == 1 ? 5 : 3)
            .padding(.bottom, 1)

        case let .paragraph(text):
            Text(inlineAttributedString(normalizedInlineMarkdown(text), fontSize: 15))
                .lineSpacing(5)
                .foregroundStyle(Color.white.opacity(0.88))
                .textSelection(.enabled)

        case let .listItem(marker, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(minWidth: marker == "•" ? 10 : 22, alignment: .trailing)

                Text(inlineAttributedString(normalizedInlineMarkdown(text), fontSize: 15))
                    .lineSpacing(5)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .textSelection(.enabled)
            }

        case let .code(code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }
        }
    }

    private func headingFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            return 20
        case 2:
            return 18
        default:
            return 16
        }
    }

    private func normalizedInlineMarkdown(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inlineAttributedString(
        _ text: String,
        fontSize: CGFloat,
        regularWeight: Font.Weight = .regular,
        emphasizedWeight: Font.Weight = .semibold
    ) -> AttributedString {
        let segments = NudgeInlineMarkdownParser.parse(text)
        return segments.reduce(AttributedString()) { partialText, segment in
            var nextText = AttributedString(segment.text)
            nextText.font = .system(size: fontSize, weight: segment.isEmphasized ? emphasizedWeight : regularWeight)
            return partialText + nextText
        }
    }
}

private struct NudgeMarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(marker: String, text: String)
        case code(String)
    }
}

private enum NudgeMarkdownParser {
    static func parse(_ markdown: String) -> [NudgeMarkdownBlock] {
        var blocks: [NudgeMarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInsideCodeBlock = false

        func flushParagraph() {
            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            if !paragraph.isEmpty {
                blocks.append(NudgeMarkdownBlock(kind: .paragraph(paragraph)))
            }

            paragraphLines.removeAll()
        }

        func flushCodeBlock() {
            blocks.append(NudgeMarkdownBlock(kind: .code(codeLines.joined(separator: "\n"))))
            codeLines.removeAll()
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                if isInsideCodeBlock {
                    flushCodeBlock()
                    isInsideCodeBlock = false
                } else {
                    flushParagraph()
                    isInsideCodeBlock = true
                }
                continue
            }

            if isInsideCodeBlock {
                codeLines.append(line)
                continue
            }

            if trimmedLine.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = headingBlock(from: trimmedLine) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let listItem = listItemBlock(from: trimmedLine) {
                flushParagraph()
                blocks.append(listItem)
                continue
            }

            paragraphLines.append(line)
        }

        if isInsideCodeBlock {
            flushCodeBlock()
        }

        flushParagraph()
        return blocks
    }

    private static func headingBlock(from line: String) -> NudgeMarkdownBlock? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(markerCount) else { return nil }

        let markerEndIndex = line.index(line.startIndex, offsetBy: markerCount)
        guard markerEndIndex < line.endIndex,
              line[markerEndIndex].isWhitespace else { return nil }

        let textStartIndex = line.index(after: markerEndIndex)
        return NudgeMarkdownBlock(kind: .heading(level: markerCount, text: String(line[textStartIndex...])))
    }

    private static func listItemBlock(from line: String) -> NudgeMarkdownBlock? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return NudgeMarkdownBlock(kind: .listItem(marker: "•", text: String(line.dropFirst(2))))
        }

        guard let dotIndex = line.firstIndex(of: ".") else { return nil }

        let numberText = line[..<dotIndex]
        let afterDotIndex = line.index(after: dotIndex)
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              afterDotIndex < line.endIndex,
              line[afterDotIndex].isWhitespace else {
            return nil
        }

        let textStartIndex = line.index(after: afterDotIndex)
        return NudgeMarkdownBlock(kind: .listItem(marker: "\(numberText).", text: String(line[textStartIndex...])))
    }
}

private struct NudgeInlineMarkdownSegment {
    let text: String
    let isEmphasized: Bool
}

private enum NudgeInlineMarkdownParser {
    static func parse(_ text: String) -> [NudgeInlineMarkdownSegment] {
        var segments: [NudgeInlineMarkdownSegment] = []
        var currentText = ""
        var isEmphasized = false
        var index = text.startIndex

        func flushCurrentText() {
            guard !currentText.isEmpty else { return }
            segments.append(NudgeInlineMarkdownSegment(text: currentText, isEmphasized: isEmphasized))
            currentText = ""
        }

        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            if nextIndex < text.endIndex,
               text[index] == "*",
               text[nextIndex] == "*" {
                flushCurrentText()
                isEmphasized.toggle()
                index = text.index(after: nextIndex)
                continue
            }

            currentText.append(text[index])
            index = nextIndex
        }

        flushCurrentText()
        return segments
    }
}
