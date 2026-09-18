#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TransNote - 选中英文右击翻译成中文，并可加入 Markdown 笔记。

由 macOS 快速操作（Automator Service）通过 stdin 传入选中的文本。
用法:
    transnote.py              弹出翻译面板（含「加入笔记」按钮）
    transnote.py --note       翻译后直接加入笔记，不弹面板
    transnote.py --print      只把译文打到 stdout
    transnote.py --text "..." 直接传入文本（调试）
    transnote.py --selftest   自检
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

APP_DIR = os.path.expanduser(os.environ.get("TRANSNOTE_HOME", "~/.transnote"))
CONFIG_PATH = os.path.join(APP_DIR, "config.json")
UI_JS = os.path.join(APP_DIR, "ui.js")
LOG_PATH = os.path.join(APP_DIR, "transnote.log")

DEFAULT_CONFIG = {
    "engine": "mymemory",
    "sourceLanguage": "en",
    "targetLanguage": "zh-CN",
    "autoDirection": True,
    "notesPath": "~/Documents/翻译笔记.md",
    "mymemoryEmail": "",
    "copyToClipboard": True,
    "chunkBytes": 450,
    "timeoutSeconds": 25,
}

CJK_RE = re.compile(u"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
LETTER_RE = re.compile(r"[A-Za-z]")
MYMEMORY_URL = "https://api.mymemory.translated.net/get"
CURL = "/usr/bin/curl"
OSASCRIPT = "/usr/bin/osascript"
PBCOPY = "/usr/bin/pbcopy"


# ---------------------------------------------------------------- 基础工具

def ensure_dir(path):
    if path and not os.path.isdir(path):
        os.makedirs(path, exist_ok=True)


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as fh:
            user = json.load(fh)
        if isinstance(user, dict):
            cfg.update(user)
    except (IOError, OSError, ValueError):
        pass
    return cfg


def save_config(cfg):
    ensure_dir(APP_DIR)
    with open(CONFIG_PATH, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")


def log(msg):
    try:
        ensure_dir(APP_DIR)
        stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write("[{}] {}\n".format(stamp, msg))
    except (IOError, OSError):
        pass


def shorten(path):
    home = os.path.expanduser("~")
    if path.startswith(home):
        return "~" + path[len(home):]
    return path


def copy_to_clipboard(text):
    try:
        subprocess.run([PBCOPY], input=text.encode("utf-8"), check=False)
        return True
    except OSError:
        return False


def applescript_quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def notify(title, message):
    try:
        script = "display notification {} with title {}".format(
            applescript_quote(message), applescript_quote(title))
        subprocess.run([OSASCRIPT, "-e", script], capture_output=True, check=False)
    except OSError:
        pass


def show_ui(payload, mode="panel"):
    """调用 JXA 面板；返回 note / copy / close / ok。"""
    data = dict(payload)
    data["mode"] = mode
    handle, tmp = tempfile.mkstemp(prefix="transnote-", suffix=".json")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False)
        proc = subprocess.run([OSASCRIPT, "-l", "JavaScript", UI_JS, tmp],
                              capture_output=True, text=True)
        if proc.returncode != 0:
            log("UI error: {}".format(proc.stderr.strip()))
            return "error"
        return proc.stdout.strip()
    except OSError as exc:
        log("UI exception: {}".format(exc))
        return "error"
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass


# ---------------------------------------------------------------- 翻译

def http_get(url, params, timeout):
    cmd = [CURL, "-sS", "--max-time", str(timeout), "--get"]
    for key, value in params:
        cmd.extend(["--data-urlencode", "{}={}".format(key, value)])
    cmd.append(url)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError("网络请求失败：{}".format(proc.stderr.strip() or proc.returncode))
    return proc.stdout


def byte_len(text):
    return len(text.encode("utf-8"))


def hard_cut(text, limit):
    total = 0
    for index, char in enumerate(text):
        total += byte_len(char)
        if total > limit:
            return text[:index]
    return text


def split_long(text, limit):
    if byte_len(text) <= limit:
        return [text]
    parts = re.split(r"(?<=[.!?。！？；;])\s+", text)
    chunks = []
    current = ""
    for part in parts:
        while byte_len(part) > limit:
            head = hard_cut(part, limit)
            if not head:
                break
            if current:
                chunks.append(current)
                current = ""
            chunks.append(head)
            part = part[len(head):].lstrip()
        if not part:
            continue
        candidate = (current + " " + part).strip() if current else part
        if byte_len(candidate) > limit:
            if current:
                chunks.append(current)
            current = part
        else:
            current = candidate
    if current:
        chunks.append(current)
    return chunks


def chunk_text(text, limit):
    chunks = []
    for para in re.split(r"\n\s*\n", text):
        para = para.strip()
        if para:
            chunks.extend(split_long(para, limit))
    return chunks or [text.strip()]


def translate_mymemory(text, source, target, cfg):
    limit = int(cfg.get("chunkBytes", 450))
    timeout = int(cfg.get("timeoutSeconds", 25))
    pair = "{}|{}".format(source, target)
    out = []
    for chunk in chunk_text(text, limit):
        params = [("q", chunk), ("langpair", pair)]
        email = (cfg.get("mymemoryEmail") or "").strip()
        if email:
            params.append(("de", email))
        raw = http_get(MYMEMORY_URL, params, timeout)
        try:
            body = json.loads(raw)
        except ValueError:
            raise RuntimeError("接口返回无法解析：{}".format(raw[:200]))
        status = str(body.get("responseStatus", ""))
        if status != "200":
            detail = body.get("responseDetails") or "接口返回 {}".format(status)
            raise RuntimeError(str(detail))
        piece = (body.get("responseData") or {}).get("translatedText") or ""
        if "MYMEMORY WARNING" in piece.upper():
            raise RuntimeError("MyMemory 今日免费额度已用完，可在 config.json 里填入 mymemoryEmail 提升额度。")
        out.append(piece.strip())
    return "\n".join(item for item in out if item)


def translate_text(text, source, target, cfg):
    engine = (cfg.get("engine") or "mymemory").lower()
    if engine == "mymemory":
        return translate_mymemory(text, source, target, cfg)
    raise RuntimeError("未知引擎：{}（请在 config.json 里改为 mymemory）".format(engine))


def detect_direction(text, cfg):
    source = cfg.get("sourceLanguage", "en")
    target = cfg.get("targetLanguage", "zh-CN")
    if cfg.get("autoDirection", True):
        cjk = len(CJK_RE.findall(text))
        letters = len(LETTER_RE.findall(text))
        if cjk > letters:
            return target, source, True
    return source, target, False


def label_for(code):
    if code.startswith("zh"):
        return "中文"
    if code == "en":
        return "英文"
    return code


# ---------------------------------------------------------------- 笔记

def quote_block(text):
    lines = text.split("\n")
    return "\n".join(("> " + ln) if ln.strip() else ">" for ln in lines)


def append_note(notes_path, source, translation, src_label, tgt_label):
    path = os.path.expanduser(notes_path)
    parent = os.path.dirname(path)
    if parent:
        ensure_dir(parent)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    fresh = not os.path.exists(path)
    parts = []
    if fresh:
        parts.append("# 翻译笔记\n")
    parts.append("\n## {}\n".format(stamp))
    parts.append("\n**原文（{}）**\n\n{}\n".format(src_label, quote_block(source)))
    parts.append("\n**译文（{}）**\n\n{}\n".format(tgt_label, quote_block(translation)))
    parts.append("\n---\n")
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("".join(parts))
    return path


# ---------------------------------------------------------------- 主流程

def read_input(args):
    if args.text is not None:
        return args.text
    if sys.stdin is None or sys.stdin.isatty():
        return ""
    try:
        return sys.stdin.read()
    except (IOError, OSError, UnicodeDecodeError):
        return ""


def selftest(cfg):
    print("TransNote 自检")
    print("  配置目录 : {}".format(APP_DIR))
    print("  配置文件 : {} ({})".format(CONFIG_PATH, "存在" if os.path.exists(CONFIG_PATH) else "默认值"))
    print("  引擎     : {}".format(cfg.get("engine")))
    print("  笔记文件 : {}".format(os.path.expanduser(cfg.get("notesPath", ""))))
    print("  面板脚本 : {} ({})".format(UI_JS, "存在" if os.path.exists(UI_JS) else "缺失"))
    for tool in (CURL, OSASCRIPT, PBCOPY):
        print("  {:8s}: {}".format(os.path.basename(tool), "OK" if os.path.exists(tool) else "缺失"))
    try:
        sample = translate_text("Hello, world. This is a self test.", "en", "zh-CN", cfg)
        print("  翻译测试 : OK -> {}".format(sample))
    except Exception as exc:  # noqa: BLE001
        print("  翻译测试 : 失败 -> {}".format(exc))
        return 1
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--note", action="store_true", help="翻译后直接加入笔记")
    parser.add_argument("--print", dest="print_only", action="store_true", help="只打印译文")
    parser.add_argument("--text", default=None, help="直接传入文本")
    parser.add_argument("--ui-test", action="store_true", help="只演示面板")
    parser.add_argument("--selftest", action="store_true", help="自检")
    args = parser.parse_args(argv)

    cfg = load_config()

    if args.selftest:
        return selftest(cfg)

    if args.ui_test:
        show_ui({"title": "英译中",
                 "subtitle": "这是一个面板演示。译文已复制到剪贴板。",
                 "body": "【原文 · 英文】\nThe quick brown fox jumps over the lazy dog.\n\n【译文 · 中文】\n快速的棕色狐狸跳过懒惰的狗。"},
                mode="panel")
        return 0

    text = (read_input(args) or "").strip().strip("\n").strip()
    if not text:
        log("空输入")
        if not args.print_only:
            show_ui({"title": "英译中",
                     "subtitle": "没有读到选中的文本",
                     "body": "用法：在任意 App 里选中英文，右击 →「快速操作 / 服务」→「英译中」。\n\n也可以直接运行：\n  /usr/bin/python3 ~/.transnote/transnote.py --text \"Hello world\""},
                    mode="confirm")
        return 1

    source, target, _reversed = detect_direction(text, cfg)
    src_label = label_for(source)
    tgt_label = label_for(target)
    title = "{} → {}".format(src_label, tgt_label)

    try:
        translation = translate_text(text, source, target, cfg)
    except Exception as exc:  # noqa: BLE001
        log("翻译失败: {}".format(exc))
        if args.print_only:
            print("")
        else:
            show_ui({"title": title, "subtitle": "翻译失败", "body": str(exc)}, mode="confirm")
        return 2

    if not translation:
        log("空译文")
        if args.print_only:
            print("")
        else:
            show_ui({"title": title, "subtitle": "没有拿到译文", "body": text}, mode="confirm")
        return 2

    if args.print_only:
        print(translation)
        return 0

    notes_path = os.path.expanduser(cfg.get("notesPath", DEFAULT_CONFIG["notesPath"]))

    if args.note:
        try:
            saved = append_note(notes_path, text, translation, src_label, tgt_label)
        except OSError as exc:
            show_ui({"title": title, "subtitle": "写入笔记失败", "body": str(exc)}, mode="confirm")
            return 3
        copy_to_clipboard(translation)
        show_ui({"title": title,
                 "subtitle": "已加入笔记",
                 "body": translation + "\n\n已保存到：\n" + shorten(saved)}, mode="confirm")
        return 0

    if cfg.get("copyToClipboard", True):
        copy_to_clipboard(translation)

    body = "【原文 · {}】\n{}\n\n【译文 · {}】\n{}".format(src_label, text, tgt_label, translation)
    choice = show_ui({"title": title,
                      "subtitle": "译文已复制到剪贴板。点「加入笔记」追加到 {}".format(shorten(notes_path)),
                      "body": body}, mode="panel")

    if choice == "copy":
        copy_to_clipboard(translation)
    elif choice == "note":
        try:
            saved = append_note(notes_path, text, translation, src_label, tgt_label)
        except OSError as exc:
            show_ui({"title": title, "subtitle": "写入笔记失败", "body": str(exc)}, mode="confirm")
            return 3
        show_ui({"title": title,
                 "subtitle": "已加入笔记",
                 "body": translation + "\n\n已保存到：\n" + shorten(saved)}, mode="confirm")
    return 0


if __name__ == "__main__":
    sys.exit(main())
