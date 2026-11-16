import Foundation

/// A conservative bilingual fact check, never an editor of recognized speech.
/// Unsupported/ambiguous replies are held for review instead of guessing a value.
enum TranslationIntegrity {
    struct Number: Equatable {
        var value: String
        var range: NSRange
        var unit: String?
        var optionalOne = false
    }
    struct Facts {
        var text: String
        var numbers: [Number]
        var currencies: Set<String>
        var dates: Set<String>
    }

    static let instruction = """
    Translate only what the current text actually says. Do not complete fragments using earlier lines.
    Preserve every stated number, sign, decimal, date, time, amount and unit. Do not convert units or currencies.
    Do not supply an unstated currency, time, date, quantity, person or technical term from the reference.
    Keep explicit spoken corrections clear. A correction can retract the earlier value, but never invent a new one.
    If the current text ends at 'The meeting starts at', translate that fragment without filling in a time.
    """

    static func warnings(source: String, translation: String, terms: [GlossaryTerm] = [], direction: LanguageDirection = .englishToChinese) -> [String] {
        var a = facts(source)
        let b = facts(translation)
        var result: [String] = []
        let correction = matches(#"sorry\s*,?\s*(?:i\s+mean|make\s+that)|更正(?:一下)?|不对[，,]?|我是说"#, in: a.text).last
        if let correction,
           let old = a.numbers.lastIndex(where: { NSMaxRange($0.range) <= correction.range.location }),
           a.numbers.contains(where: { $0.range.location >= NSMaxRange(correction.range) }) {
            // Only the immediately retracted number may be omitted, not preceding facts.
            let retracted = a.numbers.remove(at: old)
            let full = facts(source)
            if numbersAgree(full.numbers, b.numbers) { a = full }
            else if let unit = retracted.unit, let next = a.numbers.firstIndex(where: { $0.range.location >= NSMaxRange(correction.range) }), a.numbers[next].unit == nil {
                a.numbers[next].unit = unit
            }
        }
        if !numbersAgree(a.numbers, b.numbers) { result.append("数字、正负号或时间与原文不一致") }
        if !b.currencies.isSubset(of: a.currencies) { result.append("译文增加了原文没有说明的币种") }
        let periods: [(String, String)] = [("am", #"\ba\.?m\.?\b|\bmorning\b|上午|早上|凌晨"#), ("pm", #"\bp\.?m\.?\b|\bafternoon\b|\bevening\b|\bnight\b|下午|晚上"#)]
        if !b.numbers.isEmpty, periods.contains(where: { matches($0.1, in: a.text).isEmpty && !matches($0.1, in: b.text).isEmpty }) { result.append("译文补入了原文没有说明的时段") }
        if correction == nil, !a.dates.isEmpty, !b.dates.isEmpty, a.dates != b.dates { result.append("日期与原文不一致") }
        func unitCounts(_ list: [Number]) -> [String: Int] {
            list.filter { $0.unit != nil }.reduce(into: [:]) { $0[$1.value + "|" + $1.unit!, default: 0] += 1 }
        }
        if unitCounts(a.numbers) != unitCounts(b.numbers) { result.append("金额或计量单位与原文不一致") }
        let relevant = terms.filter { $0.occurs(in: source, direction: direction) }
        let explicitTargets = Set(relevant.map { $0.pair(for: direction).target.lowercased() })
        // Known names are reference data, not permission to invent a missing name.
        for term in terms where !term.occurs(in: source, direction: direction) {
            let preferred = term.pair(for: direction).target
            if explicitTargets.contains(preferred.lowercased()) { continue }
            // A currency/unit already present as a symbol or abbreviation is not
            // an invented term merely because a glossary uses another spelling.
            if let unit = facts("1 " + preferred).numbers.first?.unit,
               a.currencies.contains(unit) || a.numbers.contains(where: { $0.unit == unit }) { continue }
            if preferred.count >= 2, containsTerm(preferred, in: translation),
               !containsTerm(preferred, in: source) {
                result.append("译文补入了原文没有说出的人名或术语")
                break
            }
        }
        for term in relevant where !containsTerm(term.pair(for: direction).target, in: translation) {
            result.append("已说出的名称或术语没有采用本场指定译法")
            break
        }
        if !relevant.isEmpty {
            func residue(_ text: String, target: Bool) -> String {
                var value = text
                for term in relevant.sorted(by: { $0.pair(for: direction).source.count > $1.pair(for: direction).source.count }) {
                    let pair = term.pair(for: direction)
                    let phrase = target ? pair.target : pair.source
                    let pattern = phrase.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—")))
                        .filter { !$0.isEmpty }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: #"[\s\-–—]+"#)
                    value = replacing(pattern, in: value) { _ in " " }
                }
                value = replacing(#"\b(?:and|with)\b|与|和|及"#, in: value) { _ in " " }
                return value.filter { $0.isLetter || $0.isNumber }
            }
            if residue(source, target: false).isEmpty, !residue(translation, target: true).isEmpty {
                result.append("原文只是名称列表，译文补入了动作或关系")
            }
        }
        return Array(Set(result)).sorted()
    }

    static func containsFacts(_ text: String) -> Bool {
        let f = facts(text)
        return f.numbers.contains { !$0.optionalOne } || !f.currencies.isEmpty
    }

    private static func numbersAgree(_ a: [Number], _ b: [Number]) -> Bool {
        func counts(_ list: [Number], required: Bool) -> [String: Int] {
            list.filter { !required || !$0.optionalOne }.reduce(into: [:]) { $0[$1.value, default: 0] += 1 }
        }
        let allA = counts(a, required: false), allB = counts(b, required: false)
        return counts(a, required: true).allSatisfy { allB[$0.key, default: 0] >= $0.value }
            && counts(b, required: true).allSatisfy { allA[$0.key, default: 0] >= $0.value }
    }

    static func facts(_ input: String) -> Facts {
        var s = input.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "零下", with: "-")
            .replacingOccurrences(of: "负", with: "-").replacingOccurrences(of: "百分之", with: "% ")
        for idiom in ["一起", "一直", "一致", "一样", "一旦", "一定", "一些", "一切", "万一", "唯一", "统一", "一会儿", "一点儿", "之一"] { s = s.replacingOccurrences(of: idiom, with: " ") }
        s = replacing(#"\b(?:no one|one another|one of)\b"#, in: s) { _ in " " }
        s = replacing(#"(^|[.!?]\s+)(?:first|second|third)\s*[,，]"#, in: s) { $0[1] }
        s = replacing(#"(^|[。！？]\s*)第[一二三四五六七八九十]+[，,、]"#, in: s) { $0[1] }
        s = replacing(#"\b(?:a|an)\s+(?=(?:[a-z]+\s+){0,2}(?:box|kilometer|meter|gram|dollar|euro|pound|hour|minute|second|day)\b)"#, in: s) { _ in "1 " }
        s = replacing(#"(\d+)(?:st|nd|rd|th)\b"#, in: s) { $0[1] }
        s = replacing(#"\b(?:minus|negative)\s*(?=\d)"#, in: s) { _ in "-" }
        s = replacing(#"(\d)(usd|cny|eur|rmb|kg|km|cm|mm|ml|gb|mb|tb|m|g|l)(?![a-z])"#, in: s) { $0[1] + " " + $0[2] }
        s = replacing(#"\b(usd|cny|eur|rmb)(?=\d)"#, in: s) { $0[1] + " " }
        let names = Array(english.keys).sorted { $0.count > $1.count }.joined(separator: "|")
        s = replacing("\\b(?:" + names + ")(?:[ -]+(?:" + names + "))*\\b", in: s) { parts in
            englishNumbers(parts[0]) ?? parts[0]
        }
        s = replacing(#"([零〇一二两三四五六七八九十百千万亿\d]+)点半"#, in: s) { (chinese($0[1]) ?? $0[1]) + ":30" }
        s = replacing(#"([零〇一二两三四五六七八九十百千万亿\d]+)点([零〇一二两三四五六七八九十百千万亿\d]+)分"#, in: s) { (chinese($0[1]) ?? $0[1]) + ":" + (chinese($0[2]) ?? $0[2]) }
        s = replacing(#"(?<![\d.])[零〇一二两三四五六七八九十百千万亿]+(?:点[零〇一二两三四五六七八九]+)?"#, in: s) { chinese($0[0]) ?? $0[0] }
        s = replacing(#"\bat\s+(\d{1,2})\s+(\d{2})\b"#, in: s) { "at " + $0[1] + ":" + $0[2] }
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        for (i, month) in months.enumerated() {
            s = replacing("\\b" + month + "\\s+(\\d{1,2})(?:,?\\s+(\\d{4}))?", in: s) { p in
                (p[2].isEmpty ? "" : p[2] + "年") + String(i + 1) + "月" + p[1] + "日"
            }
        }
        var dates = Set<String>()
        for m in matches(#"(\d{4})\s*(?:年|[-/])\s*(\d{1,2})\s*(?:月|[-/])\s*(\d{1,2})"#, in: s) {
            let p = groups(m, in: s); dates.insert([p[1], p[2], p[3]].map { canonical($0) }.joined(separator: "-"))
        }
        let currencyPatterns: [(String, String)] = [
            ("dollar", #"\$|\busd\b|\bu\.?s\.?\s+dollars?\b|\bdollars?\b|美元|美金"#),
            ("yuan", #"¥|￥|\bcny\b|\brmb\b|\byuan\b|人民币|(?<![美欧加澳日港新])元"#),
            ("euro", #"€|\beur\b|\beuros?\b|欧元"#),
            ("pound", #"£|\bgbp\b|\bpounds?\b|英镑"#)
        ]
        var currencies = Set<String>()
        for (kind, pattern) in currencyPatterns where !matches(pattern, in: s).isEmpty { currencies.insert(kind) }
        let units = currencyPatterns + [
            ("box", #"\bbox(?:es)?\b|盒子|箱子|盒|箱"#),
            ("km", #"\bkilomet(?:er|re)s?\b|\bkm\b|公里|千米"#),
            ("m", #"\bmet(?:er|re)s?\b|\bm\b|(?<!厘|毫|千)米"#),
            ("kg", #"\bkilograms?\b|\bkg\b|公斤|千克"#),
            ("g", #"\bgrams?\b|\bg\b|(?<!千|毫)克"#),
            ("hour", #"\bhours?\b|小时|钟头"#),
            ("minute", #"\bminutes?\b|分钟"#),
            ("second", #"\bseconds?\b|秒"#),
            ("day", #"\bdays?\b|天"#),
            ("celsius", #"\bcelsius\b|°\s*c\b|摄氏度|摄氏"#),
            ("fahrenheit", #"\bfahrenheit\b|°\s*f\b|华氏度|华氏"#),
            ("percent", #"%|\bpercent\b|百分比"#)
        ]
        let numericMatches = matches(#"(?<![\p{L}\p{N}])[-+]?\d+(?:,\d{3})*(?:\.\d+)?(?:\s*[万亿])?(?![\p{L}\p{N}])"#, in: s)
        // Chinese units are letters too, so admit adjacent CJK while excluding product IDs.
        let cjkMatches = matches(#"[-+]?\d+(?:,\d{3})*(?:\.\d+)?(?:\s*[万亿])?"#, in: s)
        let ns = s as NSString
        var numbers: [Number] = []
        for m in cjkMatches {
            let r = m.range
            let left = r.location > 0 ? ns.substring(with: NSRange(location: r.location - 1, length: 1)) : ""
            let right = NSMaxRange(r) < ns.length ? ns.substring(with: NSRange(location: NSMaxRange(r), length: 1)) : ""
            if (left.range(of: #"[a-z]"#, options: .regularExpression) != nil || right.range(of: #"[a-z]"#, options: .regularExpression) != nil) && !numericMatches.contains(where: { $0.range == r }) { continue }
            let next = cjkMatches.first { $0.range.location >= NSMaxRange(r) }?.range.location ?? ns.length
            let before = numbers.last.map { NSMaxRange($0.range) } ?? 0
            let tail = ns.substring(with: NSRange(location: NSMaxRange(r), length: min(24, next - NSMaxRange(r))))
            let head = ns.substring(with: NSRange(location: max(before, r.location - 8), length: r.location - max(before, r.location - 8)))
            var unit = currencyPatterns.first { !matches("(?:" + $0.1 + ")\\s*$", in: head).isEmpty }?.0
            if unit == nil {
                let candidates = units.compactMap { kind, pattern -> (String, Int)? in
                    let prefix = "^(?:\\s|degrees?\\s|度|个|(?:红|蓝|绿|黄|白|黑)色|[a-z]+\\s){0,3}"
                    guard let match = matches(prefix + "(" + pattern + ")", in: tail).first else { return nil }
                    return (kind, match.range(at: 1).location)
                }
                unit = candidates.min(by: { $0.1 < $1.1 })?.0
            }
            if unit == nil, head.hasSuffix("% ") { unit = "percent" }
            let value = canonical(ns.substring(with: r))
            let optional = value == "1" && unit == nil && (tail.hasPrefix("个") || tail.hasPrefix("场") || tail.hasPrefix("次"))
            numbers.append(Number(value: value, range: r, unit: unit, optionalOne: optional))
        }
        return Facts(text: s, numbers: numbers, currencies: currencies, dates: dates)
    }

    private static func canonical(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        var multiplier = Decimal(1)
        if s.hasSuffix("万") { multiplier = 10000; s.removeLast() }
        if s.hasSuffix("亿") { multiplier = 100000000; s.removeLast() }
        if s.count >= 3, s.hasPrefix("00"), !s.contains(".") { return "id:" + s }
        guard let n = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return s }
        return NSDecimalNumber(decimal: n * multiplier).stringValue
    }

    private static func containsTerm(_ term: String, in text: String) -> Bool {
        if term.contains(where: { $0.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) }) {
            return text.localizedCaseInsensitiveContains(term)
        }
        // Chinese prose commonly touches Latin names without spaces. Retain
        // Latin word boundaries without rejecting 今天讨论Kubernetes or AI模型.
        let pattern = #"(?<![\p{Latin}\p{N}_])"# + NSRegularExpression.escapedPattern(for: term) + #"(?![\p{Latin}\p{N}_])"#
        return !matches(pattern, in: text).isEmpty
    }

    private static let english: [String: Int] = ["zero":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,"eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,"eighteen":18,"nineteen":19,"twenty":20,"thirty":30,"forty":40,"fifty":50,"sixty":60,"seventy":70,"eighty":80,"ninety":90,"first":1,"third":3,"fourth":4,"fifth":5,"sixth":6,"seventh":7,"eighth":8,"ninth":9,"tenth":10,"eleventh":11,"twelfth":12,"thirteenth":13,"fourteenth":14,"fifteenth":15,"sixteenth":16,"seventeenth":17,"eighteenth":18,"nineteenth":19,"twentieth":20,"thirtieth":30,"hundred":100,"thousand":1000,"million":1000000,"billion":1000000000,"and":-1,"point":-2,"minus":-3,"negative":-3]

    private static func englishNumbers(_ raw: String) -> String? {
        let words = raw.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
        guard words.contains(where: { (english[$0] ?? -1) >= 0 }) else { return nil }
        if words.count >= 2, ["nineteen", "twenty"].contains(words[0]), let next = english[words[1]], next >= 10 && next < 100,
           let rest = englishNumbers(words.dropFirst().joined(separator: " ")), let suffix = Int(rest), suffix < 100 {
            return String((english[words[0]] ?? 0) * 100 + suffix)
        }
        var values: [String] = [], total: Decimal = 0, group: Decimal = 0, previous: Int?, negative = false
        var fraction: String? = nil
        func flush() { values.append((negative ? "-" : "") + NSDecimalNumber(decimal: total + group).stringValue + (fraction.map { "." + $0 } ?? "")); total = 0; group = 0; previous = nil; fraction = nil; negative = false }
        for word in words {
            guard let value = english[word] else { continue }
            if value == -3 { negative = true; continue }
            if value == -2 { fraction = ""; continue }
            if value == -1 { continue }
            if fraction != nil { guard value < 10 else { return nil }; fraction! += String(value); continue }
            if value == 100 { group = max(1, group) * 100 }
            else if value >= 1000 { total += max(1, group) * Decimal(value); group = 0 }
            else {
                if let prior = previous, prior < 100, !(prior >= 20 && prior % 10 == 0 && value < 10) { flush() }
                group += Decimal(value)
            }
            previous = value
        }
        flush()
        return values.joined(separator: " ")
    }

    private static func chinese(_ raw: String) -> String? {
        if Decimal(string: raw) != nil { return raw }
        let parts = raw.split(separator: "点", omittingEmptySubsequences: false)
        let digits: [Character: Int] = ["零":0,"〇":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
        let units: [Character: Decimal] = ["十":10,"百":100,"千":1000,"万":10000,"亿":100000000]
        var total: Decimal = 0, section: Decimal = 0, number: Decimal = 0
        let whole = String(parts[0])
        if !whole.contains(where: { units[$0] != nil }) {
            guard whole.allSatisfy({ digits[$0] != nil }) else { return nil }
            return whole.map { String(digits[$0]!) }.joined() + (parts.count == 2 ? "." + parts[1].compactMap { digits[$0].map(String.init) }.joined() : "")
        }
        for c in whole {
            if let d = digits[c] { number = Decimal(d) }
            else if let u = units[c] {
                if u >= 10000 { section += number; total = (total + max(1, section)) * u; section = 0 }
                else { section += max(1, number) * u }
                number = 0
            } else { return nil }
        }
        let suffix = parts.count == 2 ? "." + parts[1].compactMap { digits[$0].map(String.init) }.joined() : ""
        return NSDecimalNumber(decimal: total + section + number).stringValue + suffix
    }

    private static let regexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 128
        return cache
    }()
    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        let key = pattern as NSString
        let regex: NSRegularExpression
        if let cached = regexCache.object(forKey: key) { regex = cached }
        else {
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
            regexCache.setObject(compiled, forKey: key)
            regex = compiled
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
    private static func groups(_ match: NSTextCheckingResult, in text: String) -> [String] {
        (0..<match.numberOfRanges).map { i in Range(match.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }
    private static func replacing(_ pattern: String, in text: String, with replacement: ([String]) -> String) -> String {
        var output = text
        for match in matches(pattern, in: text).reversed() {
            if let range = Range(match.range, in: output) { output.replaceSubrange(range, with: replacement(groups(match, in: text))) }
        }
        return output
    }
}
