using System.Globalization;

namespace IsaacPet.Windows.Core;

/// <summary>
/// 22 张大阿卡纳及其逆位，内容转录自粉丝 Wiki（https://isaac.huijiwiki.com/wiki/卡牌），
/// 供本机抽卡展示。移植自 macOS 版 TarotDeck.swift。
/// </summary>
public sealed record TarotCard(
    int NumeralIndex,
    string Numeral,
    string NameZh,
    string NameEn,
    string EnglishName,
    string PickupZh,
    string PickupEn,
    int Charge,
    string? Unlock,
    string[] EffectLines,
    bool IsReversed)
{
    public string Id => $"{(IsReversed ? "reversed" : "normal")}-{NumeralIndex}";

    /// <summary>Assets/Cards 下卡面图标的资源名（不含扩展名）。</summary>
    public string IconResource
    {
        get
        {
            var prefix = IsReversed ? "TarotReversed" : "Tarot";
            return prefix + NumeralIndex.ToString("00", CultureInfo.InvariantCulture);
        }
    }
}

public static class TarotDeck
{
    public const int ArcanaCount = 22;

    public static readonly IReadOnlyList<TarotCard> Cards =
    [
        new(
            NumeralIndex: 0, Numeral: "0", NameZh: "0-愚者",
            NameEn: "0 - The Fool", EnglishName: "The Fool",
            PickupZh: "旅程开始之地", PickupEn: "Where journey begins", Charge: 2,
            Unlock: null,
            EffectLines: [
            "传送到当前层的初始房间。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 1, Numeral: "I", NameZh: "I-魔术师",
            NameEn: "I - The Magician", EnglishName: "The Magician",
            PickupZh: "愿您弹无虚发", PickupEn: "May you never miss your goal", Charge: 2,
            Unlock: null,
            EffectLines: [
            "在当前房间中，获得 弯勺魔术的效果。",
            "射程+3.00",
            "多个I-魔术师的该效果不叠加。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 2, Numeral: "II", NameZh: "II-女祭司",
            NameEn: "II - The High Priestess", EnglishName: "The High Priestess",
            PickupZh: "妈妈在注视你", PickupEn: "Mother is watching you", Charge: 2,
            Unlock: null,
            EffectLines: [
            "生成妈妈的脚踩踏敌人，对房间中血量最高的敌人造成300.00点伤害。",
            "如果房间中没有敌人，则会瞄准角色进行一次踩踏。",
            "房间未清理完成时，踩踏可以打开房间中未上锁的门。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 3, Numeral: "III", NameZh: "III-皇后",
            NameEn: "III - The Empress", EnglishName: "The Empress",
            PickupZh: "愿您怒中生力", PickupEn: "May your rage bring power", Charge: 3,
            Unlock: null,
            EffectLines: [
            "在当前房间中，获得1层巴比伦大淫妇状态。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 4, Numeral: "IV", NameZh: "IV-皇帝",
            NameEn: "IV - The Emperor", EnglishName: "The Emperor",
            PickupZh: "挑战我！", PickupEn: "Challenge me!", Charge: 4,
            Unlock: null,
            EffectLines: [
            "传送到当前层的头目房。",
            "如果当前层有多个头目房，则随机传送到其中一个。",
            "如果当前层没有头目房，则随机传送到一个房间。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 5, Numeral: "V", NameZh: "V-教皇",
            NameEn: "V - The Hierophant", EnglishName: "The Hierophant",
            PickupZh: "为迷途者祷告两次", PickupEn: "Two prayers for the lost", Charge: 12,
            Unlock: null,
            EffectLines: [
            "生成2个魂心。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 6, Numeral: "VI", NameZh: "VI-恋人",
            NameEn: "VI - The Lovers", EnglishName: "The Lovers",
            PickupZh: "愿您健康繁盛", PickupEn: "May you prosper and be in good health", Charge: 6,
            Unlock: null,
            EffectLines: [
            "生成2个红心。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 7, Numeral: "VII", NameZh: "VII-战车",
            NameEn: "VII - The Chariot", EnglishName: "The Chariot",
            PickupZh: "愿您所向披靡", PickupEn: "May nothing stand before you", Charge: 3,
            Unlock: null,
            EffectLines: [
            "触发1次 彩虹独角兽的使用效果。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 8, Numeral: "VIII", NameZh: "VIII-正义",
            NameEn: "VIII - Justice", EnglishName: "Justice",
            PickupZh: "愿您仕途平稳", PickupEn: "May your future become balanced", Charge: 6,
            Unlock: null,
            EffectLines: [
            "生成1个随机心。",
            "生成1个随机硬币。",
            "生成1个随机钥匙。",
            "生成1个随机炸弹。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 9, Numeral: "IX", NameZh: "IX-隐者",
            NameEn: "IX - The Hermit", EnglishName: "The Hermit",
            PickupZh: "愿您看破红尘", PickupEn: "May you see what life has to offer", Charge: 2,
            Unlock: null,
            EffectLines: [
            "传送到当前层的商店。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 10, Numeral: "X", NameZh: "X-命运之轮",
            NameEn: "X - Wheel of Fortune", EnglishName: "Wheel of Fortune",
            PickupZh: "转动命运之轮", PickupEn: "Spin the wheel of destiny", Charge: 4,
            Unlock: null,
            EffectLines: [
            "66%概率生成1个赌博机，33%概率生成1个预言机，1%概率生成1个夹娃娃机。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 11, Numeral: "XI", NameZh: "XI-力量",
            NameEn: "XI - Strength", EnglishName: "Strength",
            PickupZh: "愿您力中唤怒", PickupEn: "May your power bring rage", Charge: 3,
            Unlock: null,
            EffectLines: [
            "在当前房间中，获得 魔法蘑菇的被动效果和1个心之容器。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 12, Numeral: "XII", NameZh: "XII-倒吊人",
            NameEn: "XII - The Hanged Man", EnglishName: "The Hanged Man",
            PickupZh: "愿您寻得启示", PickupEn: "May you find enlightenment", Charge: 3,
            Unlock: null,
            EffectLines: [
            "在当前房间中，获得 超凡升天的效果。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 13, Numeral: "XIII", NameZh: "XIII-死亡",
            NameEn: "XIII - Death", EnglishName: "Death",
            PickupZh: "毁灭忤逆尔者", PickupEn: "Lay waste to all that oppose you", Charge: 3,
            Unlock: null,
            EffectLines: [
            "对当前房间中的所有敌人造成40.00点伤害。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 14, Numeral: "XIV", NameZh: "XIV-节制",
            NameEn: "XIV - Temperance", EnglishName: "Temperance",
            PickupZh: "愿您内心纯洁", PickupEn: "May you be pure in heart", Charge: 6,
            Unlock: null,
            EffectLines: [
            "生成1个献血机。",
            "改为生成1个恶魔乞丐。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 15, Numeral: "XV", NameZh: "XV-恶魔",
            NameEn: "XV - The Devil", EnglishName: "The Devil",
            PickupZh: "沉迷黑暗之力", PickupEn: "Revel in the power of darkness", Charge: 3,
            Unlock: null,
            EffectLines: [
            "在当前房间中，触发 彼列之书的使用效果。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 16, Numeral: "XVI", NameZh: "XVI-塔",
            NameEn: "XVI - The Tower", EnglishName: "The Tower",
            PickupZh: "毁灭带来创造", PickupEn: "Destruction brings creation", Charge: 3,
            Unlock: null,
            EffectLines: [
            "触发1次 无政府主义者食谱的使用效果。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 17, Numeral: "XVII", NameZh: "XVII-星星",
            NameEn: "XVII - The Stars", EnglishName: "The Stars",
            PickupZh: "愿你心想事成", PickupEn: "May you find what you desire", Charge: 2,
            Unlock: null,
            EffectLines: [
            "传送到当前层的宝箱房。",
            "如果当前楼层有星象房，则传送到当前层的星象房。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 18, Numeral: "XVIII", NameZh: "XVIII-月亮",
            NameEn: "XVIII - The Moon", EnglishName: "The Moon",
            PickupZh: "愿你失而复得", PickupEn: "May you find all you have lost", Charge: 2,
            Unlock: null,
            EffectLines: [
            "传送到当前层的隐藏房。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 19, Numeral: "XIX", NameZh: "XIX-太阳",
            NameEn: "XIX - The Sun", EnglishName: "The Sun",
            PickupZh: "愿光赐你启示", PickupEn: "May the light heal and enlighten you", Charge: 12,
            Unlock: null,
            EffectLines: [
            "回复所有红心容器。",
            "对当前房间中所有敌人造成100.00点伤害。",
            "在地图上显示除超级隐藏房与究极隐藏房以外所有的房间的图标和位置。",
            "解除当前楼层的黑暗诅咒！。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 20, Numeral: "XX", NameZh: "XX-审判",
            NameEn: "XX - Judgement", EnglishName: "Judgement",
            PickupZh: "为避审而审判", PickupEn: "Judge lest ye be judged", Charge: 6,
            Unlock: null,
            EffectLines: [
            "随机生成1个乞丐、恶魔乞丐、钥匙大师或炸弹乞丐。",
            "权重概率事件4864%生成1个乞丐。2533.33%生成1个恶魔乞丐。11.33%生成1个钥匙大师。11.33%生成1个炸弹乞丐。75合计权重",
            "使用后：",
            "随机生成1个乞丐、恶魔乞丐、钥匙大师、炸弹乞丐、电池乞丐或腐烂乞丐。",
            "权重概率事件4661.33%生成1个乞丐。2533.33%生成1个恶魔乞丐。11.33%生成1个钥匙大师。11.33%生成1个炸弹乞丐。11.33%生成1个腐烂乞丐。11.33%生成1个电池乞丐。75合计权重",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 21, Numeral: "XXI", NameZh: "XXI-世界",
            NameEn: "XXI - The World", EnglishName: "The World",
            PickupZh: "睁眼洞察世界", PickupEn: "Open your eyes and see", Charge: 3,
            Unlock: null,
            EffectLines: [
            "在地图上显示除超级隐藏房与究极隐藏房以外所有房间的图标和位置。",
            ],
            IsReversed: false),
        new(
            NumeralIndex: 0, Numeral: "0", NameZh: "0-愚者？",
            NameEn: "0 - The Fool?", EnglishName: "The Fool",
            PickupZh: "一切从零开始", PickupEn: "Let go and move on", Charge: 12,
            Unlock: "愚者：用堕化游魂获得困难贪婪模式通关标记。",
            EffectLines: [
            "为角色保留半颗心的血量，失去剩余的所有心，并生成等量的对应掉落物。",
            "失去所有硬币、炸弹和钥匙，并生成等量的对应掉落物。",
            "如果硬币、炸弹和钥匙达到一定数量则改为生成对应的底座道具（如 25美分、 轰！、 骷髅钥匙、 烟火盛宴等）。",
            "掉落物和底座道具均会以最少的个数形式生成（如角色拥有110个硬币，使用卡牌后将会生成1个铸币和 一美元）。",
            "丢弃所有饰品、卡牌和胶囊。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 1, Numeral: "I", NameZh: "I-魔术师？",
            NameEn: "I - The Magician?", EnglishName: "The Magician",
            PickupZh: "愿您免受侵害", PickupEn: "May no harm come to you", Charge: 4,
            Unlock: "魔术师：用堕化犹大获得困难贪婪模式通关标记。",
            EffectLines: [
            "获得以下效果，持续60秒：",
            "角色会排斥敌人和敌方泪弹。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 2, Numeral: "II", NameZh: "II-女祭司？",
            NameEn: "II - The High Priestess?", EnglishName: "The High Priestess",
            PickupZh: "快跑", PickupEn: "Run", Charge: 4,
            Unlock: "女祭司：用堕化莉莉丝获得困难贪婪模式通关标记。",
            EffectLines: [
            "获得以下效果，持续60秒：",
            "妈妈的脚不断地对角色及其周围进行践踏。该效果与拥有 铲子碎片时的效果相同。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 3, Numeral: "III", NameZh: "III-皇后？",
            NameEn: "III - The Empress?", EnglishName: "The Empress",
            PickupZh: "愿您爱中受护", PickupEn: "May your love bring protection", Charge: 4,
            Unlock: "皇后：用堕化夏娃获得困难贪婪模式通关标记。",
            EffectLines: [
            "获得以下效果，持续60秒：",
            "移速−0.10",
            "射速修正+1.50",
            "角色获得抹大拉的发型。",
            "获得2个心之容器。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 4, Numeral: "IV", NameZh: "IV-皇帝？",
            NameEn: "IV - The Emperor?", EnglishName: "The Emperor",
            PickupZh: "愿您险境得胜", PickupEn: "May you find a worthy opponent", Charge: 2,
            Unlock: "皇帝：用堕化???获得困难贪婪模式通关标记。",
            EffectLines: [
            "将角色传送到一个额外的随机头目房。",
            "清理房间后，会生成一个头目房道具池的道具，并打开头目房门，可以回到使用卡牌前的房间。若在错误房内使用卡牌，则会回到进入错误房前的房间。",
            "如果拥有 额外选择，会额外生成1个头目房道具池的道具。角色拾取其中一个道具后，另一个会消失。",
            "如果在当前楼层使用过 撒但圣经，会改为生成1个需要进行恶魔交易的恶魔房道具池的道具。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 5, Numeral: "V", NameZh: "V-教皇？",
            NameEn: "V - The Hierophant?", EnglishName: "The Hierophant",
            PickupZh: "为被遗忘者祷告两次", PickupEn: "Two prayers for the forgotten", Charge: 12,
            Unlock: "教皇：用堕化伯大尼获得困难贪婪模式通关标记。",
            EffectLines: [
            "生成2个骨心。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 6, Numeral: "VI", NameZh: "VI-恋人？",
            NameEn: "VI - The Lovers?", EnglishName: "The Lovers",
            PickupZh: "愿您心碎如麻", PickupEn: "May your heart shatter into pieces", Charge: 4,
            Unlock: "恋人：用堕化抹大拉获得困难贪婪模式通关标记。",
            EffectLines: [
            "生成1个当前房间道具池的道具。",
            "失去1个心之容器，若角色无心之容器则改为失去2个魂心。",
            "获得。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 7, Numeral: "VII", NameZh: "VII-战车？",
            NameEn: "VII - The Chariot?", EnglishName: "The Chariot",
            PickupZh: "愿您固若金汤", PickupEn: "May nothing walk past you", Charge: 2,
            Unlock: "战车：通过挑战#42：烫手山芋。",
            EffectLines: [
            "角色变为石像，持续10秒，期间获得以下效果：",
            "角色无法移动。",
            "射速修正×400%",
            "角色获得无敌效果。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 8, Numeral: "VIII", NameZh: "VIII-正义？",
            NameEn: "VIII - Justice?", EnglishName: "Justice",
            PickupZh: "愿您罪有应得", PickupEn: "May your sins come back to torment you", Charge: 12,
            Unlock: "正义：通过挑战#43：大量过牌！。",
            EffectLines: [
            "生成2~4个金箱子。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 9, Numeral: "IX", NameZh: "IX-隐者？",
            NameEn: "IX - The Hermit?", EnglishName: "The Hermit",
            PickupZh: "愿您坦然释怀", PickupEn: "May you see the value of all things in life", Charge: 2,
            Unlock: "隐者：通过挑战#44：赤键救赎。",
            EffectLines: [
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
            IsReversed: true),
        new(
            NumeralIndex: 10, Numeral: "X", NameZh: "X-命运之轮？",
            NameEn: "X - Wheel of Fortune?", EnglishName: "Wheel of Fortune",
            PickupZh: "掷出宿命之骰", PickupEn: "Throw the dice of fate", Charge: 4,
            Unlock: "命运之轮：用堕化该隐获得困难贪婪模式通关标记。",
            EffectLines: [
            "触发随机点数的骰子房的效果。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 11, Numeral: "XI", NameZh: "XI-力量？",
            NameEn: "XI - Strength?", EnglishName: "Strength",
            PickupZh: "愿您粉碎敌志", PickupEn: "May you break their resolve", Charge: 3,
            Unlock: "力量：用堕化参孙获得困难贪婪模式通关标记。",
            EffectLines: [
            "获得以下效果，持续30秒：",
            "使当前房间中充满紫色烟雾。",
            "当前房间中所有敌人减速，并受到双倍的伤害。",
            "当前房间中所有敌方弹幕减速并降低射程，较大的弹幕会被缩小。",
            "被缩小的弹幕的碰撞体积不会改变。",
            "角色受到由怪物造成的所有伤害降至半颗心。",
            "大体型变种与骷髅变种的精英怪物造成的伤害会被降至一颗心而非半颗心。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 12, Numeral: "XII", NameZh: "XII-倒吊人？",
            NameEn: "XII - The Hanged Man?", EnglishName: "The Hanged Man",
            PickupZh: "愿您贪得无厌", PickupEn: "May your greed know no bounds", Charge: 6,
            Unlock: "倒吊人：用堕化店主获得困难贪婪模式通关标记。",
            EffectLines: [
            "获得以下效果，持续30秒：",
            "角色的形象变为店主。",
            "移速−0.10",
            "获得 内眼的效果。",
            "每当角色消灭敌人时，生成1个硬币。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 13, Numeral: "XIII", NameZh: "XIII-死亡？",
            NameEn: "XIII - Death?", EnglishName: "Death",
            PickupZh: "愿死者得复生", PickupEn: "May life spring forth from the fallen", Charge: 4,
            Unlock: "死亡：用堕化遗骸获得困难贪婪模式通关标记。",
            EffectLines: [
            "触发 亡者之书的使用效果。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 14, Numeral: "XIV", NameZh: "XIV-节制？",
            NameEn: "XIV - Temperance?", EnglishName: "Temperance",
            PickupZh: "愿您欲求得满", PickupEn: "May your hunger be satiated", Charge: 6,
            Unlock: "节制：通过挑战#45：　　　　。",
            EffectLines: [
            "触发5次随机胶囊的使用效果。",
            "如果解锁了成就/603，则使用的每个胶囊有1/140概率是金胶囊。",
            "如果解锁了成就/606，则使用的每个胶囊有1/70概率是相应颜色的大胶囊。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 15, Numeral: "XV", NameZh: "XV-恶魔？",
            NameEn: "XV - The Devil?", EnglishName: "The Devil",
            PickupZh: "沉浸仁慈之光", PickupEn: "Bask in the light of your mercy", Charge: 4,
            Unlock: "恶魔：用堕化阿撒泻勒获得困难贪婪模式通关标记。",
            EffectLines: [
            "获得以下效果，持续30秒：",
            "获得 撒拉弗的效果。",
            "触发 圣经的使用效果。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 16, Numeral: "XVI", NameZh: "XVI-塔？",
            NameEn: "XVI - The Tower?", EnglishName: "The Tower",
            PickupZh: "创造带来毁灭", PickupEn: "Creation brings destruction", Charge: 4,
            Unlock: "塔：用堕化亚玻伦获得困难贪婪模式通关标记。",
            EffectLines: [
            "在当前房间中，生成7簇石头。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 17, Numeral: "XVII", NameZh: "XVII-星星？",
            NameEn: "XVII - The Stars?", EnglishName: "The Stars",
            PickupZh: "愿您有失有得", PickupEn: "May your loss bring fortune", Charge: 12,
            Unlock: "星星：用堕化以撒获得困难贪婪模式通关标记。",
            EffectLines: [
            "角色失去1个最早获得的被动道具。",
            "生成2个当前房间道具池的道具。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 18, Numeral: "XVIII", NameZh: "XVIII-月亮？",
            NameEn: "XVIII - The Moon?", EnglishName: "The Moon",
            PickupZh: "愿您回眸过往", PickupEn: "May you remember lost memories", Charge: 2,
            Unlock: "太阳与月亮：用堕化雅各获得困难贪婪模式通关标记。",
            EffectLines: [
            "将角色传送至当前层的究极隐藏房。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 19, Numeral: "XIX", NameZh: "XIX-太阳？",
            NameEn: "XIX - The Sun?", EnglishName: "The Sun",
            PickupZh: "愿黑暗吞噬你", PickupEn: "May the darkness swallow all around you", Charge: 6,
            Unlock: "太阳与月亮：用堕化雅各获得困难贪婪模式通关标记。",
            EffectLines: [
            "在当前楼层中，获得以下效果：",
            "角色的所有心之容器变为骨心。",
            "伤害+1.50",
            "获得 夜之幽魂的效果。",
            "获得无法被移除的黑暗诅咒！。",
            "当角色下一次进入新的楼层时，将角色的所有被转换的骨心变为心之容器。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 20, Numeral: "XX", NameZh: "XX-审判？",
            NameEn: "XX - Judgement?", EnglishName: "Judgement",
            PickupZh: "愿您救赎弱者", PickupEn: "May you redeem those found wanting", Charge: 12,
            Unlock: "审判：用堕化拉撒路获得困难贪婪模式通关标记。",
            EffectLines: [
            "生成1个补货机。",
            ],
            IsReversed: true),
        new(
            NumeralIndex: 21, Numeral: "XXI", NameZh: "XXI-世界？",
            NameEn: "XXI - The World?", EnglishName: "The World",
            PickupZh: "步入无尽深渊", PickupEn: "Step into the abyss", Charge: 2,
            Unlock: "世界：用堕化伊甸获得困难贪婪模式通关标记。",
            EffectLines: [
            "生成一个暗门。",
            ],
            IsReversed: true),
    ];

    public static TarotCard? Card(int numeralIndex, bool reversed) =>
        Cards.FirstOrDefault(card => card.NumeralIndex == numeralIndex && card.IsReversed == reversed);
}

public static class TarotDrawPolicy
{
    /// <summary>逆位是更稀有的抽中结果，对应游戏内的获取难度。</summary>
    public const double ReversedProbability = 0.25;

    /// <summary>举牌动作：待机 → 手臂抬起 → 单手举起 → 双手举起（4 帧图集）。</summary>
    public static readonly TimeSpan RaiseTransitionDuration = TimeSpan.FromSeconds(0.52);

    /// <summary>卡牌在桌宠头顶正反面洗牌两秒，然后放大揭示。</summary>
    public static readonly TimeSpan SpinDuration = TimeSpan.FromSeconds(2.0);
    public static readonly TimeSpan ZoomInDuration = TimeSpan.FromSeconds(0.35);
    public static readonly TimeSpan ZoomHoldDuration = TimeSpan.FromSeconds(0.7);
    public static readonly TimeSpan ZoomOutDuration = TimeSpan.FromSeconds(0.25);
    public const double ZoomScale = 2.8;
    public const double TiltDegrees = 12;
    public static readonly TimeSpan CardPanelDisplayDuration = TimeSpan.FromSeconds(6);

    /// <summary>洗牌加揭示的总时长（不含举牌）。</summary>
    public static TimeSpan RevealDuration => SpinDuration + ZoomInDuration + ZoomHoldDuration + ZoomOutDuration;

    /// <summary>抽一张牌。random 注入 0..<1 的值以便自检保持确定性。</summary>
    public static TarotCard Draw(Func<double>? random = null)
    {
        Func<double> next = random ?? (Func<double>)(() => Random.Shared.NextDouble());
        var reversed = next() < ReversedProbability;
        var index = Math.Min(TarotDeck.ArcanaCount - 1, (int)(next() * TarotDeck.ArcanaCount));
        return TarotDeck.Card(index, reversed) ?? TarotDeck.Cards[0];
    }

    /// <summary>面板标题：Wiki 名称，逆位牌带明确的「逆位」标记。</summary>
    public static string DisplayTitle(TarotCard card) =>
        card.IsReversed ? $"逆位 · {card.NameZh}" : card.NameZh;
}
