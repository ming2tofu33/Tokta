import Foundation

/// 한국어 조사(은/는, 이/가). 이름 끝 글자에 받침이 있는지로 고른다. 영문은 한국어로 읽었을 때 기준으로 대강 맞춘다.
enum Josa {
    static func hasBatchim(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespaces).unicodeScalars.last else { return false }
        let value = last.value
        if (0xAC00...0xD7A3).contains(value) { return (value - 0xAC00) % 28 != 0 }
        let c = Character(last)
        // 대문자 한 글자는 알파벳 이름으로 읽는다: 엘·엠·엔·알
        if c.isUppercase { return "LMNR".contains(c) }
        if c.isNumber { return "013678".contains(c) }
        return "lmnkpbgt".contains(c)
    }

    static func topic(_ word: String) -> String { hasBatchim(word) ? "은" : "는" }
    static func subject(_ word: String) -> String { hasBatchim(word) ? "이" : "가" }
}
