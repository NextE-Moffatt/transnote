//  TNNotes.m

#import "TNNotes.h"

@implementation TNNoteEntry
@end

@implementation TNNotes

// 从 "**原文（英文）**" 这类行里取出括号里的标签
static NSString *LabelInLine(NSString *line) {
    NSRange open = [line rangeOfString:@"\uFF08"];   // （
    NSRange close = [line rangeOfString:@"\uFF09"];  // ）
    if (open.location == NSNotFound || close.location == NSNotFound ||
        close.location <= open.location) {
        return @"";
    }
    return [line substringWithRange:NSMakeRange(open.location + open.length,
                                                close.location - open.location - open.length)];
}

// 在 block 里找 marker 之后连续的 "> " 引用行，拼成正文
static NSString *SectionAfterMarker(NSString *block, NSString *marker, NSString **labelOut) {
    NSRange found = [block rangeOfString:marker];
    if (found.location == NSNotFound) return nil;

    NSString *rest = [block substringFromIndex:found.location + found.length];
    NSArray<NSString *> *lines = [rest componentsSeparatedByString:@"\n"];

    if (labelOut) {
        for (NSString *line in lines) {
            if ([line containsString:@"\uFF08"]) { *labelOut = LabelInLine(line); break; }
            if ([line stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceAndNewlineCharacterSet]].length) break;
        }
    }

    NSMutableArray<NSString *> *body = [NSMutableArray array];
    BOOL started = NO;
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@">"]) {
            started = YES;
            NSString *content = [trimmed substringFromIndex:1];
            if ([content hasPrefix:@" "]) content = [content substringFromIndex:1];
            [body addObject:content];
        } else if (started) {
            break;
        }
    }
    return started ? [body componentsJoinedByString:@"\n"] : nil;
}

+ (NSArray<TNNoteEntry *> *)entriesAtPath:(NSString *)path {
    NSString *text = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
    if (!text.length) return @[];

    NSMutableArray<TNNoteEntry *> *entries = [NSMutableArray array];
    // 每条记录以 "## 时间" 开头，按它切块（第 0 块是文件标题）
    NSArray<NSString *> *blocks = [text componentsSeparatedByString:@"\n## "];
    for (NSUInteger i = 1; i < blocks.count; i++) {
        NSString *block = blocks[i];
        NSArray<NSString *> *lines = [block componentsSeparatedByString:@"\n"];

        TNNoteEntry *entry = [[TNNoteEntry alloc] init];
        entry.blockIndex = (NSInteger)i;
        entry.date = [[lines firstObject] stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        NSString *srcLabel = @"";
        entry.source = SectionAfterMarker(block, @"**\u539F\u6587", &srcLabel);
        entry.sourceLabel = srcLabel;

        NSString *tgtLabel = @"";
        entry.translation = SectionAfterMarker(block, @"**\u8BD1\u6587", &tgtLabel);
        entry.targetLabel = tgtLabel;

        // 可选段落：只有单词才有；老记录没有这两段也照样解析
        entry.phonetic = SectionAfterMarker(block, @"**\u97F3\u6807", NULL);
        entry.definition = SectionAfterMarker(block, @"**\u8BCD\u5178\u91CA\u4E49", NULL);

        if (!entry.source.length && !entry.translation.length) continue;
        entry.searchBlob = [[NSString stringWithFormat:@"%@\n%@\n%@\n%@",
                             entry.source ?: @"", entry.translation ?: @"",
                             entry.phonetic ?: @"", entry.definition ?: @""] lowercaseString];
        [entries addObject:entry];
    }
    return entries;
}

+ (NSString *)normalizeKey:(NSString *)text {
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    t = [t stringByTrimmingCharactersInSet:
         [NSCharacterSet characterSetWithCharactersInString:@"\"'\u201C\u201D\u2018\u2019.,;:!?()[]{}"]];
    return [t lowercaseString];
}

+ (TNNoteEntry *)findEntryForSource:(NSString *)source inPath:(NSString *)path {
    NSString *key = [self normalizeKey:source ?: @""];
    if (!key.length) return nil;
    for (TNNoteEntry *entry in [self entriesAtPath:path]) {
        if ([[self normalizeKey:entry.source ?: @""] isEqualToString:key]) return entry;
    }
    return nil;
}

+ (NSString *)csvEscape:(NSString *)field {
    NSString *s = field ?: @"";
    BOOL needsQuote = [s containsString:@","] || [s containsString:@"\""] ||
                      [s containsString:@"\n"] || [s containsString:@"\r"];
    if (!needsQuote) return s;
    return [NSString stringWithFormat:@"\"%@\"",
            [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

// 词典释义可能有好几行，压成一行，免得撑坏 CSV/Anki 的字段
+ (NSString *)flatten:(NSString *)text {
    NSString *s = [text stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"; "];
    return s ?: @"";
}

+ (NSData *)csvDataForEntries:(NSArray<TNNoteEntry *> *)entries {
    NSMutableString *csv = [NSMutableString stringWithString:@"原文,音标,词典释义,译文,时间\n"];
    for (TNNoteEntry *entry in entries) {
        NSArray<NSString *> *fields = @[
            entry.source ?: @"",
            entry.phonetic ?: @"",
            [self flatten:entry.definition],
            entry.translation ?: @"",
            entry.date ?: @"",
        ];
        NSMutableArray<NSString *> *escaped = [NSMutableArray arrayWithCapacity:fields.count];
        for (NSString *field in fields) [escaped addObject:[self csvEscape:field]];
        [csv appendFormat:@"%@\n", [escaped componentsJoinedByString:@","]];
    }
    // 加 UTF-8 BOM，这样 Excel 打开也不会乱码（Anki 会自动忽略）
    NSMutableData *data = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
    NSData *body = [csv dataUsingEncoding:NSUTF8StringEncoding];
    if (body) [data appendData:body];
    return data;
}

+ (BOOL)removeEntriesAtIndexes:(NSIndexSet *)indexes
                      fromPath:(NSString *)path
                    backupPath:(NSString *)backupPath
                         error:(NSError **)error {
    if (!indexes.count) return YES;
    NSError *readError = nil;
    NSString *text = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:&readError];
    if (!text) {
        if (error) *error = readError;
        return NO;
    }

    // 先备份，再改写；万一写坏了还能从这个文件恢复
    if (backupPath.length) {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:[backupPath stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm copyItemAtPath:path toPath:backupPath error:NULL];
    }

    // 解析和删除用同一种切分方式，块序号才对得上
    NSMutableArray<NSString *> *blocks = [[text componentsSeparatedByString:@"\n## "] mutableCopy];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    [kept addObject:blocks[0]];                 // 第 0 块是文件标题
    for (NSUInteger i = 1; i < blocks.count; i++) {
        if (![indexes containsIndex:i]) [kept addObject:blocks[i]];
    }
    NSString *output = [kept componentsJoinedByString:@"\n## "];

    NSError *writeError = nil;
    if (![output writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        if (error) *error = writeError;
        return NO;
    }
    return YES;
}

+ (NSArray<TNNoteEntry *> *)filterEntries:(NSArray<TNNoteEntry *> *)entries
                                    query:(NSString *)query {
    NSString *q = [query stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return entries;
    q = [q lowercaseString];
    NSMutableArray<TNNoteEntry *> *out = [NSMutableArray array];
    for (TNNoteEntry *entry in entries) {
        if ([entry.searchBlob containsString:q]) [out addObject:entry];
    }
    return out;
}

@end
