//  main.m — TransNote
//  一个原生 macOS 应用：选中英文 → 右击 → 服务 → 英译中 / 英译中并加入笔记

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import "TransNoteEngine.h"
#import "TNHotKeys.h"
#import "TNSelection.h"
#import "TNVocab.h"

static BOOL gStartInBackground = NO;

#pragma mark - 界面构建辅助

static NSTextField *MakeLabel(NSString *text, NSRect frame) {
    NSTextField *f = [[NSTextField alloc] initWithFrame:frame];
    f.stringValue = text;
    f.editable = NO;
    f.selectable = NO;
    f.bezeled = NO;
    f.drawsBackground = NO;
    f.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    f.textColor = [NSColor secondaryLabelColor];
    return f;
}

static NSScrollView *MakeScroll(NSTextView **outView, NSRect frame, BOOL editable) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;
    scroll.drawsBackground = YES;

    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    tv.minSize = NSMakeSize(0, 0);
    tv.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    tv.verticallyResizable = YES;
    tv.horizontallyResizable = NO;
    tv.autoresizingMask = NSViewWidthSizable;
    tv.textContainer.containerSize = NSMakeSize(frame.size.width, FLT_MAX);
    tv.textContainer.widthTracksTextView = YES;
    tv.font = [NSFont systemFontOfSize:13];
    tv.editable = editable;
    tv.selectable = YES;
    tv.richText = NO;
    tv.allowsUndo = editable;
    tv.textContainerInset = NSMakeSize(6, 6);
    scroll.documentView = tv;
    *outView = tv;
    return scroll;
}

static void LogLine(NSString *message) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".transnote"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:@"transnote.log"];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if ([fm fileExistsAtPath:path]) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    } else {
        [data writeToFile:path atomically:YES];
    }
}

#pragma mark - 窗口控制器

@interface TNWindowController : NSWindowController
@property (nonatomic, strong) NSTextView *inputView;
@property (nonatomic, strong) NSTextView *outputView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *translateButton;
@property (nonatomic, strong) NSButton *noteButton;
@property (nonatomic, strong) NSButton *clipboardButton;
@property (nonatomic, strong) NSButton *vocabButton;
@property (nonatomic, strong) TNConfig *config;
@property (nonatomic, strong) TNResult *lastResult;
@property (nonatomic, copy)   NSString *lastSource;
@property (nonatomic, assign) BOOL pendingNote;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) NSUInteger translateGeneration;
@end

@implementation TNWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 880, 580);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"TransNote — 英译中";
    window.minSize = NSMakeSize(700, 440);
    [window center];
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (!self) return nil;

    _config = [TNConfig load];

    NSView *content = window.contentView;

    NSTextField *srcLabel = MakeLabel(@"原文（选中英文后右击 → 服务 → 英译中）", NSMakeRect(20, 542, 500, 18));
    srcLabel.autoresizingMask = NSViewMinYMargin;
    [content addSubview:srcLabel];

    NSTextView *inputTextView = nil;
    NSScrollView *inputScroll = MakeScroll(&inputTextView, NSMakeRect(20, 384, 840, 152), YES);
    _inputView = inputTextView;
    inputScroll.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:inputScroll];

    _translateButton = [NSButton buttonWithTitle:@"翻译" target:self action:@selector(performTranslate)];
    _translateButton.frame = NSMakeRect(20, 342, 90, 32);
    _translateButton.bezelStyle = NSBezelStyleRounded;
    _translateButton.keyEquivalent = @"\r";
    _translateButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    _translateButton.autoresizingMask = NSViewMinYMargin;
    [content addSubview:_translateButton];

    _noteButton = [NSButton buttonWithTitle:@"加入笔记" target:self action:@selector(performAddNote)];
    _noteButton.frame = NSMakeRect(118, 342, 110, 32);
    _noteButton.bezelStyle = NSBezelStyleRounded;
    _noteButton.autoresizingMask = NSViewMinYMargin;
    _noteButton.enabled = NO;
    [content addSubview:_noteButton];

    _noteButton.keyEquivalent = @"s";
    _noteButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;

    _clipboardButton = [NSButton buttonWithTitle:@"复制译文" target:self action:@selector(performCopy)];
    _clipboardButton.frame = NSMakeRect(236, 342, 110, 32);
    _clipboardButton.bezelStyle = NSBezelStyleRounded;
    _clipboardButton.autoresizingMask = NSViewMinYMargin;
    _clipboardButton.enabled = NO;
    _clipboardButton.keyEquivalent = @"c";
    _clipboardButton.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [content addSubview:_clipboardButton];

    // target 留空 => 沿响应链走到 AppDelegate 的 showVocab:
    _vocabButton = [NSButton buttonWithTitle:@"生词本" target:nil action:@selector(showVocab:)];
    _vocabButton.frame = NSMakeRect(354, 342, 96, 32);
    _vocabButton.bezelStyle = NSBezelStyleRounded;
    _vocabButton.autoresizingMask = NSViewMinYMargin;
    _vocabButton.toolTip = @"查看之前记录的生词（⌘L）";
    [content addSubview:_vocabButton];

    _translateButton.toolTip = [NSString stringWithFormat:@"翻译（窗口内 ⌘↩；全局 %@ 翻译剪贴板）",
                                [TNHotKey displaySpec:_config.hotkeyTranslate]];
    _noteButton.toolTip = [NSString stringWithFormat:@"追加到笔记（窗口内 ⌘S；全局 %@ 翻译剪贴板并保存）",
                           [TNHotKey displaySpec:_config.hotkeyAddNote]];
    _clipboardButton.toolTip = @"复制译文（⌘⇧C）";

    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(462, 349, 398, 18)];
    _statusLabel.editable = NO;
    _statusLabel.selectable = NO;
    _statusLabel.bezeled = NO;
    _statusLabel.drawsBackground = NO;
    _statusLabel.font = [NSFont systemFontOfSize:12];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _statusLabel.stringValue = [NSString stringWithFormat:@"笔记：%@", [[_config expandedNotesPath] stringByAbbreviatingWithTildeInPath]];
    [content addSubview:_statusLabel];

    NSTextField *dstLabel = MakeLabel(@"译文", NSMakeRect(20, 312, 200, 18));
    dstLabel.autoresizingMask = NSViewMinYMargin;
    [content addSubview:dstLabel];

    NSTextView *outputTextView = nil;
    NSScrollView *outputScroll = MakeScroll(&outputTextView, NSMakeRect(20, 20, 840, 284), NO);
    _outputView = outputTextView;
    outputScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:outputScroll];

    return self;
}

- (void)showWithText:(NSString *)text translate:(BOOL)doTranslate addNote:(BOOL)doNote {
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    if (!getenv("TRANSNOTE_NO_ACTIVATE")) [NSApp activateIgnoringOtherApps:YES];
    if (text) {
        self.inputView.string = text;
        [self.inputView setSelectedRange:NSMakeRange(0, 0)];
    }
    self.pendingNote = doNote;
    if (doTranslate) [self performTranslate];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.translateButton.enabled = !busy;
    self.noteButton.enabled = !busy && self.lastResult != nil;
    self.clipboardButton.enabled = !busy && self.lastResult != nil;
}

- (void)performTranslate {
    // 不再因为"正在翻译"就放弃：新的一次翻译会让旧的作废（按代次丢弃旧结果），
    // 否则热键连续按下时，新文本会被静默忽略。
    NSString *text = self.inputView.string ?: @"";
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        self.statusLabel.stringValue = @"请先粘贴或选中要翻译的文本。";
        return;
    }

    self.lastSource = trimmed;
    self.lastResult = nil;
    self.statusLabel.stringValue = @"翻译中…";
    [self setBusy:YES];

    self.translateGeneration += 1;
    NSUInteger generation = self.translateGeneration;
    TNConfig *config = self.config;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        TNResult *result = [TNEngine translate:trimmed config:config error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.translateGeneration) return;   // 已经有更新的一次翻译
            if (!result) {
                self.outputView.string = @"";
                self.statusLabel.stringValue = [NSString stringWithFormat:@"翻译失败：%@",
                                                error.localizedDescription ?: @"未知错误"];
                return;
            }
            self.lastResult = result;
            [self setBusy:NO];

            // 单词的话，把音标和词典释义一起显示出来（译文仍保持干净，方便复制）
            NSString *shown = result.translation;
            if (result.phonetic.length || result.definition.length) {
                NSMutableString *body = [NSMutableString string];
                if (result.phonetic.length)   [body appendFormat:@"%@\n\n", result.phonetic];
                if (result.definition.length) [body appendFormat:@"%@\n\n", result.definition];
                [body appendString:@"\u2014\u2014\u2014\u2014\u2014\u2014\n\n"];
                [body appendString:result.translation];
                shown = body;
            }
            self.outputView.string = shown;

            NSMutableString *status = [NSMutableString stringWithString:result.title];
            if (result.definition.length) [status appendString:@" · 词典"];
            if (config.copyToClipboard) {
                [TNEngine copyToClipboard:result.translation];
                [status appendString:@" · 译文已复制到剪贴板"];
            }
            self.statusLabel.stringValue = status;
            if (self.pendingNote) {
                self.pendingNote = NO;
                [self performAddNote];
            }
        });
    });
}

- (void)performAddNote {
    if (!self.lastResult) {
        self.statusLabel.stringValue = @"还没有可保存的译文。";
        return;
    }
    // 同一个词已经记过就不重复记（只比较忽略大小写/首尾引号后的原文）
    if (self.config.dedupe) {
        TNNoteEntry *existing = [TNNotes findEntryForSource:self.lastSource ?: @""
                                                     inPath:[self.config expandedNotesPath]];
        if (existing) {
            self.statusLabel.stringValue = [NSString stringWithFormat:
                @"「%@」已经记过了（%@），没有重复添加", self.lastSource, existing.date];
            return;
        }
    }
    NSError *error = nil;
    BOOL ok = [TNEngine appendNote:self.lastResult
                            source:self.lastSource ?: @""
                            config:self.config
                             error:&error];
    if (ok) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"已加入笔记 → %@",
                                        [[self.config expandedNotesPath] stringByAbbreviatingWithTildeInPath]];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"TNNotesChanged" object:nil];
    } else {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"写入笔记失败：%@",
                                        error.localizedDescription ?: @"未知错误"];
        NSBeep();
    }
}

- (void)performCopy {
    if (!self.lastResult) return;
    [TNEngine copyToClipboard:self.lastResult.translation];
    self.statusLabel.stringValue = @"译文已复制到剪贴板";
}

@end

#pragma mark - 应用代理

@interface TNAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) TNWindowController *controller;
@property (nonatomic, strong) TNHotKeyCenter *hotKeys;
@property (nonatomic, copy)   NSString *hotKeyReport;
@property (nonatomic, assign) BOOL serviceHandled;
@property (nonatomic, assign) NSTimeInterval lastHotKeyTime;
@property (nonatomic, assign) BOOL didPromptForTrust;
@property (nonatomic, strong) TNVocabWindowController *vocabController;
@end

@implementation TNAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [NSApp setServicesProvider:self];
    NSUpdateDynamicServices();
}

- (void)installHotKeys {
    self.hotKeys = [[TNHotKeyCenter alloc] init];
    TNConfig *config = self.controller.config;
    NSMutableArray<NSString *> *report = [NSMutableArray array];
    __weak TNAppDelegate *weakSelf = self;

    if (config.hotkeyTranslate.length) {
        BOOL ok = [self.hotKeys registerSpec:config.hotkeyTranslate identifier:1 handler:^{
            [weakSelf triggerHotKeyWithNote:NO];
        }];
        [report addObject:[NSString stringWithFormat:@"翻译 %@ %@",
                           [TNHotKey displaySpec:config.hotkeyTranslate], ok ? @"OK" : @"失败"]];
    }
    if (config.hotkeyAddNote.length) {
        BOOL ok = [self.hotKeys registerSpec:config.hotkeyAddNote identifier:2 handler:^{
            [weakSelf triggerHotKeyWithNote:YES];
        }];
        [report addObject:[NSString stringWithFormat:@"加入笔记 %@ %@",
                           [TNHotKey displaySpec:config.hotkeyAddNote], ok ? @"OK" : @"失败"]];
    }
    self.hotKeyReport = [report componentsJoinedByString:@"，"];
    NSLog(@"[TransNote] 全局快捷键：%@", self.hotKeyReport);
    LogLine([NSString stringWithFormat:@"启动完成，全局快捷键：%@；辅助功能授权：%@；模拟按键权限：%@",
             self.hotKeyReport,
             [TNSelection isTrusted] ? @"已授权" : @"未授权",
             CGPreflightPostEventAccess() ? @"有" : @"无"]);
}

- (void)requestAccessibility:(id)sender {
    [TNSelection requestTrust];
}

// 生词本：主窗口的按钮和菜单「操作 → 生词本」都走这里
- (void)showVocab:(id)sender {
    NSString *path = [self.controller.config expandedNotesPath];
    if (!self.vocabController) {
        self.vocabController = [[TNVocabWindowController alloc] initWithNotesPath:path];
    } else {
        self.vocabController.notesPath = path;
    }
    [self.vocabController reloadAndShow];
}

// 从 Carbon 事件回调进来的入口：只做防抖，然后立刻返回。
// 真正的活（要跑嵌套 runloop 等剪贴板更新）推到下一次主循环，
// 避免在事件处理过程里重入。
- (void)triggerHotKeyWithNote:(BOOL)withNote {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastHotKeyTime < 0.35) return;   // 按住不放会连发
    self.lastHotKeyTime = now;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self performHotKeyWithNote:withNote];
    });
}

// 优先取「当前选中的文字」；拿不到才退回剪贴板。
- (void)performHotKeyWithNote:(BOOL)withNote {
    NSString *text = nil;
    NSString *origin = nil;
    BOOL trusted = [TNSelection isTrusted];

    if (trusted) {
        // 先用「模拟 ⌘C」：它复制的一定是当前选区，最可靠。
        // 辅助功能 API 虽然不用碰剪贴板，但在实测中会返回陈旧选区，所以只当兜底。
        NSString *copied = [TNSelection selectedTextViaCopy];
        NSString *axText = copied.length ? nil : [TNSelection selectedTextViaAccessibility];
        LogLine([NSString stringWithFormat:@"  选区尝试：模拟⌘C=%@；AX=%@",
                 copied.length ? [NSString stringWithFormat:@"%lu 字", (unsigned long)copied.length]
                               : @"失败（没有选区）",
                 axText.length ? [NSString stringWithFormat:@"%lu 字", (unsigned long)axText.length]
                               : @"空"]);

        if (copied.length) {
            text = copied;
            origin = @"模拟 ⌘C 取的选区";
        } else if (axText.length) {
            text = axText;
            origin = @"辅助功能选区（兜底）";
        }
    }

    BOOL fromClipboard = NO;
    if (!text.length) {
        text = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
        origin = @"剪贴板";
        fromClipboard = YES;
    }
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";

    LogLine([NSString stringWithFormat:@"热键触发（%@）来源=%@ 长度=%lu 已授权=%@ 焦点[%@]",
             withNote ? @"翻译并加入笔记" : @"翻译", origin ?: @"无",
             (unsigned long)text.length, trusted ? @"是" : @"否",
             [TNSelection focusedElementDescription]]);

    // 剪贴板里是上一次的译文 —— 说明用户又按了一次但没复制新内容。
    // 这正是「自己跟自己乒乓」的成因：译文被写回剪贴板，下一按又被当成原文。
    NSString *lastTranslation = self.controller.lastResult.translation;
    if (fromClipboard && text.length && lastTranslation.length &&
        [text isEqualToString:lastTranslation]) {
        [self.controller showWithText:text translate:NO addNote:NO];
        self.controller.statusLabel.stringValue =
            @"剪贴板里还是上一次的译文，没有新的内容可翻。"
             "请先复制要翻译的文字；或在菜单「操作 → 启用「选中即翻译」」授权辅助功能后重启本应用，即可直接翻译选中的内容。";
        [self promptForTrustOnce];
        return;
    }

    if (!text.length) {
        [self.controller showWithText:@"" translate:NO addNote:NO];
        if (!trusted) {
            self.controller.statusLabel.stringValue =
                @"没有读到内容。想直接翻译选中的文字（不用先复制），请在菜单"
                 "「操作 → 启用「选中即翻译」」授权辅助功能，然后重启本应用。";
            [self promptForTrustOnce];
        } else {
            self.controller.statusLabel.stringValue = @"没有读到选中的文字，剪贴板也是空的。";
        }
        return;
    }

    [self.controller showWithText:text translate:YES addNote:withNote];
    if (!trusted) [self promptForTrustOnce];
}

// 只在第一次没授权时弹一次系统提示，避免反复打扰
- (void)promptForTrustOnce {
    if (self.didPromptForTrust) return;
    self.didPromptForTrust = YES;
    LogLine(@"请求辅助功能授权（为了直接读取选中文字）");
    [TNSelection requestTrust];
}

- (void)menuTranslateClipboard:(id)sender   { [self triggerHotKeyWithNote:NO]; }
- (void)menuTranslateAndNoteClipboard:(id)sender { [self triggerHotKeyWithNote:YES]; }

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.controller = [[TNWindowController alloc] init];
    [self installHotKeys];

    __weak TNAppDelegate *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:@"TNNotesChanged"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        [weakSelf.vocabController reload];
    }];

    // 由登录项在后台启动时不要弹窗
    if (gStartInBackground) return;

    // 被「服务」唤起时，服务回调会先于这里设置的延迟触发，从而不闪一下空窗口。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.serviceHandled) return;
        [self.controller showWindow:nil];
        [self.controller.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [self.controller.window makeFirstResponder:self.controller.inputView];
    });
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (self.controller) {
        [self.controller showWindow:nil];
        [self.controller.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
    return YES;
}

#pragma mark 服务回调

- (void)translateService:(NSPasteboard *)pboard
                userData:(NSString *)userData
                   error:(NSString **)error {
    NSString *text = [pboard stringForType:NSPasteboardTypeString];
    if (text.length == 0) {
        if (error) *error = @"没有读到选中的文本";
        return;
    }
    self.serviceHandled = YES;
    [self.controller showWithText:text translate:YES addNote:NO];
}

- (void)translateAndNoteService:(NSPasteboard *)pboard
                       userData:(NSString *)userData
                          error:(NSString **)error {
    NSString *text = [pboard stringForType:NSPasteboardTypeString];
    if (text.length == 0) {
        if (error) *error = @"没有读到选中的文本";
        return;
    }
    self.serviceHandled = YES;
    [self.controller showWithText:text translate:YES addNote:YES];
}

@end

#pragma mark - 主菜单

static void BuildMainMenu(void) {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"关于 TransNote" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"隐藏 TransNote" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"退出 TransNote" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"拷贝" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;

    NSMenuItem *winItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:winItem];
    NSMenu *winMenu = [[NSMenu alloc] initWithTitle:@"窗口"];
    [winMenu addItemWithTitle:@"最小化" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [winMenu addItemWithTitle:@"关闭" action:@selector(performClose:) keyEquivalent:@"w"];
    winItem.submenu = winMenu;

    TNConfig *config = [TNConfig load];
    NSMenuItem *actionItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:actionItem];
    NSMenu *actionMenu = [[NSMenu alloc] initWithTitle:@"操作"];
    [actionMenu addItemWithTitle:[NSString stringWithFormat:@"翻译剪贴板   %@",
                                  [TNHotKey displaySpec:config.hotkeyTranslate]]
                          action:@selector(menuTranslateClipboard:)
                   keyEquivalent:@""];
    [actionMenu addItemWithTitle:[NSString stringWithFormat:@"翻译剪贴板并加入笔记   %@",
                                  [TNHotKey displaySpec:config.hotkeyAddNote]]
                          action:@selector(menuTranslateAndNoteClipboard:)
                   keyEquivalent:@""];
    [actionMenu addItemWithTitle:@"生词本（查看已记录的生词）" action:@selector(showVocab:) keyEquivalent:@"l"];
    [actionMenu addItem:[NSMenuItem separatorItem]];
    [actionMenu addItemWithTitle:@"启用「选中即翻译」（辅助功能授权）…"
                          action:@selector(requestAccessibility:)
                   keyEquivalent:@""];
    actionItem.submenu = actionMenu;

    NSApp.mainMenu = mainMenu;
    [NSApp setWindowsMenu:winMenu];
}

#pragma mark - 命令行模式

static void Out(NSString *line) {
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    [[NSFileHandle fileHandleWithStandardOutput] writeData:data];
}

static NSString *ReadStdinIfPiped(void) {
    if (isatty(fileno(stdin))) return @"";
    NSData *data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
    if (!data) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *TextFromArgs(NSArray<NSString *> *args) {
    if (args.count > 2) return args[2];
    return ReadStdinIfPiped();
}

static int RunTranslateCLI(NSArray<NSString *> *args, BOOL save) {
    TNConfig *config = [TNConfig load];
    NSString *text = TextFromArgs(args);
    NSError *error = nil;
    TNResult *result = [TNEngine translate:text config:config error:&error];
    if (!result) {
        Out([NSString stringWithFormat:@"翻译失败：%@", error.localizedDescription]);
        return 2;
    }
    if (save) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (config.dedupe) {
            TNNoteEntry *existing = [TNNotes findEntryForSource:trimmed
                                                         inPath:[config expandedNotesPath]];
            if (existing) {
                Out([NSString stringWithFormat:@"「%@」已经记过了（%@），没有重复添加", trimmed, existing.date]);
                Out(result.translation);
                return 0;
            }
        }
        NSError *writeError = nil;
        if (![TNEngine appendNote:result
                           source:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                           config:config
                            error:&writeError]) {
            Out([NSString stringWithFormat:@"写入笔记失败：%@", writeError.localizedDescription]);
            return 3;
        }
        Out([NSString stringWithFormat:@"已加入笔记 → %@", [config expandedNotesPath]]);
    }
    Out(result.translation);
    return 0;
}

static int RunSelftest(void) {
    TNConfig *config = [TNConfig load];
    Out(@"TransNote 自检");
    Out([NSString stringWithFormat:@"  配置文件 : %@", [TNConfig configPath]]);
    Out([NSString stringWithFormat:@"  引擎     : %@", config.engine]);
    Out([NSString stringWithFormat:@"  笔记文件 : %@", [config expandedNotesPath]]);
    Out([NSString stringWithFormat:@"  语言方向 : %@ → %@（自动反向：%@）",
         config.sourceLanguage, config.targetLanguage, config.autoDirection ? @"开" : @"关"]);
    TNResult *result = [TNEngine translate:@"Hello, world. This is a self test." config:config error:NULL];
    if (!result) {
        Out(@"  翻译测试 : 失败");
        return 1;
    }
    Out([NSString stringWithFormat:@"  翻译测试 : OK -> %@", result.translation]);
    TNResult *back = [TNEngine translate:@"这是一个测试句子。" config:config error:NULL];
    Out([NSString stringWithFormat:@"  反向测试 : %@", back ? back.translation : @"失败"]);
    return 0;
}

static int RunHotKeyCheck(void) {
    TNConfig *config = [TNConfig load];
    Out(@"TransNote 全局快捷键");
    Out([NSString stringWithFormat:@"  英译中           : %@   %@",
         config.hotkeyTranslate, [TNHotKey displaySpec:config.hotkeyTranslate]]);
    Out([NSString stringWithFormat:@"  英译中并加入笔记  : %@   %@",
         config.hotkeyAddNote, [TNHotKey displaySpec:config.hotkeyAddNote]]);

    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    TNHotKeyCenter *center = [[TNHotKeyCenter alloc] init];

    unsigned int keyCode = 0, mods = 0;
    BOOL parsed = [TNHotKey parseSpec:config.hotkeyTranslate keyCode:&keyCode modifiers:&mods];
    Out([NSString stringWithFormat:@"  解析 英译中      : %@  keyCode=%u modifiers=0x%04X",
         parsed ? @"OK" : @"失败", keyCode, mods]);
    BOOL registered = [center registerSpec:config.hotkeyTranslate identifier:1 handler:^{}];
    Out([NSString stringWithFormat:@"  注册 英译中      : %@", registered ? @"OK" : @"失败"]);

    unsigned int keyCode2 = 0, mods2 = 0;
    BOOL parsed2 = [TNHotKey parseSpec:config.hotkeyAddNote keyCode:&keyCode2 modifiers:&mods2];
    Out([NSString stringWithFormat:@"  解析 加入笔记    : %@  keyCode=%u modifiers=0x%04X",
         parsed2 ? @"OK" : @"失败", keyCode2, mods2]);
    BOOL registered2 = [center registerSpec:config.hotkeyAddNote identifier:2 handler:^{}];
    Out([NSString stringWithFormat:@"  注册 加入笔记    : %@", registered2 ? @"OK" : @"失败"]);

    return (parsed && registered && parsed2 && registered2) ? 0 : 1;
}

// 模拟一次「服务」调用：走的是和右击菜单完全相同的代码路径。
static int RunServiceTest(NSArray<NSString *> *args, BOOL withNote) {
    NSString *text = args.count > 2 ? args[2]
                                    : @"Artificial intelligence is changing how we write software.";
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

    TNAppDelegate *delegate = [[TNAppDelegate alloc] init];
    [delegate applicationWillFinishLaunching:
        [NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification object:app]];
    delegate.controller = [[TNWindowController alloc] init];
    delegate.serviceHandled = YES;

    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];

    NSString *serviceError = nil;
    if (withNote) {
        [delegate translateAndNoteService:pasteboard userData:@"" error:&serviceError];
    } else {
        [delegate translateService:pasteboard userData:@"" error:&serviceError];
    }
    if (serviceError) Out([NSString stringWithFormat:@"服务回调报错：%@", serviceError]);

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:40];
    while ([deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        if (!delegate.controller.busy && delegate.controller.lastResult) break;
    }

    TNWindowController *wc = delegate.controller;
    Out([NSString stringWithFormat:@"窗口输入框 : %@", wc.inputView.string]);
    Out([NSString stringWithFormat:@"窗口译文   : %@", wc.outputView.string]);
    Out([NSString stringWithFormat:@"状态栏     : %@", wc.statusLabel.stringValue]);
    return wc.lastResult ? 0 : 1;
}

// 直接走一遍全局快捷键的处理逻辑（读剪贴板 → 翻译 → 可选写笔记）
static int RunTriggerTest(NSArray<NSString *> *args, BOOL withNote) {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

    TNAppDelegate *delegate = [[TNAppDelegate alloc] init];
    [delegate applicationWillFinishLaunching:
        [NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification object:app]];
    delegate.controller = [[TNWindowController alloc] init];

    [delegate triggerHotKeyWithNote:withNote];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:40];
    while ([deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        if (!delegate.controller.busy && delegate.controller.lastResult) break;
    }
    TNWindowController *wc = delegate.controller;
    Out([NSString stringWithFormat:@"剪贴板内容 : %@", wc.inputView.string]);
    Out([NSString stringWithFormat:@"译文       : %@", wc.outputView.string]);
    Out([NSString stringWithFormat:@"状态栏     : %@", wc.statusLabel.stringValue]);
    return wc.lastResult ? 0 : 1;
}

// 按当前筛选/排序导出 CSV（用于验证导出内容）
static int RunVocabExport(NSArray<NSString *> *args) {
    if (args.count < 3) {
        Out(@"用法: --vocab-export <输出路径> [搜索词] [排序列] [asc|desc] [时间序号]");
        return 1;
    }
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

    TNConfig *config = [TNConfig load];
    TNVocabWindowController *vocab =
        [[TNVocabWindowController alloc] initWithNotesPath:[config expandedNotesPath]];
    [vocab reload];
    if (args.count > 3) [vocab setSearchQuery:args[3]];
    if (args.count > 5) [vocab setSortKey:args[4] ascending:[args[5] isEqualToString:@"asc"]];
    if (args.count > 6) [vocab setTimeFilterIndex:[args[6] integerValue]];

    NSData *data = [TNNotes csvDataForEntries:vocab.filtered];
    NSError *error = nil;
    if (![data writeToFile:args[2] options:NSDataWritingAtomic error:&error]) {
        Out([NSString stringWithFormat:@"写入失败：%@", error.localizedDescription]);
        return 2;
    }
    Out([NSString stringWithFormat:@"已导出 %lu 条 → %@",
         (unsigned long)vocab.filtered.count, args[2]]);
    Out(@"---- CSV ----");
    Out([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"");
    return 0;
}

// 在指定文件上测试删除（只用于验证，不会碰真实笔记）
static int RunVocabDeleteTest(NSArray<NSString *> *args) {
    if (args.count < 4) {
        Out(@"用法: --vocab-delete-test <笔记文件> <块序号,逗号分隔> [备份文件]");
        return 1;
    }
    NSString *path = args[2];
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    for (NSString *part in [args[3] componentsSeparatedByString:@","]) {
        [indexes addIndex:(NSUInteger)[part integerValue]];
    }
    NSString *backup = args.count > 4 ? args[4] : nil;

    NSError *error = nil;
    if (![TNNotes removeEntriesAtIndexes:indexes fromPath:path backupPath:backup error:&error]) {
        Out([NSString stringWithFormat:@"失败：%@", error.localizedDescription]);
        return 2;
    }
    Out([NSString stringWithFormat:@"已按块序号 %@ 删除", args[3]]);
    if (backup) Out([NSString stringWithFormat:@"备份：%@", backup]);
    Out(@"---- 删除后的文件 ----");
    Out([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @"");
    return 0;
}

// 查一个词/一句话，打印完整的处理结果（验证词典与单词判定）
static int RunLookup(NSArray<NSString *> *args) {
    TNConfig *config = [TNConfig load];
    NSString *text = args.count > 2 ? args[2] : @"";
    NSError *error = nil;
    TNResult *result = [TNEngine translate:text config:config error:&error];
    if (!result) {
        Out([NSString stringWithFormat:@"失败：%@", error.localizedDescription]);
        return 1;
    }
    Out([NSString stringWithFormat:@"原文     : %@", text]);
    Out([NSString stringWithFormat:@"判定     : %@", result.isWord ? @"单词（会查词典）" : @"句子（只走翻译）"]);
    Out([NSString stringWithFormat:@"音标     : %@", result.phonetic.length ? result.phonetic : @"（无）"]);
    Out([NSString stringWithFormat:@"词典释义 : %@", result.definition.length ? result.definition : @"（无）"]);
    Out([NSString stringWithFormat:@"译文     : %@", result.translation]);
    Out([NSString stringWithFormat:@"引擎     : %@", result.engineUsed ?: @"?"]);
    return 0;
}

// 打印笔记文件里解析出来的生词（验证解析）
static int RunVocabDump(NSArray<NSString *> *args) {
    TNConfig *config = [TNConfig load];
    NSString *path = args.count > 2 ? args[2] : [config expandedNotesPath];
    NSArray<TNNoteEntry *> *entries = [TNNotes entriesAtPath:path];
    Out([NSString stringWithFormat:@"笔记文件 : %@", path]);
    Out([NSString stringWithFormat:@"记录条数 : %lu", (unsigned long)entries.count]);
    for (TNNoteEntry *entry in entries) {
        Out([NSString stringWithFormat:@"  [%@] %@（%@） → %@（%@）",
             entry.date, entry.source, entry.sourceLabel,
             entry.translation, entry.targetLabel]);
        if (entry.phonetic.length)   Out([NSString stringWithFormat:@"        音标：%@", entry.phonetic]);
        if (entry.definition.length) Out([NSString stringWithFormat:@"        释义：%@", entry.definition]);
    }
    return 0;
}

// 建生词本窗口、检查表格与搜索，不显示窗口
static int RunVocabUITest(NSArray<NSString *> *args) {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

    TNConfig *config = [TNConfig load];
    TNVocabWindowController *vocab =
        [[TNVocabWindowController alloc] initWithNotesPath:[config expandedNotesPath]];
    [vocab reload];

    Out([NSString stringWithFormat:@"窗口标题 : %@", vocab.window.title]);
    Out([NSString stringWithFormat:@"窗口尺寸 : %@", NSStringFromRect(vocab.window.frame)]);
    Out([NSString stringWithFormat:@"子视图数 : %lu", (unsigned long)vocab.window.contentView.subviews.count]);
    Out([NSString stringWithFormat:@"总记录数 : %lu", (unsigned long)vocab.entries.count]);
    Out([NSString stringWithFormat:@"表格行数 : %ld",
         (long)[vocab numberOfRowsInTableView:vocab.tableView]]);
    Out([NSString stringWithFormat:@"表格列数 : %ld", (long)vocab.tableView.numberOfColumns]);
    Out([NSString stringWithFormat:@"状态栏   : %@", vocab.statusLabel.stringValue]);

    if (args.count > 2) {
        [vocab setSearchQuery:args[2]];
    }
    if (args.count > 4) {
        [vocab setSortKey:args[3] ascending:[args[4] isEqualToString:@"asc"]];
    }
    if (args.count > 5) {
        [vocab setTimeFilterIndex:[args[5] integerValue]];
    }
    if (args.count > 6) {
        NSInteger times = [args[6] integerValue];
        for (NSInteger i = 0; i < times; i++) [vocab toggleRecordOrder:nil];
    }

    Out([NSString stringWithFormat:@"显示行数 : %ld", (long)[vocab numberOfRowsInTableView:vocab.tableView]]);
    Out([NSString stringWithFormat:@"状态栏   : %@", vocab.statusLabel.stringValue]);
    NSInteger rows = [vocab numberOfRowsInTableView:vocab.tableView];
    NSInteger limit = MIN(rows, 6);
    for (NSInteger i = 0; i < limit; i++) {
        Out([NSString stringWithFormat:@"  %@ | %@ | %@",
             [vocab tableView:vocab.tableView objectValueForTableColumn:vocab.tableView.tableColumns[0] row:i],
             [vocab tableView:vocab.tableView objectValueForTableColumn:vocab.tableView.tableColumns[1] row:i],
             [vocab tableView:vocab.tableView objectValueForTableColumn:vocab.tableView.tableColumns[3] row:i]]);
    }
    Out([NSString stringWithFormat:@"排序     : %@", vocab.tableView.sortDescriptors.firstObject ?: @"（记录顺序）"]);
    return 0;
}

// 复现「自己跟自己乒乓」：按三次热键，看第二次起是否被拦住
static int RunPingPongTest(void) {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

    TNAppDelegate *delegate = [[TNAppDelegate alloc] init];
    [delegate applicationWillFinishLaunching:
        [NSNotification notificationWithName:NSApplicationWillFinishLaunchingNotification object:app]];
    delegate.controller = [[TNWindowController alloc] init];

    for (int round = 1; round <= 3; round++) {
        NSString *clipboard = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"";
        delegate.lastHotKeyTime = 0;   // 绕过防抖，方便测试
        [delegate triggerHotKeyWithNote:NO];

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:40];
        while ([deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
            if (!delegate.controller.busy) break;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];

        Out([NSString stringWithFormat:@"第 %d 轮  按之前的剪贴板 = %@", round, clipboard]);
        Out([NSString stringWithFormat:@"         译文         = %@",
             delegate.controller.outputView.string.length ? delegate.controller.outputView.string : @"（无）"]);
        Out([NSString stringWithFormat:@"         状态栏       = %@", delegate.controller.statusLabel.stringValue]);
    }
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
        NSString *mode = args.count > 1 ? args[1] : nil;

        if ([mode isEqualToString:@"--version"]) {
            Out(@"TransNote 1.0");
            return 0;
        }
        if ([mode isEqualToString:@"--selftest"]) {
            return RunSelftest();
        }
        if ([mode isEqualToString:@"--hotkeys"]) {
            return RunHotKeyCheck();
        }
        if ([mode isEqualToString:@"--background"]) {
            gStartInBackground = YES;
        }
        if ([mode isEqualToString:@"--vocab-export"]) {
            return RunVocabExport(args);
        }
        if ([mode isEqualToString:@"--vocab-delete-test"]) {
            return RunVocabDeleteTest(args);
        }
        if ([mode isEqualToString:@"--lookup"]) {
            return RunLookup(args);
        }
        if ([mode isEqualToString:@"--vocab"]) {
            return RunVocabDump(args);
        }
        if ([mode isEqualToString:@"--vocab-ui"]) {
            return RunVocabUITest(args);
        }
        if ([mode isEqualToString:@"--pingpong-test"]) {
            return RunPingPongTest();
        }
        if ([mode isEqualToString:@"--trigger-hotkey"]) {
            return RunTriggerTest(args, NO);
        }
        if ([mode isEqualToString:@"--trigger-hotkey-note"]) {
            return RunTriggerTest(args, YES);
        }
        if ([mode isEqualToString:@"--service-test"]) {
            return RunServiceTest(args, NO);
        }
        if ([mode isEqualToString:@"--service-test-note"]) {
            return RunServiceTest(args, YES);
        }
        if ([mode isEqualToString:@"--print"]) {
            return RunTranslateCLI(args, NO);
        }
        if ([mode isEqualToString:@"--note"]) {
            return RunTranslateCLI(args, YES);
        }
        if ([mode isEqualToString:@"--register"]) {
            NSUpdateDynamicServices();
            Out(@"已请求刷新系统服务列表");
            return 0;
        }
        if ([mode isEqualToString:@"--dump-ui"]) {
            // 不显示窗口，只验证界面对象都建好了（无法截屏时的自检手段）
            NSApplication *probeApp = [NSApplication sharedApplication];
            [probeApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
            TNWindowController *wc = [[TNWindowController alloc] init];
            NSWindow *window = wc.window;
            Out([NSString stringWithFormat:@"窗口标题 : %@", window.title]);
            Out([NSString stringWithFormat:@"窗口尺寸 : %@", NSStringFromRect(window.frame)]);
            Out([NSString stringWithFormat:@"子视图数 : %lu", (unsigned long)window.contentView.subviews.count]);
            Out([NSString stringWithFormat:@"输入框   : %@", wc.inputView ? @"ok" : @"nil"]);
            Out([NSString stringWithFormat:@"输出框   : %@", wc.outputView ? @"ok" : @"nil"]);
            Out([NSString stringWithFormat:@"按钮     : %@ / %@ / %@ / %@",
                 wc.translateButton.title, wc.noteButton.title,
                 wc.clipboardButton.title, wc.vocabButton.title]);
            Out([NSString stringWithFormat:@"状态栏   : %@", wc.statusLabel.stringValue]);
            return 0;
        }
    }

    // 单实例保护：登录项是直接执行二进制文件的，绕过 LaunchServices 的去重。
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID.length) {
        for (NSRunningApplication *other in
             [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID]) {
            if (other.processIdentifier != getpid() && !other.terminated) {
                [other activateWithOptions:NSApplicationActivateIgnoringOtherApps];
                return 0;
            }
        }
    }

    NSApplication *app = [NSApplication sharedApplication];
    TNAppDelegate *delegate = [[TNAppDelegate alloc] init];
    app.delegate = delegate;
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    BuildMainMenu();
    [app run];
    return 0;
}
