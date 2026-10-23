# Cursor 菜单栏用量

日期：2026-10-23

在 macOS 顶部栏显示当前账期的 Cursor 用量。数字与 [账单页 Included Usage](https://cursor.com/dashboard/billing) 同一套数据：默认只显示 Cursor Models 与 Other Models 两类合计，点开后显示每个模型。顶部栏有三种详略，用户自选并记住。

## 交付物

一个不出现在 Dock 里的 macOS 应用，放在 `~/Workspace/cursor-usage-bar`。双击后只在顶部栏显示文字。不做图表，不做按量付费，不做开机启动，不支持多账号，不提供手动粘贴 cookie。

## 数据来源

只读本机 Cursor 已登录会话，不把 token 写入本应用的任何文件或日志。

1. 只读打开 `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`。
2. 读取 `ItemTable` 里的 `cursorAuth/accessToken`（JWT）。
3. 从 JWT payload 的 `sub` 取出用户 id：有 `|` 时取最后一段，否则用整个 `sub`。
4. 请求 cookie 为 `WorkosCursorSessionToken=<userId>%3A%3A<jwt>`。
5. 只向 `https://cursor.com` 发请求。POST 必须带 `Origin: https://cursor.com` 和 `Content-Type: application/json`。超时 15 秒。

两次请求都针对当前账期：

| 用途 | 请求 |
| --- | --- |
| 两类百分比、账期、Cursor Models 名单 | `POST /api/dashboard/get-current-period-usage`，body `{}` |
| 每个模型的 token 与费用 | `POST /api/dashboard/get-aggregated-usage-events` |

第二次请求的 `startDate` 与 `endDate` 使用第一次返回的 `billingCycleStart`、`billingCycleEnd`（毫秒，可能是字符串）。这样周计费账号也不会拿错窗口。

采用的字段：

- `planUsage.autoPercentUsed`：Cursor Models 已用百分比
- `planUsage.apiPercentUsed`：Other Models 已用百分比
- `autoBucketModels`：计入 Cursor Models 的模型 id
- `aggregations[].modelIntent`
- `inputTokens`、`outputTokens`、`cacheReadTokens`、`cacheWriteTokens`（字符串整数）
- `totalCents`

接口未文档化。百分比字段缺失，或响应不是预期结构时，视为本次刷新失败，不把缺失显示成 0%。

## 分类与计算

一个模型计入 Cursor Models，当且仅当满足下面任一条：

- `modelIntent` 出现在 `autoBucketModels` 中
- 与名单中某一项同族
- 名字是 `auto` 或 `default`

同族：把两边都转成小写，去掉 `-fast`、去掉 `-low` / `-medium` / `-high` / `-xhigh`、去掉版本数字和小数点，再去掉首尾多余的 `-`。剩下的词干相同则同族。例如 `grok-4.7-high` 与 `grok-4.5-high-fast` 的词干都是 `grok`。

其余模型计入 Other Models。`autoBucketModels` 为空时，只把 `auto`、`default`，以及名字以 `composer`、`grok`、`cursor-grok` 开头的模型放进 Cursor Models。

模型 token 为四项 token 之和。费用或 token 都为 0 的模型不显示。同一 `modelIntent` 出现多次时先合并。

模型百分比 = 该池百分比 ×（该模型 `totalCents` / 该池 `totalCents` 之和）。该池费用为 0 但还有 token 时，改用 token 占比。展示前把每个模型百分比四舍五入到一位小数，再把舍入差额补到该池费用最高的模型上，使展示出来的模型百分比之和等于展示出来的池百分比。池内按百分比从高到低，其次按 token 从高到低，最后按名字排序。

## 顶部栏

三种显示存在本机偏好里，默认「百分比」。菜单里单选，选中后立即改顶部栏文字，不等下一次网络刷新。

百分比四舍五入到整数，token 在「亿」上保留一位小数，在「万」上四舍五入到整数。

| 选项 | 示例 |
| --- | --- |
| 百分比 | `Cursor 93% · Other 62%` |
| 百分比和 token | `Cursor 6.0亿 93% · Other 5748万 62%` |
| 仅 token | `Cursor 6.0亿 · Other 5748万` |

顶部栏只有这段文字，没有单独图标。

## 点击菜单

点顶部栏打开系统菜单，结构如下：

1. 账期，不可点。格式与账单页一致，例如 `Sep 27, 2026 – Oct 27, 2026`。
2. `Cursor Models`，右侧为明细数字。
3. 该类下每个模型一行，名字在左，数字在右。
4. 分隔线。
5. `Other Models` 及其模型，规则相同。
6. 分隔线。
7. 子菜单「顶部栏显示」：百分比、百分比和 token、仅 token。当前项打勾。
8. 「刷新」。
9. 「退出」。退出即结束进程。

明细数字比顶部栏更细，对齐账单页：

- 大于等于 1 亿：用「亿」，保留一位小数，去掉末尾 `.0`（`6亿`、`2.4亿`）。
- 大于等于 1 万：用「万」，保留一位小数，去掉末尾 `.0`（`3271.4万`）。
- 不足 1 万：整数。
- 百分比始终一位小数（`93.1%`、`9.0%`）。
- 每行同时显示 token 和百分比，顺序与账单页相同：token 在前，百分比在后。

顶部栏的三项选择只改变顶部栏文字。菜单里的合计和每个模型始终按上面的明细格式显示。

## 刷新与失败

启动后立刻拉一次，之后每 5 分钟一次。正在请求时忽略新的刷新。菜单在请求完成后重建。

| 情况 | 顶部栏 | 菜单 |
| --- | --- | --- |
| 找不到本地登录 | `未登录` | 说明需要先在 Cursor 里登录 |
| 百分比请求失败，且从无成功数据 | `Cursor —` | 说明这次失败 |
| 百分比请求失败，但有过成功数据 | 保持上次文字 | 说明失败时间，下面仍是上次的模型列表 |
| 只有模型明细失败 | 两类合计仍按成功结果更新 | 两类标题在，模型行替换为一行「模型明细暂时不可用」 |

失败文案不包含 token、cookie 或数据库路径。

## 测试

纯计算用单元测试覆盖：

- token 的万 / 亿格式，以及顶部栏与菜单两种舍入
- 同族分类，以及 `auto` 固定进入 Cursor Models
- 模型百分比之和等于池百分比
- 三种顶部栏文案
- 费用为 0 时改按 token 分摊

手工核对：运行应用，与账单页同一账期对比两类百分比、模型名单和数量级。接口失败时顶部栏不把旧数字换成 0。
