import SwiftUI

/// One block of an article body.
///
/// `body` arrives as Markdown restricted to a small subset — paragraphs, `## `
/// subheads, and inline emphasis. Nothing here interprets more than that, and
/// `scripts/validate.mjs` warns on anything outside it, so what the generator
/// writes and what the phone shows can't quietly drift apart.
enum StoryBlock: Hashable {
    case subhead(String)
    case paragraph(String)
}

extension StoryBlock {
    /// Splits a body into blocks.
    ///
    /// Line by line rather than splitting on blank lines, for two reasons: a
    /// subhead becomes its own block whether or not a blank line happens to
    /// precede it, and a body written before this format existed — one unbroken
    /// string with no newlines at all — comes back as a single paragraph rather
    /// than as nothing. That second case is live, not hypothetical: the app holds
    /// a rolling 5 days, so plain-prose stories stay on the phone for most of a
    /// week after the generator starts emitting Markdown.
    ///
    /// Lines within a paragraph join with a space — a lone newline is a soft wrap
    /// in Markdown, not a break.
    static func parse(_ body: String) -> [StoryBlock] {
        var blocks: [StoryBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushParagraph()
            } else if let subhead = subheadText(line) {
                flushParagraph()
                blocks.append(.subhead(subhead))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()

        return blocks
    }

    /// The text of a heading line, or nil if this isn't one. Any level counts:
    /// the contract asks for `## `, but a stray `###` is a story that should
    /// still read correctly rather than one showing its own hash marks.
    private static func subheadText(_ line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard let next = rest.first, next == " " || next == "\t" else { return nil }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The story text, laid out as a news story rather than a single block:
/// paragraphs, and subheads where the generator judged the story long enough to
/// want them.
///
/// The text is one size throughout. A larger opening paragraph is the obvious
/// newspaper move and was tried here, but a 60-word lede at `.title3` fills the
/// whole screen below the photo on a phone the size of Shane's — the reader
/// pays a screenful for a decoration, and the subtitle on the card has already
/// done the standfirst's job.
struct StoryBodyView: View {
    let markdown: String

    @Environment(\.readingFont) private var readingFont

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(StoryBlock.parse(markdown).enumerated()), id: \.offset) { index, block in
                switch block {
                case .subhead(let text):
                    Text(text)
                        .font(.system(.headline, design: readingFont).bold())
                        .foregroundStyle(Palette.ink.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, index == 0 ? 0 : 28)

                case .paragraph(let text):
                    Text(inline(text))
                        .font(.system(.body, design: readingFont))
                        .lineSpacing(6)
                        .foregroundStyle(Palette.ink.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, index == 0 ? 0 : 18)
                }
            }
        }
    }

    /// Inline emphasis only — the block structure is already resolved, and
    /// whitespace is preserved rather than collapsed because the paragraph text
    /// is by this point exactly what should appear.
    ///
    /// Falling back to the raw string on a parse failure means a stray unmatched
    /// `*` costs a bit of stray punctuation, not the paragraph.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
