import Foundation
import NaturalLanguage

/// Some recognizers emit rolling phrases, then finalize their combined text. Align by audio time,
/// retaining earlier phrases and replacing the ranges a later (possibly longer) result covers.
struct RecognitionTranscript {
    private struct Piece {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
    }
    private var pieces: [Piece] = []
    private var draft = ""

    mutating func observe(_ text: String, start: TimeInterval?, end: TimeInterval?) -> String {
        guard !text.isEmpty else { return combined }
        // SFSpeech on macOS emits (0, 0) for the draft of EACH new utterance. Its
        // settled result carries valid times even though isFinal is still false.
        // Zero is not an overlap with the first utterance's audio.
        if let start, let end, end > start {
            let settledText = Self.fuller(settled: text, draft: draft)
            draft = ""
            let replacement = Piece(start: start, end: end, text: settledText)
            if let first = pieces.firstIndex(where: { $0.end > start + 0.05 || abs($0.start - start) < 0.1 }) {
                var last = first
                while last + 1 < pieces.count, pieces[last + 1].start < end { last += 1 }
                pieces.replaceSubrange(first...last, with: [replacement])
            } else {
                pieces.append(replacement)
            }
        } else {
            draft = text
        }
        return combined
    }

    private var combined: String {
        (pieces.map(\.text) + (draft.isEmpty ? [] : [draft])).joined(separator: " ")
    }

    /// The legacy recognizer sometimes drops several already-heard words when settling fast
    /// speech. Prefer the fuller draft only for substantial loss, keeping ordinary corrections.
    private static func fuller(settled: String, draft: String) -> String {
        let cjk = (settled + draft).unicodeScalars.contains { $0.properties.isIdeographic }
        func size(_ text: String) -> Int {
            cjk ? text.filter { $0.isLetter || $0.isNumber }.count : text.split(whereSeparator: \.isWhitespace).count
        }
        let s = size(settled), d = size(draft)
        return d >= s + (cjk ? 6 : 3) && Double(d) >= Double(s) * 1.15 ? draft : settled
    }
}

/// Tracks revisions within one recognition request. Cuts retain their identity when words change.
struct LiveTranscript {
    struct Line: Equatable {
        let id: UUID
        var end: Int
        var text: String
    }

    var protectedPhrases: [String] = []
    private(set) var text = ""
    private(set) var lines: [Line] = []
    private var changedAt = Date.distantPast
    private var pendingSince: Date?
    private var protectedIDs = Set<UUID>()
    private var lastEmission: (id: UUID, at: Date, provisional: Bool)?

    mutating func protect(_ id: UUID) { protectedIDs.insert(id) }

    var pendingText: String {
        String(text.dropFirst(lines.last?.end ?? 0)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isMeaningful(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    mutating func observe(_ newText: String, at now: Date) {
        guard newText != text else { return }
        let old = Array(text), new = Array(newText)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        if lines.contains(where: { $0.end > prefix }) {
            // Align cuts through replacements, leaving newly appended words AFTER a cut.
            // Punctuation alone is not a reliable suffix anchor between two utterances.
            if suffix > 0, new.suffix(suffix).allSatisfy({ !$0.isLetter && !$0.isNumber }) { suffix = 0 }
            let oldEnd = old.count - suffix, newEnd = new.count - suffix
            let oldEdit = Array(old[prefix..<oldEnd]), newEdit = Array(new[prefix..<newEnd])
            let difference = newEdit.difference(from: oldEdit)
            var removed = Set<Int>(), inserted = Set<Int>()
            for change in difference {
                switch change {
                case .remove(let offset, _, _): removed.insert(offset)
                case .insert(let offset, _, _): inserted.insert(offset)
                }
            }
            var cutMap = Array(repeating: 0, count: oldEdit.count + 1)
            var ni = 0
            for oi in 0...oldEdit.count {
                cutMap[oi] = ni
                if oi == oldEdit.count { break }
                while ni < newEdit.count && inserted.contains(ni) { ni += 1 }
                if !removed.contains(oi) { ni += 1 }
            }
            var wordEnds: [Int] = []
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = newText
            if lines.contains(where: { $0.end > prefix }) {
                tokenizer.enumerateTokens(in: newText.startIndex..<newText.endIndex) { range, _ in
                    wordEnds.append(newText.distance(from: newText.startIndex, to: range.upperBound)); return true
                }
            }
            for i in lines.indices {
                let end = lines[i].end
                if end > prefix {
                    var mapped = end > oldEnd ? end + new.count - old.count : prefix + cutMap[end - prefix]
                    // A complete sentence keeps its sentence boundary. Matching only its
                    // final period against the last period of newly appended speech would
                    // otherwise swallow the following sentence into a protected row.
                    let beginning = i > 0 ? lines[i-1].end : 0
                    if let anchored = matchingSentenceBoundary(previous: lines[i].text,
                        updated: String(new.dropFirst(beginning))) { mapped = beginning + anchored }
                mapped = max(0, min(new.count, mapped))
                    if mapped > 0, mapped < new.count, new[mapped-1].isLetter || new[mapped-1].isNumber,
                       new[mapped].isLetter || new[mapped].isNumber {
                        mapped = wordEnds.min(by: { abs($0 - mapped) < abs($1 - mapped) }) ?? mapped
                    }
                    lines[i].end = mapped
                }
                if i > 0 { lines[i].end = max(lines[i-1].end, lines[i].end) }
            }
        }
        text = newText
        changedAt = now
        if pendingSince == nil, (lines.last?.end ?? 0) < new.count { pendingSince = now }
    }

    /// Emit at sentence/clause boundaries; recent provisional fragments can grow in place.
    mutating func drain(at now: Date, force: Bool = false, maxWait: TimeInterval = 4, maxCharacters: Int = 100) -> [Line] {
        var changes: [Line] = []
        var start = 0
        for i in lines.indices {
            let end = max(start, min(text.count, lines[i].end))
            let revised = slice(start, end).trimmingCharacters(in: .whitespacesAndNewlines)
            if revised != lines[i].text { lines[i].text = revised; changes.append(lines[i]) }
            start = end
        }
        // A pause in streaming recognition can produce "Before the" / "keeps".
        // Join the imminent continuation on the SAME row instead of translating a stray tail.
        if let emission = lastEmission, let last = lines.last, last.id == emission.id,
           !protectedIDs.contains(last.id),
           now.timeIntervalSince(emission.at) <= (isCorrection(slice(start, text.count)) ? 12 : 3),
           start < text.count, Self.isMeaningful(slice(start, text.count)),
           (emission.provisional || isCorrection(slice(start, text.count))),
           (sentenceEnd(last.text) == nil || isCorrection(slice(start, text.count))),
           text.count - (lines.count > 1 ? lines[lines.count-2].end : 0) <= 220 {
            let previousEnd = lines.count > 1 ? lines[lines.count-2].end : 0
            let combined = slice(previousEnd, text.count)
            let sentence: Int?
            if isCorrection(slice(start, text.count)) {
                sentence = sentenceEnd(slice(start, text.count)).map { start - previousEnd + $0 }
            } else { sentence = sentenceEnd(combined) }
            let quiet = now.timeIntervalSince(changedAt) >= quietDelay(combined)
            if sentence == nil && !force && !quiet && combined.count < 220 { return changes }
            let end = previousEnd + (sentence ?? combined.count)
            lines[lines.count-1].end = end
            lines[lines.count-1].text = slice(previousEnd, end).trimmingCharacters(in: .whitespacesAndNewlines)
            changes.removeAll { $0.id == last.id }
            changes.append(lines[lines.count-1])
            start = end
            lastEmission = (last.id, now, !force && sentence == nil)
            pendingSince = start < text.count ? now : nil
        }
        while start < text.count {
            let tail = slice(start, text.count)
            let quiet = now.timeIntervalSince(changedAt) >= quietDelay(tail)
            let age = pendingSince.map { now.timeIntervalSince($0) >= maxWait } ?? false
            let hardDeadline = pendingSince.map { now.timeIntervalSince($0) >= maxWait * 2 } ?? false
            let cjk = tail.unicodeScalars.contains { $0.properties.isIdeographic }
            let hardLimit = cjk ? 90 : 220
            let count: Int
            let sentence = sentenceEnd(tail)
            if let end = sentence, end <= hardLimit { count = end }
            else if tail.count >= hardLimit,
                    let cut = clauseEnd(tail, allowFallback: true, cap: maxCharacters) { count = cut }
            else if let end = sentence { count = end }
            else if force || quiet { count = tail.count }
            else if age || tail.count >= maxCharacters {
                guard let end = clauseEnd(tail, allowFallback: hardDeadline || tail.count >= hardLimit,
                                          cap: maxCharacters) else { break }
                count = end
            } else { break }
            let end = start + phraseSafeCut(tail, proposed: count)
            let content = slice(start, end).trimmingCharacters(in: .whitespacesAndNewlines)
            let line = Line(id: UUID(), end: end, text: content)
            lines.append(line)
            lastEmission = (line.id, now, !force && sentence == nil && !isStandaloneAnswer(content))
            if Self.isMeaningful(content) { changes.append(line) }
            start = end
            pendingSince = start < text.count ? now : nil
        }
        return changes
    }

    /// Do not separate a glossary name or term when a deadline/size cut is needed.
    /// This only moves a cut; it never substitutes recognition text.
    private func phraseSafeCut(_ value: String, proposed: Int) -> Int {
        guard proposed < value.count else { return proposed }
        var spans: [(Int, Int)] = []
        for phrase in protectedPhrases.prefix(100) where !phrase.isEmpty && phrase.count <= 80 {
            let words = phrase.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—")))
                .filter { !$0.isEmpty }.map(NSRegularExpression.escapedPattern(for:))
            guard !words.isEmpty,
                  let regex = try? NSRegularExpression(pattern: words.joined(separator: "[\\s\\-–—]+"), options: .caseInsensitive) else { continue }
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
                guard let range = Range(match.range, in: value) else { continue }
                spans.append((value.distance(from: value.startIndex, to: range.lowerBound),
                              value.distance(from: value.startIndex, to: range.upperBound)))
            }
        }
        // Merge overlapping terms so one adjustment cannot split another term.
        var merged: [(Int, Int)] = []
        for span in spans.sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, span.0 < last.1 {
                merged[merged.count - 1].1 = max(last.1, span.1)
            } else { merged.append(span) }
        }
        if let span = merged.first(where: { $0.0 < proposed && proposed < $0.1 && $0.1 - $0.0 <= 180 }) {
            let minimum = value.unicodeScalars.contains { $0.properties.isIdeographic } ? 12 : 20
            return span.0 >= minimum ? span.0 : span.1
        }
        return proposed
    }

    private func isCorrection(_ value: String) -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["sorry", "no i mean", "actually", "i mean", "rather", "不对", "不是", "更正", "应该是", "抱歉"].contains { t.hasPrefix($0) }
    }

    private func isStandaloneAnswer(_ value: String) -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["yes", "no", "ok", "okay", "sure", "thanks", "thank you", "all right", "not yet", "not really", "go ahead", "好", "好的", "是", "是的", "不是", "可以", "不用", "谢谢", "不"].contains(t) { return true }
        return t.range(of: #"^[\p{Sc}]?[-+]?\d[\d,.]*[%％]?$"#, options: .regularExpression) != nil
    }

    private func isShortAnswer(_ value: String) -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needsContinuation(t) { return false }
        let words = t.split(whereSeparator: \.isWhitespace)
        if t.unicodeScalars.contains(where: { $0.properties.isIdeographic }) { return t.count <= 4 }
        return words.count <= 3
    }

    private func quietDelay(_ value: String) -> TimeInterval {
        if needsContinuation(value) { return 2.8 }
        return isShortAnswer(value) ? 0.8 : 1.4
    }

    private func needsContinuation(_ value: String) -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = t.split(whereSeparator: \.isWhitespace).map(String.init)
        let dangling: Set<String> = ["the", "a", "an", "of", "to", "and", "or", "but", "for", "with", "from", "by", "at", "in", "on", "than", "is", "are", "was", "were", "will", "would", "can", "could", "should", "must", "has", "have", "had", "keeps", "keep", "dr.", "mr.", "ms.", "prof."]
        if let last = words.last, dangling.contains(last) { return true }
        if let first = words.first, ["before", "after", "because", "although", "unless", "when", "if"].contains(first), words.count < 8, !t.contains(",") { return true }
        if t.unicodeScalars.contains(where: { $0.properties.isIdeographic }) {
            if ["的", "和", "与", "以及", "因为", "如果", "但是", "为", "将", "把", "在"].contains(where: { t.hasSuffix($0) }) { return true }
            if ["因为", "虽然", "如果", "当", "为了"].contains(where: { t.hasPrefix($0) }), t.count < 16, !t.contains("，") { return true }
        }
        return false
    }

    private func matchingSentenceBoundary(previous: String, updated: String) -> Int? {
        var remainder = previous, count = 0
        while let end = sentenceEnd(remainder) {
            count += 1; remainder = String(remainder.dropFirst(end)).trimmingCharacters(in:.whitespacesAndNewlines)
        }
        guard count > 0, remainder.isEmpty else { return nil }
        remainder = updated
        var boundary = 0
        for _ in 0..<count {
            guard let end = sentenceEnd(remainder) else { return nil }
            boundary += end; remainder = String(remainder.dropFirst(end))
        }
        return boundary
    }

    private func slice(_ start: Int, _ end: Int) -> String {
        String(text.dropFirst(start).prefix(max(0, end - start)))
    }

    private func sentenceEnd(_ text: String) -> Int? {
        let chars = Array(text)
        for (i, char) in chars.enumerated() where "。！？!?;；".contains(char) || char == "." {
            if char == "." {
                if i > 0, i + 1 < chars.count, chars[i-1].isNumber, chars[i+1].isNumber { continue }
                let word = String(chars[...i]).split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
                if ["mr.", "mrs.", "ms.", "dr.", "prof.", "e.g.", "i.e."].contains(word.lowercased()) { continue }
                if i + 1 < chars.count, chars[i + 1].isLetter { continue }
                if word.count == 2, word.first?.isLetter == true { continue }
                if word.range(of: #"^([A-Za-z]\.){2,}$"#, options: .regularExpression) != nil { continue }
            }
            return i + 1
        }
        return nil
    }

    private func beginsIndependentClause(_ text: String) -> Bool {
        let sample = String(text.split(whereSeparator: \.isWhitespace).prefix(10).joined(separator: " "))
        guard let first = sample.split(whereSeparator: \.isWhitespace).first else { return false }
        let subjects: Set<String> = ["i", "we", "you", "they", "he", "she", "it", "the", "a", "an", "this", "that", "these", "those"]
        guard subjects.contains(first.lowercased()) || first.first?.isUppercase == true else { return false }
        let tagger = NLTagger(tagSchemes: [.lexicalClass]); tagger.string = sample
        tagger.setLanguage(.english, range: sample.startIndex..<sample.endIndex)
        var hasVerb = false
        tagger.enumerateTags(in: sample.startIndex..<sample.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if tag == .verb { hasVerb = true; return false }; return true
        }
        return hasVerb
    }

    private func clauseEnd(_ text: String, allowFallback: Bool, cap requestedCap: Int) -> Int? {
        let cjk = text.unicodeScalars.contains { $0.properties.isIdeographic }
        let minimum = cjk ? 12 : 20
        let cap = cjk ? max(24, min(72, requestedCap)) : max(60, min(180, requestedCap))
        let chars = Array(text)
        if let comma = chars.indices.last(where: {
            $0 >= minimum && $0 < cap && ",，、:：".contains(chars[$0]) &&
            !($0 > 0 && $0 + 1 < chars.count && chars[$0-1].isNumber && chars[$0+1].isNumber) &&
            !needsContinuation(String(chars[..<$0]))
        }) {
            return comma + 1
        }
        if cjk {
            for connector in ["然后", "并且", "但是", "同时", "因此", "所以", "不过"] {
                if let range = text.range(of: connector) {
                    let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                    if offset >= minimum && offset < cap, !needsContinuation(String(text.prefix(offset))) { return offset }
                }
            }
        } else {
            let lower = text.lowercased()
            for connector in [" and ", " but ", " because ", " although ", " while ", " so that "] {
                if let range = lower.range(of: connector) {
                    let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
                    if offset >= minimum && offset < cap, !needsContinuation(String(text.prefix(offset))),
                       beginsIndependentClause(String(text[range.upperBound...])) { return offset }
                }
            }
        }
        guard allowFallback else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var boundaries: [Int] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let offset = text.distance(from: text.startIndex, to: range.upperBound)
            if offset >= minimum && offset <= cap { boundaries.append(offset) }
            return offset <= cap
        }
        // Keep the last word unfinished while the speaker is still talking.
        return boundaries.last(where: { $0 < text.count && !needsContinuation(String(text.prefix($0))) })
            ?? boundaries.last(where: { $0 < text.count })
    }
}
