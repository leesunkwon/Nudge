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
        VStack(alignment: .leading, spacing: 10) {
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
            Text(text)
                .font(.system(size: level == 1 ? 17 : 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .textSelection(.enabled)
                .padding(.top, level == 1 ? 4 : 2)

        case let .paragraph(text):
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(Color.white.opacity(0.88))
                .textSelection(.enabled)

        case let .listItem(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.56))

                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .lineSpacing(4)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .textSelection(.enabled)
            }

        case let .code(code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    }
            }
        }
    }
}

private struct NudgeMarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case listItem(String)
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
        if line.hasPrefix("## ") {
            return NudgeMarkdownBlock(kind: .heading(level: 2, text: String(line.dropFirst(3))))
        }

        if line.hasPrefix("# ") {
            return NudgeMarkdownBlock(kind: .heading(level: 1, text: String(line.dropFirst(2))))
        }

        return nil
    }

    private static func listItemBlock(from line: String) -> NudgeMarkdownBlock? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return NudgeMarkdownBlock(kind: .listItem(String(line.dropFirst(2))))
        }

        return nil
    }
}
