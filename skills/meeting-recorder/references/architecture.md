# 设计说明

## 组成

- 录音 / 转写：由上层客户端（录音 / ASR 前端）完成，本 skill 不碰音频。
- 本 skill 做三件事：文字落盘、清会话上文、结束时出纪要。
- 依赖：本机 openclaw 命令行；零第三方 Python 依赖。

## 流程

1. 开始：capture.py start，建目录并记下会话 key，回复尾句带「记录中」。
2. 逐句：capture.py append，写入文件，并在后台延迟几秒截断会话历史。
3. 结束：capture.py stop，读一次 transcript.md，生成 summary.md 并交付。

## 为什么清上文

同一会话中，每条消息的提示词都包含此前全部历史，第 k 条要重发前 k-1 条，成本是平方级。
实测 550 条约重发 6600 万 token（约 ¥14，其中缓存重读占 96%）。

每条落盘后把会话历史截断到最近几行（会话压缩命令的 max-lines 模式：只截断、旧记录归档为 .bak，不调用模型），
下一条只带最近几行，成本从平方级降为线性。截断在后台延迟执行，避免打断当前回合。

## 为什么状态能跨轮

清上文后看不到旧消息，因此把状态放在每条回复的尾句里；该回复会被保留在会话尾部，
下一轮读到上一句话即可判定「记录中 / 已结束」。因此 max_lines 不能小于能保住上一条回复的量（默认 3）。

## 落盘格式

```markdown
# 项目周会 — 会议原始记录

- 开始：2026-09-22 10:14:03

- [10:14:20] 今天要过一下排序逻辑
- [10:15:02] 先看业务侧的需求
```

## 已知取舍

- 说话人：不做声纹区分，不标。
- 固定开销：系统提示每条仍带一次，是常数项。
- 延迟窗口：delay_sec 内又来一条，该条会带上文，无碍。

## 状态与配置

- 状态：~/.config/openclaw-meeting/state.json
- 配置：~/.config/openclaw-meeting/config.json
- 截断日志：~/.config/openclaw-meeting/compact.log

```json
{
  "output_dir": "~/.openclaw/workspace/meetings",
  "session_key": "",
  "compact": { "enabled": true, "max_lines": 3, "delay_sec": 5 }
}
```

## 可选扩展

- 归档：接已有的笔记 / 云文档技能，把 summary.md 存出去。
- 说话人：若上游语音识别支持声纹，可在落盘时带说话人前缀。
