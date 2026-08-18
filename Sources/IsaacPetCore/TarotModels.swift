import Foundation

public struct TarotCard: Equatable, Identifiable, Sendable {
    public let id: Int
    public let romanNumeral: String
    public let name: String
    public let gameMessage: String
    public let reading: String
    /// Packed RGB value used by the placeholder renderer; no card artwork is embedded yet.
    public let placeholderRGB: UInt32

    public init(
        id: Int,
        romanNumeral: String,
        name: String,
        gameMessage: String,
        reading: String,
        placeholderRGB: UInt32
    ) {
        self.id = id
        self.romanNumeral = romanNumeral
        self.name = name
        self.gameMessage = gameMessage
        self.reading = reading
        self.placeholderRGB = placeholderRGB
    }
}

public enum TarotDeck {
    /// The 22 Major Arcana cards documented for The Binding of Isaac: Rebirth.
    /// The meanings below are entertainment-only interpretations, not game effects.
    public static let majorArcana: [TarotCard] = [
        TarotCard(id: 0, romanNumeral: "0", name: "愚者 · The Fool", gameMessage: "Where journey begins", reading: "今天适合迈出第一步，别被未知吓住。", placeholderRGB: 0x4D6FAE),
        TarotCard(id: 1, romanNumeral: "I", name: "魔术师 · The Magician", gameMessage: "May you never miss your goal", reading: "把注意力收回来，你手上的工具已经够用了。", placeholderRGB: 0x9B59B6),
        TarotCard(id: 2, romanNumeral: "II", name: "女祭司 · The High Priestess", gameMessage: "Mother is watching you", reading: "先听听直觉，再决定要不要立刻行动。", placeholderRGB: 0x526A8D),
        TarotCard(id: 3, romanNumeral: "III", name: "皇后 · The Empress", gameMessage: "May your rage bring power", reading: "照顾好自己的能量，创造力会慢慢回到手里。", placeholderRGB: 0xC05A7A),
        TarotCard(id: 4, romanNumeral: "IV", name: "皇帝 · The Emperor", gameMessage: "Challenge me!", reading: "给今天设一个清晰边界，稳稳推进最重要的一步。", placeholderRGB: 0xB06B36),
        TarotCard(id: 5, romanNumeral: "V", name: "教皇 · The Hierophant", gameMessage: "Two prayers for the lost", reading: "向可信的人求助，经验能让路变得更短。", placeholderRGB: 0x6D8B74),
        TarotCard(id: 6, romanNumeral: "VI", name: "恋人 · The Lovers", gameMessage: "May you prosper and be in good health", reading: "今天的选择重在真诚，也别忘了照顾关系。", placeholderRGB: 0xC65D70),
        TarotCard(id: 7, romanNumeral: "VII", name: "战车 · The Chariot", gameMessage: "May nothing stand before you", reading: "确定方向后就向前，短时间专注会带来突破。", placeholderRGB: 0x3F7F8F),
        TarotCard(id: 8, romanNumeral: "VIII", name: "正义 · Justice", gameMessage: "May your future become balanced", reading: "把任务和休息重新称一称，公平地分配精力。", placeholderRGB: 0x7289A8),
        TarotCard(id: 9, romanNumeral: "IX", name: "隐者 · The Hermit", gameMessage: "May you see what life has to offer", reading: "给自己一段安静时间，答案可能在噪音之外。", placeholderRGB: 0x5C677D),
        TarotCard(id: 10, romanNumeral: "X", name: "命运之轮 · Wheel of Fortune", gameMessage: "Spin the wheel of destiny", reading: "变化正在发生，留一点弹性给意外的好事。", placeholderRGB: 0xA87939),
        TarotCard(id: 11, romanNumeral: "XI", name: "力量 · Strength", gameMessage: "May your power bring rage", reading: "真正的力量是稳住情绪，再处理眼前的问题。", placeholderRGB: 0xC58B43),
        TarotCard(id: 12, romanNumeral: "XII", name: "倒吊人 · The Hanged Man", gameMessage: "May you find enlightenment", reading: "换一个角度看，暂缓并不等于停滞。", placeholderRGB: 0x557C74),
        TarotCard(id: 13, romanNumeral: "XIII", name: "死神 · Death", gameMessage: "Lay waste to all that oppose you", reading: "结束一个消耗你的旧循环，给新的安排腾位置。", placeholderRGB: 0x454B66),
        TarotCard(id: 14, romanNumeral: "XIV", name: "节制 · Temperance", gameMessage: "May you be pure in heart", reading: "慢一点、均匀一点，今天适合恢复节奏。", placeholderRGB: 0x4F8C8D),
        TarotCard(id: 15, romanNumeral: "XV", name: "恶魔 · The Devil", gameMessage: "Revel in the power of darkness", reading: "看见让你上瘾的诱惑，给自己留一个主动选择。", placeholderRGB: 0x7D3C5A),
        TarotCard(id: 16, romanNumeral: "XVI", name: "高塔 · The Tower", gameMessage: "Destruction brings creation", reading: "计划有变时先保住核心，重建也能带来新解法。", placeholderRGB: 0xA64B3C),
        TarotCard(id: 17, romanNumeral: "XVII", name: "星星 · The Stars", gameMessage: "May you find what you desire", reading: "保留一点希望，今天适合为长期目标点灯。", placeholderRGB: 0x4E739E),
        TarotCard(id: 18, romanNumeral: "XVIII", name: "月亮 · The Moon", gameMessage: "May you find all you have lost", reading: "信息还不完整，先核实再下结论。", placeholderRGB: 0x454A79),
        TarotCard(id: 19, romanNumeral: "XIX", name: "太阳 · The Sun", gameMessage: "May the light heal and enlighten you", reading: "把重要的事放到明处，清晰会带来行动力。", placeholderRGB: 0xD09A3A),
        TarotCard(id: 20, romanNumeral: "XX", name: "审判 · Judgement", gameMessage: "Judge lest ye be judged", reading: "回看一次最近的决定，然后给自己一个新答案。", placeholderRGB: 0x8D6656),
        TarotCard(id: 21, romanNumeral: "XXI", name: "世界 · The World", gameMessage: "Open your eyes and see", reading: "完成一个阶段，记得停下来确认自己已经走了很远。", placeholderRGB: 0x567D63),
    ]
}

public enum TarotDrawPolicy {
    public static func dailyCard(
        for date: Date = Date(),
        calendar rawCalendar: Calendar = .current
    ) -> TarotCard {
        var calendar = rawCalendar
        calendar.timeZone = rawCalendar.timeZone
        let startOfDay = calendar.startOfDay(for: date)
        let reference = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? startOfDay
        let offset = calendar.dateComponents([.day], from: reference, to: startOfDay).day ?? 0
        let index = ((offset % TarotDeck.majorArcana.count) + TarotDeck.majorArcana.count) % TarotDeck.majorArcana.count
        return TarotDeck.majorArcana[index]
    }

    public static func randomCard(excluding excludedID: Int? = nil) -> TarotCard {
        let candidates = TarotDeck.majorArcana.filter { $0.id != excludedID }
        return candidates.randomElement() ?? TarotDeck.majorArcana[0]
    }
}
