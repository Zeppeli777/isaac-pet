# 《以撒的结合》塔罗牌调研

调研日期：2026-08-18

参考页面：[The Binding of Isaac: Rebirth Wiki — Cards and Runes](https://bindingofisaacrebirth.wiki.gg/wiki/Cards_and_Runes)

## 范围

本次先采用游戏里的 22 张 Major Arcana（0–XXI）作为“今日运势”牌组。Wiki 页面同时列出了扑克牌、特殊卡、符文、灵魂石和《忏悔》新增的逆位大阿卡纳；本期不把这些混入每日牌组，避免首次功能过重。

游戏内短句保留英文原文作为识别线索；桌宠展示的中文句子是独立的娱乐解读，不模拟游戏内实际效果，也不对现实作预测。

| 编号 | 卡牌 | 游戏内短句 | 桌宠解读方向 |
| --- | --- | --- | --- |
| 0 | The Fool / 愚者 | Where journey begins | 新的开始 |
| I | The Magician / 魔术师 | May you never miss your goal | 聚焦目标 |
| II | The High Priestess / 女祭司 | Mother is watching you | 直觉与观察 |
| III | The Empress / 皇后 | May your rage bring power | 能量与创造 |
| IV | The Emperor / 皇帝 | Challenge me! | 边界与担当 |
| V | The Hierophant / 教皇 | Two prayers for the lost | 求助与经验 |
| VI | The Lovers / 恋人 | May you prosper and be in good health | 关系与照顾 |
| VII | The Chariot / 战车 | May nothing stand before you | 方向与行动 |
| VIII | Justice / 正义 | May your future become balanced | 平衡与取舍 |
| IX | The Hermit / 隐者 | May you see what life has to offer | 安静与反思 |
| X | Wheel of Fortune / 命运之轮 | Spin the wheel of destiny | 变化与弹性 |
| XI | Strength / 力量 | May your power bring rage | 稳定与勇气 |
| XII | The Hanged Man / 倒吊人 | May you find enlightenment | 换位思考 |
| XIII | Death / 死神 | Lay waste to all that oppose you | 结束与更新 |
| XIV | Temperance / 节制 | May you be pure in heart | 节奏与恢复 |
| XV | The Devil / 恶魔 | Revel in the power of darkness | 识别诱惑 |
| XVI | The Tower / 高塔 | Destruction brings creation | 变化与重建 |
| XVII | The Stars / 星星 | May you find what you desire | 希望与长期目标 |
| XVIII | The Moon / 月亮 | May you find all you have lost | 信息核实 |
| XIX | The Sun / 太阳 | May the light heal and enlighten you | 清晰与活力 |
| XX | Judgement / 审判 | Judge lest ye be judged | 复盘与决定 |
| XXI | The World / 世界 | Open your eyes and see | 完成与阶段总结 |

## 实现决策

- 默认入口叫“今日运势（塔罗）…”，每天第一次打开使用稳定的当天牌，不写入外部服务。
- “重新抽一张”在当前窗口内随机换牌；重新打开窗口时回到当天固定牌，避免娱乐操作污染每日记录。
- 当前卡面是纯色方块占位：每张牌有独立颜色、罗马数字、中文名和英文短句。
- 后续替换卡面时，优先使用用户明确提供或确认授权的游戏内素材；不要从第三方页面直接打包未经确认的图片。
- 牌面、解读和 LLM 都不应被描述为真实预测；未来如接入 LLM，只允许润色已有解读，不让模型自行编造游戏效果。
