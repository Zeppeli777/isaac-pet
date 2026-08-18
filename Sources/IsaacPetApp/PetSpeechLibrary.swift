import Foundation

enum PetSpeechLibrary {
    private static let phrases = [
        "嗨！今天也要加油 :)",
        "记得休息一下。",
        "我会在这里陪你。",
        "先完成最小的一步吧！",
        "喝口水？",
        "今天想做什么？",
    ]

    private static let expressions = [
        ":)",
        "♥",
        "...",
        "!",
        "T_T",
        "o_o",
        ":P",
    ]

    static func randomPhrase() -> String {
        phrases.randomElement() ?? "嗨！ :)"
    }

    static func randomExpression() -> String {
        expressions.randomElement() ?? ":)"
    }
}
