---
name: "meeting-recorder"
description: "会议记录：出现「STATE 记录中」时按该行命令落盘并回复指定短应答；结束自检后出纪要"
---

# Meeting Recorder

会议期间把逐句送来的文字落盘，结束时先做完整性自检、再生成纪要。
不做录音、不做语音识别——文字由上层客户端提供。

## 交互约定

- 每句落盘后，**只回 STATE 行里指定的短应答**（默认「收到」）——不多话、不解释、不总结。
- 只有三处会说话：**开始**（一句确认）、**每句**（短应答）、**结束**（纪要）。

## 规则单一来源

状态的唯一权威是 **capture.py 的输出行**（`STATE …`）：带着「下一步动作 + 命令 + 该回什么」，
且工具结果会保留在会话尾部。SKILL.md 只解释设计；**description 只负责识别触发**。
执行时**以 STATE 行为准**，不要自造格式或改应答词。

每轮判定（先看会话尾部）：
- 出现 `STATE 记录中` → 按该行命令把**这条用户消息的原文**落盘，然后回该行指定的短应答；
- 出现 `STATE 记录结束` / 没有 → 按普通消息处理。

## 流程

1. 开始 —— `python3 scripts/capture.py start "<标题>" --session "<当前会话 key>"`
   会话 key 取运行时 `session=` 后面那串。回一句：`🎙️ 已开始记录（标题）`
2. 每句文字 —— 落盘（三选一，含引号/换行/emoji 时优先用后两种）：
   - `python3 scripts/capture.py append --text "原文"`
   - `python3 scripts/capture.py append --file <临时文件>`
   - `echo "原文" | python3 scripts/capture.py append --stdin`
   然后**只回短应答**（默认「收到」）。
3. 结束 —— `python3 scripts/capture.py stop`
   `stop` 会顺带跑完整性自检（`CHECK` 行）。然后：
   - 读一次 `transcript.md`；
   - 按 `templates/summary_template.md` 生成 `summary.md`；
   - **数据质量备注必须按自检结果显式写**，不要把缺失笼统写成「待确认」；
   - 交付前自检（见下）。

## 清上文（后台 worker）

append/start 后，会**脱离进程**启动一个 worker：先等当前回合结束（轮询会话状态，`running` 就让路，
最多等若干次），确认空闲后才执行截断 —— 避免截断撞上进行中的回合导致会话卡死。

## 交付前自检（出纪要的最后一步）

- 完整性：`CHECK` 报了几处疑似缺失？纪要里有没有如实标注？
- 决议与数据：数字、日期、负责人有没有原文依据？（没依据的不要写成结论）
- 若用户提供了「官方版 / 参考纪要」：逐项比对，列出差异，以「差异对照」小节给出。

## 命令

- `start <标题> [--session <key>]`
- `append --text "…" | --file <path> | --stdin`
- `stop` —— 结束 + 自检
- `check` —— 只做完整性自检（不改状态）
- `status` / `path` / `compact`

## 配置

`~/.config/openclaw-meeting/config.json`：

```json
{
  "output_dir": "~/.openclaw/workspace/meetings",
  "session_key": "",
  "ack": "收到",
  "compact": { "enabled": true, "max_lines": 6, "delay_sec": 5, "wait_tries": 20, "wait_sec": 3 }
}
```

- `ack`：每句落盘后的短应答（想改成「收到，已记录」就改这里）。
- `max_lines`：截断后保留最近几行，要够留住「上一条工具输出」。
- `delay_sec`：先等多久；`wait_tries` / `wait_sec`：之后每 `wait_sec` 秒查一次会话是否空闲，最多查 `wait_tries` 次。
- 截断日志：`~/.config/openclaw-meeting/compact.log`

## 铁律

- 落盘期间只回短应答，不多话。
- 以 `STATE` 行为准；规则与应答词只有这一处来源。
- 自检有缺失就如实标注，别用「待确认」糊过去。
- 出纪要才读 transcript，且只读一次。

## 文件

- `scripts/capture.py` —— start / append / stop / check / status / path / compact
- `templates/summary_template.md`
- `references/architecture.md`
