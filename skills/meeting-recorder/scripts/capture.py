#!/usr/bin/env python3
"""会议记录：文字增量落盘 + 会话上文截断（空闲守卫） + 完整性自检。

- 不做录音/转写：文字由上层客户端逐句送来，这里只负责追加到文件。
- append/start 后，脱离进程启动 worker：等会话空闲（status != running）再截断会话历史，
  避免截断撞上进行中的回合导致会话卡死。
- 输出末尾带一行 STATE（记录中/结束 + 下一条命令 + 该回的短应答）。
- stop 会顺带跑完整性自检（CHECK）。
- 零第三方依赖，只用标准库。
"""
import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta

STATE_DIR = os.path.expanduser("~/.config/openclaw-meeting")
STATE = os.path.join(STATE_DIR, "state.json")
CFG = os.path.join(STATE_DIR, "config.json")
LOG = os.path.join(STATE_DIR, "compact.log")
OPENCLAW = shutil.which("openclaw") or "/usr/local/bin/openclaw"
SELF = os.path.abspath(__file__)
HEADER_LINES = 4  # 标题 / 空行 / 开始时间 / 空行
ENTRY_RE = re.compile(r"^- \[(\d{2}:\d{2}:\d{2})\]\s?(.*)$")
SPEAKER_RE = re.compile(r"^([^：:]{1,10})[：:]")


def cfg(key, default=None):
    try:
        d = json.load(open(CFG, encoding="utf-8"))
    except Exception:
        d = {}
    cur = d
    for k in key.split("."):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return default
    return cur


def load_state():
    try:
        return json.load(open(STATE, encoding="utf-8"))
    except Exception:
        return {}


def save_state(s):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as f:
        json.dump(s, f, ensure_ascii=False, indent=2)


def slug(s):
    s = re.sub(r"[^\w\u4e00-\u9fff-]+", "_", s, flags=re.UNICODE).strip("_")
    return s[:60] or "meeting"


def transcript_path(st):
    return os.path.join(st["dir"], "transcript.md")


def total_lines(path):
    try:
        with open(path, encoding="utf-8") as f:
            return sum(1 for _ in f)
    except Exception:
        return 0


def entries(path):
    out = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = ENTRY_RE.match(line.rstrip("\n"))
                if m:
                    out.append((m.group(1), m.group(2)))
    except Exception:
        pass
    return out


def count_entries(path):
    n = len(entries(path))
    return n if n else max(total_lines(path) - HEADER_LINES, 0)


def ack_word():
    return str(cfg("ack", "收到")) or "收到"


def state_recording(n):
    return (f'STATE 记录中 · 已记 {n} 句 · 下一条：python3 {SELF} append --text "<本条原文>"，'
            f"然后只回复「{ack_word()}」")


# ---------- 完整性自检 ----------

def check_transcript(path):
    ents = entries(path)
    issues = []

    i = 0
    while i < len(ents):
        j = i
        while j + 1 < len(ents) and ents[j + 1][0] == ents[i][0]:
            j += 1
        run = j - i + 1
        if run >= 3:
            issues.append(f"{ents[i][0]} 连续 {run} 条相同时间戳（疑似重复投递/丢包）")
        i = j + 1

    for k in range(1, len(ents)):
        if ents[k][1].strip() and ents[k][1].strip() == ents[k - 1][1].strip():
            issues.append(f"{ents[k][0]} 与上一条内容完全相同（疑似重复投递）")

    for t, txt in ents:
        if len(txt.strip()) < 2:
            issues.append(f"{t} 条目内容过短/为空（疑似截断）")

    for k, (t, txt) in enumerate(ents):
        if not txt.rstrip().endswith(("？", "?")):
            continue
        nxt = ents[k + 1][1].rstrip() if k + 1 < len(ents) else ""
        if nxt == "" or nxt.endswith(("？", "?")):
            issues.append(f'{t} 问句后未见应答：「{txt[:24]}…」（疑似应答缺失）')

    spk = [(t, m.group(1)) for t, txt in ents for m in [SPEAKER_RE.match(txt)] if m]
    run = 1
    for k in range(1, len(spk)):
        if spk[k][1] == spk[k - 1][1]:
            run += 1
            if run == 5:
                issues.append(f"{spk[k][0]} 起「{spk[k][1]}」连续 {run}+ 条发言（留意说话人识别/交替异常）")
        else:
            run = 1

    return ents, issues


def print_check(path):
    ents, issues = check_transcript(path)
    print(f"CHECK 条目={len(ents)} · 疑似缺失 {len(issues)} 处")
    for it in issues:
        print(f"  - {it}")
    if issues:
        print("NOTE 出纪要时必须在「数据质量备注」里显式写出上述缺失，不要笼统写成「待确认」")
    return len(issues)


# ---------- 清上文（带空闲守卫） ----------

def session_status(key):
    """返回该会话的运行时状态（running/done/killed/None/''）。"""
    try:
        r = subprocess.run([OPENCLAW, "sessions", "--json"], capture_output=True,
                           text=True, timeout=60)
        d = json.loads(r.stdout)
        rows = d.get("sessions", d) if isinstance(d, dict) else d
        for x in rows:
            if x.get("key") == key:
                return x.get("status") or ""
    except Exception:
        pass
    return ""


def do_compact_now(key, max_lines):
    cmd = (f"{shlex.quote(OPENCLAW)} sessions compact {shlex.quote(key)}"
           f" --max-lines {max_lines} --json")
    return subprocess.run(["/bin/sh", "-c", cmd], capture_output=True, text=True, timeout=180)


def spawn_worker(key, max_lines, delay, tries, wait):
    """脱离进程启动 worker：等会话空闲再截断。"""
    cmd = (f"{shlex.quote(sys.executable)} {shlex.quote(SELF)} _compact-worker "
           f"{shlex.quote(key)} {int(max_lines)} {float(delay)} {int(tries)} {float(wait)}")
    subprocess.Popen(["/bin/sh", "-c", cmd], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cmd_compact_worker(key, max_lines, delay, tries, wait):
    time.sleep(max(delay, 0))
    for _ in range(max(tries, 0)):
        st = session_status(key)
        if st != "running":
            break
        time.sleep(max(wait, 1))
    r = do_compact_now(key, max_lines)
    out = (r.stdout or r.stderr).strip()
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().strftime('%H:%M:%S')}] key={key} status={session_status(key)}\n{out}\n")
    except Exception:
        pass


def do_compact(st, session=None, foreground=False):
    c = cfg("compact", {}) or {}
    if not c.get("enabled", True):
        print("COMPACT disabled (config.compact.enabled=false)")
        return
    key = session or st.get("session") or cfg("session_key") or ""
    if not key:
        print("WARN 没有会话 key，跳过清上文（start --session <key> 或 config.session_key）", file=sys.stderr)
        return
    max_lines = int(c.get("max_lines", 6))
    if foreground:
        r = do_compact_now(key, max_lines)
        print((r.stdout or r.stderr).strip() or f"COMPACT exit={r.returncode}")
        return
    delay = float(c.get("delay_sec", 5))
    tries = int(c.get("wait_tries", 20))
    wait = float(c.get("wait_sec", 3))
    try:
        spawn_worker(key, max_lines, delay, tries, wait)
        print(f"COMPACT queued key={key} max_lines={max_lines} delay={delay}s（等会话空闲后再截断）")
    except Exception as e:
        print(f"COMPACT schedule failed: {e}", file=sys.stderr)


# ---------- 子命令 ----------

def cmd_start(title, session=None):
    out = os.path.expanduser(str(cfg("output_dir", "~/.openclaw/workspace/meetings")))
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    d = os.path.join(out, f"{ts}-{slug(title)}")
    os.makedirs(d, exist_ok=True)
    tp = os.path.join(d, "transcript.md")
    if not os.path.exists(tp):
        with open(tp, "w", encoding="utf-8") as f:
            f.write(f"# {title} — 会议原始记录\n\n")
            f.write(f"- 开始：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
    save_state({
        "active": True,
        "dir": d,
        "title": title,
        "session": session or cfg("session_key") or "",
        "started": datetime.now().isoformat(timespec="seconds"),
    })
    print(f"STARTED dir={d}")
    print(state_recording(count_entries(tp)))
    do_compact(load_state(), session=session)


def read_text(args):
    if args.stdin:
        return sys.stdin.read()
    if args.file:
        with open(os.path.expanduser(args.file), encoding="utf-8") as f:
            return f.read()
    return args.text or ""


def cmd_append(args):
    st = load_state()
    if not st.get("active"):
        print("ERROR 没有进行中的会议，请先 start", file=sys.stderr)
        sys.exit(1)
    text = read_text(args)
    if not text.strip():
        print("ERROR 输入为空（--text / --file / --stdin 三选一）", file=sys.stderr)
        sys.exit(1)
    tp = transcript_path(st)
    parts = [p.strip() for p in text.splitlines() if p.strip()]
    base = datetime.now()
    with open(tp, "a", encoding="utf-8") as f:
        for k, p in enumerate(parts):
            t = (base + timedelta(seconds=k)).strftime("%H:%M:%S")
            f.write(f"- [{t}] {p}\n")
    print(f"APPENDED 条={len(parts)} lines={total_lines(tp)} file={tp}")
    print(state_recording(count_entries(tp)))
    do_compact(st, session=args.session)


def cmd_stop():
    st = load_state()
    if not st.get("active"):
        print("IDLE 没有进行中的会议")
        return
    tp = transcript_path(st)
    st["active"] = False
    st["ended"] = datetime.now().isoformat(timespec="seconds")
    save_state(st)
    print(f"STOPPED dir={st['dir']} lines={total_lines(tp)}")
    print(f"STATE 记录结束 · 纪要来源：{tp}")
    print_check(tp)


def cmd_check():
    st = load_state()
    tp = transcript_path(st) if st.get("dir") else None
    if not tp or not os.path.exists(tp):
        print("IDLE 没有可检查的会议记录")
        return
    print(tp)
    print_check(tp)


def cmd_status():
    st = load_state()
    if st.get("active"):
        tp = transcript_path(st)
        print(f"RECORDING title={st.get('title','')} lines={total_lines(tp)}")
        print(tp)
        print(state_recording(count_entries(tp)))
    else:
        print("IDLE")


def cmd_path():
    st = load_state()
    if not st.get("dir"):
        print("IDLE")
        return
    print(transcript_path(st))


def main():
    p = argparse.ArgumentParser(description="会议记录：文字增量落盘 + 清上文 + 自检")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("start", help="开始会议记录")
    s.add_argument("title", nargs="?", default="会议")
    s.add_argument("--session", default=None, help="当前会话 key（用于清上文）")

    a = sub.add_parser("append", help="追加一句/一段（三选一：--text/--file/--stdin）")
    a.add_argument("--text", default=None)
    a.add_argument("--file", default=None)
    a.add_argument("--stdin", action="store_true")
    a.add_argument("--session", default=None)

    sub.add_parser("stop", help="结束会议（含自检）")
    sub.add_parser("check", help="完整性自检")
    sub.add_parser("status", help="状态")
    sub.add_parser("path", help="当前 transcript 路径")

    c = sub.add_parser("compact", help="手动清一次上文（前台）")
    c.add_argument("--session", default=None)

    w = sub.add_parser("_compact-worker", help=argparse.SUPPRESS)
    w.add_argument("key")
    w.add_argument("max_lines", type=int)
    w.add_argument("delay", type=float)
    w.add_argument("tries", type=int)
    w.add_argument("wait", type=float)

    args = p.parse_args()
    if args.cmd == "start":
        cmd_start(args.title, args.session)
    elif args.cmd == "append":
        cmd_append(args)
    elif args.cmd == "stop":
        cmd_stop()
    elif args.cmd == "check":
        cmd_check()
    elif args.cmd == "status":
        cmd_status()
    elif args.cmd == "path":
        cmd_path()
    elif args.cmd == "compact":
        do_compact(load_state(), session=args.session, foreground=True)
    elif args.cmd == "_compact-worker":
        cmd_compact_worker(args.key, args.max_lines, args.delay, args.tries, args.wait)


if __name__ == "__main__":
    main()
