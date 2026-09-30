import Foundation

/// The 22 major arcana and their reversed counterparts, transcribed from the
/// fan wiki (https://isaac.huijiwiki.com/wiki/卡牌) for the local card draw.
public struct TarotCard: Equatable, Identifiable, Sendable {
    public let numeralIndex: Int
    public let numeral: String
    public let nameZH: String
    public let nameEN: String
    public let englishName: String
    public let pickupZH: String
    public let pickupEN: String
    public let charge: Int
    /// Unlock condition text; only the reversed cards carry one.
    public let unlock: String?
    /// Lines of the primary "使用后" effect, without the leading label.
    public let effectLines: [String]
    public let isReversed: Bool

    public var id: String { "\(isReversed ? "reversed" : "normal")-\(numeralIndex)" }
    /// Bundle resource stem of the card icon inside the Cards folder.
    public var iconResource: String {
        let prefix = isReversed ? "TarotReversed" : "Tarot"
        return prefix + String(format: "%02d", numeralIndex)
    }

    public init(
        numeralIndex: Int,
        numeral: String,
        nameZH: String,
        nameEN: String,
        englishName: String,
        pickupZH: String,
        pickupEN: String,
        charge: Int,
        unlock: String? = nil,
        effectLines: [String],
        isReversed: Bool = false
    ) {
        self.numeralIndex = numeralIndex
        self.numeral = numeral
        self.nameZH = nameZH
        self.nameEN = nameEN
        self.englishName = englishName
        self.pickupZH = pickupZH
        self.pickupEN = pickupEN
        self.charge = charge
        self.unlock = unlock
        self.effectLines = effectLines
        self.isReversed = isReversed
    }
}

public enum TarotDeck {
    public static let arcanaCount = 22

    public static let cards: [TarotCard] = [
        TarotCard(
            numeralIndex: 0,
            numeral: "0",
            nameZH: "0-愚者",
            nameEN: "0 - The Fool",
            englishName: "The Fool",
            pickupZH: "旅程开始之地",
            pickupEN: "Where journey begins",
            charge: 2,
            effectLines: [
                "传送到当前层的初始房间。",
            ],
        ),
        TarotCard(
            numeralIndex: 1,
            numeral: "I",
            nameZH: "I-魔术师",
            nameEN: "I - The Magician",
            englishName: "The Magician",
            pickupZH: "愿您弹无虚发",
            pickupEN: "May you never miss your goal",
            charge: 2,
            effectLines: [
                "在当前房间中，获得 弯勺魔术的效果。",
                "射程+3.00",
                "多个I-魔术师的该效果不叠加。",
            ],
        ),
        TarotCard(
            numeralIndex: 2,
            numeral: "II",
            nameZH: "II-女祭司",
            nameEN: "II - The High Priestess",
            englishName: "The High Priestess",
            pickupZH: "妈妈在注视你",
            pickupEN: "Mother is watching you",
            charge: 2,
            effectLines: [
                "生成妈妈的脚踩踏敌人，对房间中血量最高的敌人造成300.00点伤害。",
                "如果房间中没有敌人，则会瞄准角色进行一次踩踏。",
                "房间未清理完成时，踩踏可以打开房间中未上锁的门。",
            ],
        ),
        TarotCard(
            numeralIndex: 3,
            numeral: "III",
            nameZH: "III-皇后",
            nameEN: "III - The Empress",
            englishName: "The Empress",
            pickupZH: "愿您怒中生力",
            pickupEN: "May your rage bring power",
            charge: 3,
            effectLines: [
                "在当前房间中，获得1层巴比伦大淫妇状态。",
            ],
        ),
        TarotCard(
            numeralIndex: 4,
            numeral: "IV",
            nameZH: "IV-皇帝",
            nameEN: "IV - The Emperor",
            englishName: "The Emperor",
            pickupZH: "挑战我！",
            pickupEN: "Challenge me!",
            charge: 4,
            effectLines: [
                "传送到当前层的头目房。",
                "如果当前层有多个头目房，则随机传送到其中一个。",
                "如果当前层没有头目房，则随机传送到一个房间。",
            ],
        ),
        TarotCard(
            numeralIndex: 5,
            numeral: "V",
            nameZH: "V-教皇",
            nameEN: "V - The Hierophant",
            englishName: "The Hierophant",
            pickupZH: "为迷途者祷告两次",
            pickupEN: "Two prayers for the lost",
            charge: 12,
            effectLines: [
                "生成2个魂心。",
            ],
        ),
        TarotCard(
            numeralIndex: 6,
            numeral: "VI",
            nameZH: "VI-恋人",
            nameEN: "VI - The Lovers",
            englishName: "The Lovers",
            pickupZH: "愿您健康繁盛",
            pickupEN: "May you prosper and be in good health",
            charge: 6,
            effectLines: [
                "生成2个红心。",
            ],
        ),
        TarotCard(
            numeralIndex: 7,
            numeral: "VII",
            nameZH: "VII-战车",
            nameEN: "VII - The Chariot",
            englishName: "The Chariot",
            pickupZH: "愿您所向披靡",
            pickupEN: "May nothing stand before you",
            charge: 3,
            effectLines: [
                "触发1次 彩虹独角兽的使用效果。",
            ],
        ),
        TarotCard(
            numeralIndex: 8,
            numeral: "VIII",
            nameZH: "VIII-正义",
            nameEN: "VIII - Justice",
            englishName: "Justice",
            pickupZH: "愿您仕途平稳",
            pickupEN: "May your future become balanced",
            charge: 6,
            effectLines: [
                "生成1个随机心。",
                "生成1个随机硬币。",
                "生成1个随机钥匙。",
                "生成1个随机炸弹。",
            ],
        ),
        TarotCard(
            numeralIndex: 9,
            numeral: "IX",
            nameZH: "IX-隐者",
            nameEN: "IX - The Hermit",
            englishName: "The Hermit",
            pickupZH: "愿您看破红尘",
            pickupEN: "May you see what life has to offer",
            charge: 2,
            effectLines: [
                "传送到当前层的商店。",
            ],
        ),
        TarotCard(
            numeralIndex: 10,
            numeral: "X",
            nameZH: "X-命运之轮",
            nameEN: "X - Wheel of Fortune",
            englishName: "Wheel of Fortune",
            pickupZH: "转动命运之轮",
            pickupEN: "Spin the wheel of destiny",
            charge: 4,
            effectLines: [
                "66%概率生成1个赌博机，33%概率生成1个预言机，1%概率生成1个夹娃娃机。",
            ],
        ),
        TarotCard(
            numeralIndex: 11,
            numeral: "XI",
            nameZH: "XI-力量",
            nameEN: "XI - Strength",
            englishName: "Strength",
            pickupZH: "愿您力中唤怒",
            pickupEN: "May your power bring rage",
            charge: 3,
            effectLines: [
                "在当前房间中，获得 魔法蘑菇的被动效果和1个心之容器。",
            ],
        ),
        TarotCard(
            numeralIndex: 12,
            numeral: "XII",
            nameZH: "XII-倒吊人",
            nameEN: "XII - The Hanged Man",
            englishName: "The Hanged Man",
            pickupZH: "愿您寻得启示",
            pickupEN: "May you find enlightenment",
            charge: 3,
            effectLines: [
                "在当前房间中，获得 超凡升天的效果。",
            ],
        ),
        TarotCard(
            numeralIndex: 13,
            numeral: "XIII",
            nameZH: "XIII-死亡",
            nameEN: "XIII - Death",
            englishName: "Death",
            pickupZH: "毁灭忤逆尔者",
            pickupEN: "Lay waste to all that oppose you",
            charge: 3,
            effectLines: [
                "对当前房间中的所有敌人造成40.00点伤害。",
            ],
        ),
        TarotCard(
            numeralIndex: 14,
            numeral: "XIV",
            nameZH: "XIV-节制",
            nameEN: "XIV - Temperance",
            englishName: "Temperance",
            pickupZH: "愿您内心纯洁",
            pickupEN: "May you be pure in heart",
            charge: 6,
            effectLines: [
                "生成1个献血机。",
                "改为生成1个恶魔乞丐。",
            ],
        ),
        TarotCard(
            numeralIndex: 15,
            numeral: "XV",
            nameZH: "XV-恶魔",
            nameEN: "XV - The Devil",
            englishName: "The Devil",
            pickupZH: "沉迷黑暗之力",
            pickupEN: "Revel in the power of darkness",
            charge: 3,
            effectLines: [
                "在当前房间中，触发 彼列之书的使用效果。",
            ],
        ),
        TarotCard(
            numeralIndex: 16,
            numeral: "XVI",
            nameZH: "XVI-塔",
            nameEN: "XVI - The Tower",
            englishName: "The Tower",
            pickupZH: "毁灭带来创造",
            pickupEN: "Destruction brings creation",
            charge: 3,
            effectLines: [
                "触发1次 无政府主义者食谱的使用效果。",
            ],
        ),
        TarotCard(
            numeralIndex: 17,
            numeral: "XVII",
            nameZH: "XVII-星星",
            nameEN: "XVII - The Stars",
            englishName: "The Stars",
            pickupZH: "愿你心想事成",
            pickupEN: "May you find what you desire",
            charge: 2,
            effectLines: [
                "传送到当前层的宝箱房。",
                "如果当前楼层有星象房，则传送到当前层的星象房。",
            ],
        ),
        TarotCard(
            numeralIndex: 18,
            numeral: "XVIII",
            nameZH: "XVIII-月亮",
            nameEN: "XVIII - The Moon",
            englishName: "The Moon",
            pickupZH: "愿你失而复得",
            pickupEN: "May you find all you have lost",
            charge: 2,
            effectLines: [
                "传送到当前层的隐藏房。",
            ],
        ),
        TarotCard(
            numeralIndex: 19,
            numeral: "XIX",
            nameZH: "XIX-太阳",
            nameEN: "XIX - The Sun",
            englishName: "The Sun",
            pickupZH: "愿光赐你启示",
            pickupEN: "May the light heal and enlighten you",
            charge: 12,
            effectLines: [
                "回复所有红心容器。",
                "对当前房间中所有敌人造成100.00点伤害。",
                "在地图上显示除超级隐藏房与究极隐藏房以外所有的房间的图标和位置。",
                "解除当前楼层的黑暗诅咒！。",
            ],
        ),
        TarotCard(
            numeralIndex: 20,
            numeral: "XX",
            nameZH: "XX-审判",
            nameEN: "XX - Judgement",
            englishName: "Judgement",
            pickupZH: "为避审而审判",
            pickupEN: "Judge lest ye be judged",
            charge: 6,
            effectLines: [
                "随机生成1个乞丐、恶魔乞丐、钥匙大师或炸弹乞丐。",
                "权重概率事件4864%生成1个乞丐。2533.33%生成1个恶魔乞丐。11.33%生成1个钥匙大师。11.33%生成1个炸弹乞丐。75合计权重",
                "使用后：",
                "随机生成1个乞丐、恶魔乞丐、钥匙大师、炸弹乞丐、电池乞丐或腐烂乞丐。",
                "权重概率事件4661.33%生成1个乞丐。2533.33%生成1个恶魔乞丐。11.33%生成1个钥匙大师。11.33%生成1个炸弹乞丐。11.33%生成1个腐烂乞丐。11.33%生成1个电池乞丐。75合计权重",
            ],
        ),
        TarotCard(
            numeralIndex: 21,
            numeral: "XXI",
            nameZH: "XXI-世界",
            nameEN: "XXI - The World",
            englishName: "The World",
            pickupZH: "睁眼洞察世界",
            pickupEN: "Open your eyes and see",
            charge: 3,
            effectLines: [
                "在地图上显示除超级隐藏房与究极隐藏房以外所有房间的图标和位置。",
            ],
        ),
        TarotCard(
            numeralIndex: 0,
            numeral: "0",
            nameZH: "0-愚者？",
            nameEN: "0 - The Fool?",
            englishName: "The Fool",
            pickupZH: "一切从零开始",
            pickupEN: "Let go and move on",
            charge: 12,
            unlock: "愚者：用堕化游魂获得困难贪婪模式通关标记。",
            effectLines: [
                "为角色保留半颗心的血量，失去剩余的所有心，并生成等量的对应掉落物。",
                "失去所有硬币、炸弹和钥匙，并生成等量的对应掉落物。",
                "如果硬币、炸弹和钥匙达到一定数量则改为生成对应的底座道具（如 25美分、 轰！、 骷髅钥匙、 烟火盛宴等）。",
                "掉落物和底座道具均会以最少的个数形式生成（如角色拥有110个硬币，使用卡牌后将会生成1个铸币和 一美元）。",
                "丢弃所有饰品、卡牌和胶囊。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 1,
            numeral: "I",
            nameZH: "I-魔术师？",
            nameEN: "I - The Magician?",
            englishName: "The Magician",
            pickupZH: "愿您免受侵害",
            pickupEN: "May no harm come to you",
            charge: 4,
            unlock: "魔术师：用堕化犹大获得困难贪婪模式通关标记。",
            effectLines: [
                "获得以下效果，持续60秒：",
                "角色会排斥敌人和敌方泪弹。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 2,
            numeral: "II",
            nameZH: "II-女祭司？",
            nameEN: "II - The High Priestess?",
            englishName: "The High Priestess",
            pickupZH: "快跑",
            pickupEN: "Run",
            charge: 4,
            unlock: "女祭司：用堕化莉莉丝获得困难贪婪模式通关标记。",
            effectLines: [
                "获得以下效果，持续60秒：",
                "妈妈的脚不断地对角色及其周围进行践踏。该效果与拥有 铲子碎片时的效果相同。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 3,
            numeral: "III",
            nameZH: "III-皇后？",
            nameEN: "III - The Empress?",
            englishName: "The Empress",
            pickupZH: "愿您爱中受护",
            pickupEN: "May your love bring protection",
            charge: 4,
            unlock: "皇后：用堕化夏娃获得困难贪婪模式通关标记。",
            effectLines: [
                "获得以下效果，持续60秒：",
                "移速−0.10",
                "射速修正+1.50",
                "角色获得抹大拉的发型。",
                "获得2个心之容器。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 4,
            numeral: "IV",
            nameZH: "IV-皇帝？",
            nameEN: "IV - The Emperor?",
            englishName: "The Emperor",
            pickupZH: "愿您险境得胜",
            pickupEN: "May you find a worthy opponent",
            charge: 2,
            unlock: "皇帝：用堕化???获得困难贪婪模式通关标记。",
            effectLines: [
                "将角色传送到一个额外的随机头目房。",
                "清理房间后，会生成一个头目房道具池的道具，并打开头目房门，可以回到使用卡牌前的房间。若在错误房内使用卡牌，则会回到进入错误房前的房间。",
                "如果拥有 额外选择，会额外生成1个头目房道具池的道具。角色拾取其中一个道具后，另一个会消失。",
                "如果在当前楼层使用过 撒但圣经，会改为生成1个需要进行恶魔交易的恶魔房道具池的道具。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 5,
            numeral: "V",
            nameZH: "V-教皇？",
            nameEN: "V - The Hierophant?",
            englishName: "The Hierophant",
            pickupZH: "为被遗忘者祷告两次",
            pickupEN: "Two prayers for the forgotten",
            charge: 12,
            unlock: "教皇：用堕化伯大尼获得困难贪婪模式通关标记。",
            effectLines: [
                "生成2个骨心。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 6,
            numeral: "VI",
            nameZH: "VI-恋人？",
            nameEN: "VI - The Lovers?",
            englishName: "The Lovers",
            pickupZH: "愿您心碎如麻",
            pickupEN: "May your heart shatter into pieces",
            charge: 4,
            unlock: "恋人：用堕化抹大拉获得困难贪婪模式通关标记。",
            effectLines: [
                "生成1个当前房间道具池的道具。",
                "失去1个心之容器，若角色无心之容器则改为失去2个魂心。",
                "获得。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 7,
            numeral: "VII",
            nameZH: "VII-战车？",
            nameEN: "VII - The Chariot?",
            englishName: "The Chariot",
            pickupZH: "愿您固若金汤",
            pickupEN: "May nothing walk past you",
            charge: 2,
            unlock: "战车：通过挑战#42：烫手山芋。",
            effectLines: [
                "角色变为石像，持续10秒，期间获得以下效果：",
                "角色无法移动。",
                "射速修正×400%",
                "角色获得无敌效果。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 8,
            numeral: "VIII",
            nameZH: "VIII-正义？",
            nameEN: "VIII - Justice?",
            englishName: "Justice",
            pickupZH: "愿您罪有应得",
            pickupEN: "May your sins come back to torment you",
            charge: 12,
            unlock: "正义：通过挑战#43：大量过牌！。",
            effectLines: [
                "生成2~4个金箱子。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 9,
            numeral: "IX",
            nameZH: "IX-隐者？",
            nameEN: "IX - The Hermit?",
            englishName: "The Hermit",
            pickupZH: "愿您坦然释怀",
            pickupEN: "May you see the value of all things in life",
            charge: 2,
            unlock: "隐者：通过挑战#44：赤键救赎。",
            effectLines: [
                "如果房间中没有下列物品，则生成1个硬币；否则将所有下列物品根据种类转化为若干硬币：",
                "道具：2个镍币和5个硬币，合计15美分；",
                "永恒之心、金心、金钥匙、钥匙圈、充能钥匙、金炸弹、双炸弹、巨型炸弹：1个镍币和5个硬币，合计10美分；",
                "福袋：7个硬币；",
                "双红心、黑心、骨心：6个硬币；",
                "魂心、钥匙、炸弹、胶囊、电池、卡牌、饰品：5个硬币；",
                "红心、胆小的红心、混合心：3个硬币；",
                "半魂心、腐心：2个硬币；",
                "半红心：1个硬币；",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 10,
            numeral: "X",
            nameZH: "X-命运之轮？",
            nameEN: "X - Wheel of Fortune?",
            englishName: "Wheel of Fortune",
            pickupZH: "掷出宿命之骰",
            pickupEN: "Throw the dice of fate",
            charge: 4,
            unlock: "命运之轮：用堕化该隐获得困难贪婪模式通关标记。",
            effectLines: [
                "触发随机点数的骰子房的效果。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 11,
            numeral: "XI",
            nameZH: "XI-力量？",
            nameEN: "XI - Strength?",
            englishName: "Strength",
            pickupZH: "愿您粉碎敌志",
            pickupEN: "May you break their resolve",
            charge: 3,
            unlock: "力量：用堕化参孙获得困难贪婪模式通关标记。",
            effectLines: [
                "获得以下效果，持续30秒：",
                "使当前房间中充满紫色烟雾。",
                "当前房间中所有敌人减速，并受到双倍的伤害。",
                "当前房间中所有敌方弹幕减速并降低射程，较大的弹幕会被缩小。",
                "被缩小的弹幕的碰撞体积不会改变。",
                "角色受到由怪物造成的所有伤害降至半颗心。",
                "大体型变种与骷髅变种的精英怪物造成的伤害会被降至一颗心而非半颗心。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 12,
            numeral: "XII",
            nameZH: "XII-倒吊人？",
            nameEN: "XII - The Hanged Man?",
            englishName: "The Hanged Man",
            pickupZH: "愿您贪得无厌",
            pickupEN: "May your greed know no bounds",
            charge: 6,
            unlock: "倒吊人：用堕化店主获得困难贪婪模式通关标记。",
            effectLines: [
                "获得以下效果，持续30秒：",
                "角色的形象变为店主。",
                "移速−0.10",
                "获得 内眼的效果。",
                "每当角色消灭敌人时，生成1个硬币。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 13,
            numeral: "XIII",
            nameZH: "XIII-死亡？",
            nameEN: "XIII - Death?",
            englishName: "Death",
            pickupZH: "愿死者得复生",
            pickupEN: "May life spring forth from the fallen",
            charge: 4,
            unlock: "死亡：用堕化遗骸获得困难贪婪模式通关标记。",
            effectLines: [
                "触发 亡者之书的使用效果。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 14,
            numeral: "XIV",
            nameZH: "XIV-节制？",
            nameEN: "XIV - Temperance?",
            englishName: "Temperance",
            pickupZH: "愿您欲求得满",
            pickupEN: "May your hunger be satiated",
            charge: 6,
            unlock: "节制：通过挑战#45：　　　　。",
            effectLines: [
                "触发5次随机胶囊的使用效果。",
                "如果解锁了成就/603，则使用的每个胶囊有1/140概率是金胶囊。",
                "如果解锁了成就/606，则使用的每个胶囊有1/70概率是相应颜色的大胶囊。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 15,
            numeral: "XV",
            nameZH: "XV-恶魔？",
            nameEN: "XV - The Devil?",
            englishName: "The Devil",
            pickupZH: "沉浸仁慈之光",
            pickupEN: "Bask in the light of your mercy",
            charge: 4,
            unlock: "恶魔：用堕化阿撒泻勒获得困难贪婪模式通关标记。",
            effectLines: [
                "获得以下效果，持续30秒：",
                "获得 撒拉弗的效果。",
                "触发 圣经的使用效果。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 16,
            numeral: "XVI",
            nameZH: "XVI-塔？",
            nameEN: "XVI - The Tower?",
            englishName: "The Tower",
            pickupZH: "创造带来毁灭",
            pickupEN: "Creation brings destruction",
            charge: 4,
            unlock: "塔：用堕化亚玻伦获得困难贪婪模式通关标记。",
            effectLines: [
                "在当前房间中，生成7簇石头。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 17,
            numeral: "XVII",
            nameZH: "XVII-星星？",
            nameEN: "XVII - The Stars?",
            englishName: "The Stars",
            pickupZH: "愿您有失有得",
            pickupEN: "May your loss bring fortune",
            charge: 12,
            unlock: "星星：用堕化以撒获得困难贪婪模式通关标记。",
            effectLines: [
                "角色失去1个最早获得的被动道具。",
                "生成2个当前房间道具池的道具。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 18,
            numeral: "XVIII",
            nameZH: "XVIII-月亮？",
            nameEN: "XVIII - The Moon?",
            englishName: "The Moon",
            pickupZH: "愿您回眸过往",
            pickupEN: "May you remember lost memories",
            charge: 2,
            unlock: "太阳与月亮：用堕化雅各获得困难贪婪模式通关标记。",
            effectLines: [
                "将角色传送至当前层的究极隐藏房。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 19,
            numeral: "XIX",
            nameZH: "XIX-太阳？",
            nameEN: "XIX - The Sun?",
            englishName: "The Sun",
            pickupZH: "愿黑暗吞噬你",
            pickupEN: "May the darkness swallow all around you",
            charge: 6,
            unlock: "太阳与月亮：用堕化雅各获得困难贪婪模式通关标记。",
            effectLines: [
                "在当前楼层中，获得以下效果：",
                "角色的所有心之容器变为骨心。",
                "伤害+1.50",
                "获得 夜之幽魂的效果。",
                "获得无法被移除的黑暗诅咒！。",
                "当角色下一次进入新的楼层时，将角色的所有被转换的骨心变为心之容器。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 20,
            numeral: "XX",
            nameZH: "XX-审判？",
            nameEN: "XX - Judgement?",
            englishName: "Judgement",
            pickupZH: "愿您救赎弱者",
            pickupEN: "May you redeem those found wanting",
            charge: 12,
            unlock: "审判：用堕化拉撒路获得困难贪婪模式通关标记。",
            effectLines: [
                "生成1个补货机。",
            ],
            isReversed: true
        ),
        TarotCard(
            numeralIndex: 21,
            numeral: "XXI",
            nameZH: "XXI-世界？",
            nameEN: "XXI - The World?",
            englishName: "The World",
            pickupZH: "步入无尽深渊",
            pickupEN: "Step into the abyss",
            charge: 2,
            unlock: "世界：用堕化伊甸获得困难贪婪模式通关标记。",
            effectLines: [
                "生成一个暗门。",
            ],
            isReversed: true
        ),
    ]

    public static func card(numeralIndex: Int, reversed: Bool) -> TarotCard? {
        cards.first { $0.numeralIndex == numeralIndex && $0.isReversed == reversed }
    }
}

public enum TarotDrawPolicy {
    /// Reversed arcana are the rarer pull, mirroring their in-game scarcity.
    public static let reversedProbability = 0.25
    /// Delay before the card panel pops up, so the raise motion lands first.
    public static let cardAppearDelay: TimeInterval = 0.35
    public static let cardPanelDisplayDuration: TimeInterval = 6

    /// Draws one card. `random` injects values in 0..<1 so checks stay deterministic.
    public static func draw(random: () -> Double = { Double.random(in: 0..<1) }) -> TarotCard {
        let reversed = random() < reversedProbability
        let index = min(TarotDeck.arcanaCount - 1, Int(random() * Double(TarotDeck.arcanaCount)))
        return TarotDeck.card(numeralIndex: index, reversed: reversed)
            ?? TarotDeck.cards[0]
    }

    /// Panel heading: the wiki name with an explicit 逆位 marker for reversed pulls.
    public static func displayTitle(for card: TarotCard) -> String {
        card.isReversed ? "逆位 · \(card.nameZH)" : card.nameZH
    }
}
