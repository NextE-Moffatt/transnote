//  TNVocab.m

#import "TNVocab.h"
#import <AVFoundation/AVFoundation.h>

// NSTableView 默认不响应 Delete 键，这里自己接一下
@interface TNVocabTableView : NSTableView
@property (nonatomic, copy) void (^onDeleteKey)(void);
@end

@implementation TNVocabTableView
- (void)keyDown:(NSEvent *)event {
    NSString *chars = event.charactersIgnoringModifiers;
    unichar c = chars.length ? [chars characterAtIndex:0] : 0;
    if ((c == NSDeleteCharacter || c == NSBackspaceCharacter || c == 0x7F) && self.onDeleteKey) {
        self.onDeleteKey();
        return;
    }
    [super keyDown:event];
}
@end

static NSTextField *MakeVocabLabel(NSString *text, NSRect frame) {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.stringValue = text;
    field.editable = NO;
    field.selectable = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.font = [NSFont systemFontOfSize:12];
    field.textColor = [NSColor secondaryLabelColor];
    return field;
}

@implementation TNVocabWindowController

- (instancetype)initWithNotesPath:(NSString *)path {
    NSRect frame = NSMakeRect(0, 0, 880, 600);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"生词本";
    window.minSize = NSMakeSize(720, 440);
    [window center];
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (!self) return nil;
    _notesPath = [path copy];

    NSView *content = window.contentView;
    CGFloat W = frame.size.width;
    CGFloat H = frame.size.height;

    _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, H - 52, 400, 26)];
    _searchField.placeholderString = @"搜索原文或译文…";
    _searchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _searchField.target = self;
    _searchField.action = @selector(searchChanged:);
    _searchField.sendsSearchStringImmediately = YES;
    _searchField.sendsWholeSearchString = NO;
    [content addSubview:_searchField];

    NSButton *openButton = [NSButton buttonWithTitle:@"打开笔记文件"
                                              target:self
                                              action:@selector(openNotesFile:)];
    openButton.frame = NSMakeRect(W - 160, H - 54, 140, 28);
    openButton.bezelStyle = NSBezelStyleRounded;
    openButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:openButton];

    // ---- 第二行：时间范围 ----
    _timePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, H - 94, 140, 28) pullsDown:NO];
    [_timePopup addItemsWithTitles:@[@"全部时间", @"今天", @"昨天",
                                     @"最近 7 天", @"最近 30 天", @"自定义…"]];
    _timePopup.target = self;
    _timePopup.action = @selector(timeFilterChanged:);
    _timePopup.autoresizingMask = NSViewMinYMargin;
    _timePopup.toolTip = @"按记录时间筛选";
    [content addSubview:_timePopup];

    NSDatePicker *start = [[NSDatePicker alloc] initWithFrame:NSMakeRect(170, H - 94, 160, 26)];
    start.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    start.datePickerMode = NSDatePickerModeSingle;
    start.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    start.target = self;
    start.action = @selector(timeFilterChanged:);
    start.enabled = NO;
    start.autoresizingMask = NSViewMinYMargin;
    _startPicker = start;
    [content addSubview:start];

    NSTextField *dash = MakeVocabLabel(@"至", NSMakeRect(338, H - 90, 20, 18));
    dash.autoresizingMask = NSViewMinYMargin;
    [content addSubview:dash];

    NSDatePicker *end = [[NSDatePicker alloc] initWithFrame:NSMakeRect(360, H - 94, 160, 26)];
    end.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    end.datePickerMode = NSDatePickerModeSingle;
    end.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    end.target = self;
    end.action = @selector(timeFilterChanged:);
    end.enabled = NO;
    end.autoresizingMask = NSViewMinYMargin;
    _endPicker = end;
    [content addSubview:end];

    NSTextField *timeHint = MakeVocabLabel(@"（选「自定义…」后这两个日期框才可用）",
                                           NSMakeRect(530, H - 90, 340, 18));
    timeHint.autoresizingMask = NSViewMinYMargin;
    [content addSubview:timeHint];

    _resetOrderButton = [NSButton buttonWithTitle:@"记录顺序 ↑" target:self
                                          action:@selector(toggleRecordOrder:)];
    _resetOrderButton.frame = NSMakeRect(600, H - 54, 110, 28);
    _resetOrderButton.bezelStyle = NSBezelStyleRounded;
    _resetOrderButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    _resetOrderButton.toolTip = @"按记录先后排序；点一下在正序（最早在前）和倒序（最新在前）之间切换，并清掉列头排序";
    [content addSubview:_resetOrderButton];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 48, W - 40, H - 156)];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _tableView = [[TNVocabTableView alloc] initWithFrame:scroll.bounds];
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.rowHeight = 22;
    _tableView.allowsMultipleSelection = YES;   // 可一次选多条删除
    __weak TNVocabWindowController *weakSelf = self;
    ((TNVocabTableView *)_tableView).onDeleteKey = ^{ [weakSelf deleteSelected:nil]; };
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(copySource:);

    NSArray<NSArray *> *columns = @[
        @[@"date", @"时间", @130],
        @[@"source", @"原文", @200],
        @[@"phonetic", @"音标", @170],
        @[@"translation", @"译文", @330],
    ];
    for (NSArray<NSString *> *spec in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        column.minWidth = 60;
        column.sortDescriptorPrototype =
            [NSSortDescriptor sortDescriptorWithKey:spec[0] ascending:YES
                                         selector:@selector(localizedStandardCompare:)];
        [_tableView addTableColumn:column];
    }
    scroll.documentView = _tableView;
    [content addSubview:scroll];

    _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 16, 370, 18)];
    _statusLabel.editable = NO;
    _statusLabel.selectable = NO;
    _statusLabel.bezeled = NO;
    _statusLabel.drawsBackground = NO;
    _statusLabel.font = [NSFont systemFontOfSize:12];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _statusLabel.autoresizingMask = NSViewWidthSizable;
    [content addSubview:_statusLabel];

    _sourceClipButton = [NSButton buttonWithTitle:@"复制原文" target:self action:@selector(copySource:)];
    _sourceClipButton.frame = NSMakeRect(W - 218, 10, 95, 26);
    _sourceClipButton.bezelStyle = NSBezelStyleRounded;
    _sourceClipButton.autoresizingMask = NSViewMinXMargin;
    [content addSubview:_sourceClipButton];

    _translationClipButton = [NSButton buttonWithTitle:@"复制译文" target:self action:@selector(copyTranslation:)];
    _translationClipButton.frame = NSMakeRect(W - 115, 10, 95, 26);
    _translationClipButton.bezelStyle = NSBezelStyleRounded;
    _translationClipButton.autoresizingMask = NSViewMinXMargin;
    [content addSubview:_translationClipButton];

    _exportButton = [NSButton buttonWithTitle:@"导出 CSV" target:self action:@selector(exportCSV:)];
    _exportButton.frame = NSMakeRect(W - 482, 10, 100, 26);
    _exportButton.bezelStyle = NSBezelStyleRounded;
    _exportButton.autoresizingMask = NSViewMinXMargin;
    _exportButton.toolTip = @"把当前显示的内容（受搜索/时间筛选/排序影响）导出成 CSV，可直接导入 Anki";
    [content addSubview:_exportButton];

    _speakButton = [NSButton buttonWithTitle:@"朗读" target:self action:@selector(speakSource:)];
    _speakButton.frame = NSMakeRect(W - 374, 10, 70, 26);
    _speakButton.bezelStyle = NSBezelStyleRounded;
    _speakButton.autoresizingMask = NSViewMinXMargin;
    _speakButton.toolTip = @"朗读选中的词或句子";
    [content addSubview:_speakButton];

    _deleteButton = [NSButton buttonWithTitle:@"删除" target:self action:@selector(deleteSelected:)];
    _deleteButton.frame = NSMakeRect(W - 296, 10, 70, 26);
    _deleteButton.bezelStyle = NSBezelStyleRounded;
    _deleteButton.autoresizingMask = NSViewMinXMargin;
    _deleteButton.toolTip = @"删除选中的记录（Delete 键同样可以，删除前自动备份）";
    [content addSubview:_deleteButton];

    return self;
}

#pragma mark - 数据

- (void)reload {
    self.entries = [TNNotes entriesAtPath:self.notesPath];
    [self applyFilter];
}

- (void)applyFilter {
    NSArray<TNNoteEntry *> *matched = [TNNotes filterEntries:self.entries
                                                       query:self.searchField.stringValue ?: @""];
    NSMutableArray<TNNoteEntry *> *list = [NSMutableArray array];
    for (TNNoteEntry *entry in matched) {
        if ([self entryPassesTimeFilter:entry]) [list addObject:entry];
    }
    self.filtered = [self sortEntries:list];
    [self.tableView reloadData];

    NSMutableString *status = [NSMutableString string];
    if (self.entries.count == 0) {
        [status appendFormat:@"还没有记录。笔记文件：%@",
         [self.notesPath stringByAbbreviatingWithTildeInPath]];
    } else {
        [status appendFormat:@"共 %lu 条", (unsigned long)self.entries.count];
        if (self.filtered.count != self.entries.count) {
            [status appendFormat:@" · 当前显示 %lu 条", (unsigned long)self.filtered.count];
        }
        if (self.timePopup.indexOfSelectedItem > 0 &&
            self.timePopup.indexOfSelectedItem < 5) {
            [status appendFormat:@" · %@", self.timePopup.titleOfSelectedItem ?: @""];
        } else if (self.timePopup.indexOfSelectedItem == 5) {
            [status appendFormat:@" · %@ 至 %@",
             [self dayString:self.startPicker.dateValue],
             [self dayString:self.endPicker.dateValue]];
        }
        NSSortDescriptor *descriptor = self.tableView.sortDescriptors.firstObject;
        if (descriptor) {
            [status appendFormat:@" · 按%@%@", [self titleForKey:descriptor.key],
             descriptor.ascending ? @"升序" : @"降序"];
        } else {
            [status appendFormat:@" · 记录顺序（%@）",
             self.recordReversed ? @"最新在前" : @"最早在前"];
        }
    }
    self.statusLabel.stringValue = status;

    self.resetOrderButton.title = self.recordReversed ? @"记录顺序 ↓" : @"记录顺序 ↑";
    [self updateButtons];
}

- (NSString *)titleForKey:(NSString *)key {
    if ([key isEqualToString:@"date"]) return @"时间";
    if ([key isEqualToString:@"source"]) return @"原文";
    if ([key isEqualToString:@"phonetic"]) return @"音标";
    return @"译文";
}

- (NSString *)stringForEntry:(TNNoteEntry *)entry key:(NSString *)key {
    if ([key isEqualToString:@"date"]) return entry.date ?: @"";
    if ([key isEqualToString:@"source"]) return entry.source ?: @"";
    if ([key isEqualToString:@"phonetic"]) return entry.phonetic ?: @"";
    return entry.translation ?: @"";
}

- (NSArray<TNNoteEntry *> *)sortEntries:(NSArray<TNNoteEntry *> *)entries {
    NSSortDescriptor *descriptor = self.tableView.sortDescriptors.firstObject;
    if (!descriptor) {
        // 没按列排序时，按「记录顺序」，可选倒过来
        if (!self.recordReversed) return entries;
        NSMutableArray<TNNoteEntry *> *reversed = [NSMutableArray arrayWithCapacity:entries.count];
        for (TNNoteEntry *entry in [entries reverseObjectEnumerator]) [reversed addObject:entry];
        return reversed;
    }
    NSString *key = descriptor.key;
    BOOL ascending = descriptor.ascending;
    return [entries sortedArrayUsingComparator:^NSComparisonResult(TNNoteEntry *a, TNNoteEntry *b) {
        NSComparisonResult result = [[self stringForEntry:a key:key]
                                     localizedStandardCompare:[self stringForEntry:b key:key]];
        if (result == NSOrderedSame || ascending) return result;
        return (result == NSOrderedAscending) ? NSOrderedDescending : NSOrderedAscending;
    }];
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)old {
    [self applyFilter];
}

// 在「记录顺序正序」和「记录顺序倒序」之间切换，同时清掉列头排序
- (void)toggleRecordOrder:(id)sender {
    BOOL hasColumnSort = (self.tableView.sortDescriptors.count > 0);
    if (hasColumnSort) {
        // 本来在按列排序：先回到记录顺序的正序，这样第一次点总是可预期的
        [self.tableView setSortDescriptors:@[]];
        self.recordReversed = NO;
    } else {
        self.recordReversed = !self.recordReversed;
    }
    [self applyFilter];
}

#pragma mark - 时间筛选

- (NSDate *)dateFromStamp:(NSString *)stamp {
    if (!stamp.length) return nil;
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return [formatter dateFromString:stamp];
}

- (NSString *)dayString:(NSDate *)date {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [formatter stringFromDate:date];
}

- (BOOL)entryPassesTimeFilter:(TNNoteEntry *)entry {
    NSInteger index = self.timePopup.indexOfSelectedItem;
    if (index <= 0) return YES;                     // 全部时间

    NSDate *stamp = [self dateFromStamp:entry.date];
    if (!stamp) return YES;                         // 时间解析不了就别藏起来

    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *day = [calendar startOfDayForDate:stamp];
    NSDate *today = [calendar startOfDayForDate:[NSDate date]];
    NSDate *from = nil;
    NSDate *to = nil;

    if (index == 1) {          // 今天
        from = today; to = today;
    } else if (index == 2) {   // 昨天
        from = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0];
        to = from;
    } else if (index == 3) {   // 最近 7 天
        from = [calendar dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:today options:0];
        to = today;
    } else if (index == 4) {   // 最近 30 天
        from = [calendar dateByAddingUnit:NSCalendarUnitDay value:-29 toDate:today options:0];
        to = today;
    } else if (index == 5) {   // 自定义
        from = [calendar startOfDayForDate:self.startPicker.dateValue];
        to = [calendar startOfDayForDate:self.endPicker.dateValue];
    } else {
        return YES;
    }

    if (from && [day compare:from] == NSOrderedAscending) return NO;
    if (to && [day compare:to] == NSOrderedDescending) return NO;
    return YES;
}

- (void)timeFilterChanged:(id)sender {
    NSInteger index = self.timePopup.indexOfSelectedItem;
    BOOL custom = (index == 5);
    self.startPicker.enabled = custom;
    self.endPicker.enabled = custom;

    if (custom) {
        NSDate *today = [NSDate date];
        if (!self.entries.count) {
            self.startPicker.dateValue = today;
        } else {
            NSDate *earliest = nil;
            for (TNNoteEntry *entry in self.entries) {
                NSDate *d = [self dateFromStamp:entry.date];
                if (!d) continue;
                if (!earliest || [d compare:earliest] == NSOrderedAscending) earliest = d;
            }
            self.startPicker.dateValue = earliest ?: today;
        }
        self.endPicker.dateValue = today;
    }
    [self applyFilter];
}

- (void)updateButtons {
    BOOL has = ([self selectedEntry] != nil);
    self.sourceClipButton.enabled = has;
    self.translationClipButton.enabled = has;
    self.speakButton.enabled = has;
    self.deleteButton.enabled = (self.tableView.selectedRowIndexes.count > 0);
}

- (TNNoteEntry *)selectedEntry {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.filtered.count) return nil;
    return self.filtered[(NSUInteger)row];
}

- (void)reloadAndShow {
    [self reload];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - 表格

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.filtered.count;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.filtered.count) return @"";
    TNNoteEntry *entry = self.filtered[(NSUInteger)row];
    NSString *ident = column.identifier;
    if ([ident isEqualToString:@"date"]) return entry.date ?: @"";
    if ([ident isEqualToString:@"source"]) return entry.source ?: @"";
    if ([ident isEqualToString:@"phonetic"]) return entry.phonetic ?: @"";
    return entry.translation ?: @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateButtons];
}

#pragma mark - 动作

- (void)searchChanged:(id)sender {
    [self applyFilter];
}

- (void)setSearchQuery:(NSString *)query {
    self.searchField.stringValue = query ?: @"";
    [self applyFilter];
}

// 便于自动化验证：直接设置排序键
- (void)setSortKey:(NSString *)key ascending:(BOOL)ascending {
    if (!key.length) {
        [self.tableView setSortDescriptors:@[]];
    } else {
        [self.tableView setSortDescriptors:@[
            [NSSortDescriptor sortDescriptorWithKey:key ascending:ascending
                                         selector:@selector(localizedStandardCompare:)]
        ]];
    }
    [self applyFilter];
}

// 便于自动化验证：直接选择时间范围
- (void)setTimeFilterIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.timePopup.numberOfItems) return;
    [self.timePopup selectItemAtIndex:index];
    [self timeFilterChanged:nil];
}

- (void)copySource:(id)sender {
    TNNoteEntry *entry = [self selectedEntry];
    if (!entry.source.length) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:entry.source forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = @"已复制原文";
}

- (void)copyTranslation:(id)sender {
    TNNoteEntry *entry = [self selectedEntry];
    if (!entry.translation.length) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:entry.translation forType:NSPasteboardTypeString];
    self.statusLabel.stringValue = @"已复制译文";
}

// 朗读：中文条目用中文嗓音，英文条目用美式嗓音
- (void)speakSource:(id)sender {
    TNNoteEntry *entry = [self selectedEntry];
    NSString *text = entry.source.length ? entry.source : entry.translation;
    if (!text.length) return;

    BOOL isChinese = NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= 0x4E00 && c <= 0x9FFF) { isChinese = YES; break; }
    }

    if (!self.speaker) self.speaker = [[AVSpeechSynthesizer alloc] init];
    if (self.speaker.isSpeaking) [self.speaker stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    NSString *language = isChinese ? @"zh-CN" : @"en-US";
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:language];
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9f;
    [self.speaker speakUtterance:utterance];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"朗读：%@", text];
}

- (NSString *)backupPathForNotes {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".transnote/backups"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *name = [NSString stringWithFormat:@"%@-%@.md",
                      [self.notesPath lastPathComponent],
                      [formatter stringFromDate:[NSDate date]]];
    return [dir stringByAppendingPathComponent:name];
}

// 删除选中的记录：先确认，再备份，再改写文件
- (void)deleteSelected:(id)sender {
    NSIndexSet *rows = self.tableView.selectedRowIndexes;
    if (!rows.count) {
        self.statusLabel.stringValue = @"先选中要删除的行（可以按住 ⌘ 或 ⇧ 多选）。";
        NSBeep();
        return;
    }

    NSMutableIndexSet *blocks = [NSMutableIndexSet indexSet];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        if (row >= self.filtered.count) return;
        TNNoteEntry *entry = self.filtered[row];
        [blocks addIndex:(NSUInteger)entry.blockIndex];
        if (entry.source.length) [names addObject:entry.source];
    }];
    if (!blocks.count) return;

    NSString *preview = [names componentsJoinedByString:@"、"];
    if (preview.length > 200) preview = [[preview substringToIndex:200] stringByAppendingString:@"…"];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = [NSString stringWithFormat:@"删除 %lu 条记录？", (unsigned long)blocks.count];
    alert.informativeText = [NSString stringWithFormat:@"%@\n\n删除前会自动备份笔记文件，可以从备份恢复。", preview];
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSError *error = nil;
    NSString *backup = [self backupPathForNotes];
    if (![TNNotes removeEntriesAtIndexes:blocks
                                fromPath:self.notesPath
                              backupPath:backup
                                   error:&error]) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"删除失败：%@",
                                        error.localizedDescription ?: @"未知错误"];
        NSBeep();
        return;
    }
    [self reload];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"已删除 %lu 条 · 备份：%@",
                                    (unsigned long)blocks.count,
                                    [backup stringByAbbreviatingWithTildeInPath]];
}

// 导出当前「看到的内容」——已经算上搜索、时间筛选和排序
- (void)exportCSV:(id)sender {
    if (!self.filtered.count) {
        self.statusLabel.stringValue = @"当前没有可导出的记录。";
        NSBeep();
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"导出生词本";
    panel.nameFieldStringValue = @"生词本.csv";
    panel.message = [NSString stringWithFormat:@"将导出当前显示的 %lu 条记录",
                     (unsigned long)self.filtered.count];
    if ([panel runModal] != NSModalResponseOK) return;

    NSData *data = [TNNotes csvDataForEntries:self.filtered];
    NSError *error = nil;
    if (![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"导出失败：%@",
                                        error.localizedDescription ?: @"未知错误"];
        NSBeep();
        return;
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"已导出 %lu 条 → %@",
                                    (unsigned long)self.filtered.count,
                                    [panel.URL.path stringByAbbreviatingWithTildeInPath]];
}

- (void)openNotesFile:(id)sender {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.notesPath]) {
        self.statusLabel.stringValue = @"笔记文件还不存在，先在主窗口点「加入笔记」记一条吧。";
        NSBeep();
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:self.notesPath]];
}

@end
