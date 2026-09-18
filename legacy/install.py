#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TransNote 安装器

把脚本安装到 ~/.transnote，并在 ~/Library/Services 生成两个「快速操作」：
    英译中           - 弹出翻译面板，含「加入笔记」按钮
    英译中并加入笔记   - 直接翻译并追加到 Markdown 笔记

用法:
    /usr/bin/python3 install.py           安装 / 更新
    /usr/bin/python3 install.py --uninstall 卸载
"""

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_BIN = os.path.join(HERE, "bin")
APP_DIR = os.path.expanduser("~/.transnote")
SERVICES_DIR = os.path.expanduser("~/Library/Services")
LSREGISTER = ("/System/Library/Frameworks/CoreServices.framework/Frameworks/"
              "LaunchServices.framework/Support/lsregister")
PBS = "/System/Library/CoreServices/pbs"
PYTHON = "/usr/bin/python3"

PAYLOAD_MAIN = "英译中"
PAYLOAD_NOTE = "英译中并加入笔记"
WORKFLOWS = [PAYLOAD_MAIN, PAYLOAD_NOTE]


def build_arguments():
    return {
        "0": {"default value": 0, "name": "inputMethod", "required": "0",
              "type": "0", "uuid": "0"},
        "1": {"default value": False, "name": "CheckedForUserDefaultShell",
              "required": "0", "type": "0", "uuid": "1"},
        "2": {"default value": "", "name": "source", "required": "0",
              "type": "0", "uuid": "2"},
        "3": {"default value": "", "name": "COMMAND_STRING", "required": "0",
              "type": "0", "uuid": "3"},
        "4": {"default value": "/bin/sh", "name": "shell", "required": "0",
              "type": "0", "uuid": "4"},
    }


def build_action(command):
    return {
        "AMAccepts": {"Container": "List", "Optional": True,
                      "Types": ["com.apple.cocoa.string"]},
        "AMActionVersion": "2.0.3",
        "AMApplication": ["Automator"],
        "AMParameterProperties": {
            "COMMAND_STRING": {}, "CheckedForUserDefaultShell": {},
            "inputMethod": {}, "shell": {}, "source": {},
        },
        "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
        "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
        "ActionName": "Run Shell Script",
        "ActionParameters": {
            "COMMAND_STRING": command,
            "CheckedForUserDefaultShell": True,
            "inputMethod": 0,
            "shell": "/bin/zsh",
            "source": "",
        },
        "BundleIdentifier": "com.apple.RunShellScript",
        "CFBundleVersion": "2.0.3",
        "CanShowSelectedItemsWhenRun": False,
        "CanShowWhenRun": True,
        "Category": ["AMCategoryUtilities"],
        "Class Name": "RunShellScriptAction",
        "InputUUID": str(uuid.uuid4()).upper(),
        "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
        "OutputUUID": str(uuid.uuid4()).upper(),
        "UUID": str(uuid.uuid4()).upper(),
        "UnlocalizedApplications": ["Automator"],
        "arguments": build_arguments(),
        "conversionLabel": 0,
        "isViewVisible": 1,
        "location": "309.000000:305.000000",
        "nibPath": ("/System/Library/Automator/Run Shell Script.action/"
                    "Contents/Resources/Base.lproj/main.nib"),
    }


def build_wflow(command):
    return {
        "AMApplicationBuild": "534",
        "AMApplicationVersion": "2.10",
        "AMDocumentVersion": "2",
        "actions": [{"action": build_action(command), "isViewVisible": 1}],
        "connectors": {},
        "workflowMetaData": {
            "applicationBundleIDsByPath": {},
            "applicationPaths": [],
            "inputTypeIdentifier": "com.apple.Automator.text",
            "outputTypeIdentifier": "com.apple.Automator.nothing",
            "presentationMode": 11,
            "processesInput": False,
            "serviceInputTypeIdentifier": "com.apple.Automator.text",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": False,
            "systemImageName": "NSActionTemplate",
            "useAutomaticInputType": False,
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        },
    }


def build_info(service_name):
    return {
        "NSServices": [{
            "NSBackgroundColorName": "background",
            "NSIconName": "NSActionTemplate",
            "NSMenuItem": {"default": service_name},
            "NSMessage": "runWorkflowAsService",
        }]
    }


def write_plist(path, obj):
    with open(path, "wb") as fh:
        plistlib.dump(obj, fh, fmt=plistlib.FMT_XML, sort_keys=True)


def make_workflow(name, command):
    bundle = os.path.join(SERVICES_DIR, name + ".workflow")
    contents = os.path.join(bundle, "Contents")
    if os.path.isdir(bundle):
        shutil.rmtree(bundle)
    os.makedirs(contents, exist_ok=True)
    write_plist(os.path.join(contents, "document.wflow"), build_wflow(command))
    write_plist(os.path.join(contents, "Info.plist"), build_info(name))
    subprocess.run(["/bin/chmod", "-R", "755", bundle], check=False)
    return bundle


def lsregister(path):
    if not os.path.exists(LSREGISTER):
        return False
    try:
        subprocess.run([LSREGISTER, "-f", path], capture_output=True, check=False)
        subprocess.run([LSREGISTER, "-R", SERVICES_DIR], capture_output=True, check=False)
        return True
    except OSError:
        return False


def refresh_services():
    done = []
    if os.path.exists(PBS):
        try:
            subprocess.run([PBS, "-flush"], capture_output=True, check=False)
            done.append("pbs -flush")
        except OSError:
            pass
    # pbs 只在启动时扫描 ~/Library/Services，必须重启才能看到新的快速操作。
    try:
        subprocess.run(["/usr/bin/killall", "pbs"], capture_output=True, check=False)
        done.append("killall pbs")
    except OSError:
        pass
    return done


def install():
    os.makedirs(APP_DIR, exist_ok=True)
    os.makedirs(SERVICES_DIR, exist_ok=True)

    for name in ("transnote.py", "ui.js"):
        src = os.path.join(SRC_BIN, name)
        dst = os.path.join(APP_DIR, name)
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o755)
        print("  安装 {}".format(dst))

    cfg = os.path.join(APP_DIR, "config.json")
    if not os.path.exists(cfg):
        from json import dump
        defaults = {
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
        with open(cfg, "w", encoding="utf-8") as fh:
            dump(defaults, fh, ensure_ascii=False, indent=2, sort_keys=True)
            fh.write("\n")
        print("  生成 {}".format(cfg))
    else:
        print("  保留已有 {}".format(cfg))

    runner = os.path.join(APP_DIR, "transnote.py")
    commands = {
        PAYLOAD_MAIN: '{} "{}"'.format(PYTHON, runner),
        PAYLOAD_NOTE: '{} "{}" --note'.format(PYTHON, runner),
    }

    print("")
    for name, command in commands.items():
        bundle = make_workflow(name, command)
        print("  快速操作 {}".format(bundle))
        lsregister(bundle)

    refresh_services()

    print("")
    print("完成。请在任意 App 中选中英文后右击：")
    print("  「快速操作 / Quick Actions」或「服务 / Services」-> 英译中")
    print("")
    print("如果没有出现，打开：系统设置 -> 键盘 -> 键盘快捷键 -> 服务 -> 文本，")
    print("勾选「英译中」和「英译中并加入笔记」。")
    return 0


def uninstall():
    for name in WORKFLOWS:
        bundle = os.path.join(SERVICES_DIR, name + ".workflow")
        if os.path.isdir(bundle):
            shutil.rmtree(bundle)
            print("  移除 {}".format(bundle))
    if os.path.isdir(APP_DIR):
        shutil.rmtree(APP_DIR)
        print("  移除 {}".format(APP_DIR))
    lsregister(SERVICES_DIR)
    refresh_services()
    print("已卸载（笔记文件保留）。")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--uninstall", action="store_true")
    args = parser.parse_args(argv)
    if args.uninstall:
        return uninstall()
    return install()


if __name__ == "__main__":
    sys.exit(main())
