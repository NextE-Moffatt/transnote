//  TransNoteEngine.m

#import "TransNoteEngine.h"
#import <AppKit/AppKit.h>

NSString *const TNErrorDomain = @"TransNoteErrorDomain";

static NSString *const kMyMemoryURL = @"https://api.mymemory.translated.net/get";
static NSString *const kYoudaoURL   = @"https://aidemo.youdao.com/trans";
static NSString *const kYoudaoDictURL = @"https://dict.youdao.com/jsonapi";

#pragma mark - TNConfig

@implementation TNConfig

- (instancetype)init {
    if ((self = [super init])) {
        _engine = @"auto";
        _sourceLanguage = @"en";
        _targetLanguage = @"zh-CN";
        _autoDirection = YES;
        _notesPath = [TNEngine defaultNotesPath];
        _mymemoryEmail = @"";
        _copyToClipboard = YES;
        _chunkBytes = 450;
        _timeout = 25.0;
        _hotkeyTranslate = @"opt+cmd+T";
        _hotkeyAddNote = @"shift+opt+cmd+T";
        _dedupe = YES;
    }
    return self;
}

+ (NSString *)configPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@".transnote/config.json"];
}

+ (instancetype)load {
    TNConfig *cfg = [[TNConfig alloc] init];
    NSString *path = [self configPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    BOOL needsRewrite = NO;
    if (data) {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)json;
            // 老版本配置里没有的键补写回去，方便用户看到和修改。
            // 只在确实缺键时改写；JSON 解析失败则不动用户的文件。
            for (NSString *key in @[@"engine", @"sourceLanguage", @"targetLanguage", @"autoDirection",
                                    @"notesPath", @"mymemoryEmail", @"copyToClipboard",
                                    @"chunkBytes", @"timeoutSeconds",
                                    @"hotkeyTranslate", @"hotkeyAddNote", @"dedupe"]) {
                if (d[key] == nil) { needsRewrite = YES; break; }
            }
            if ([d[@"engine"] isKindOfClass:[NSString class]])           cfg.engine = d[@"engine"];
            if ([d[@"sourceLanguage"] isKindOfClass:[NSString class]])   cfg.sourceLanguage = d[@"sourceLanguage"];
            if ([d[@"targetLanguage"] isKindOfClass:[NSString class]])   cfg.targetLanguage = d[@"targetLanguage"];
            if ([d[@"notesPath"] isKindOfClass:[NSString class]])        cfg.notesPath = d[@"notesPath"];
            if ([d[@"hotkeyTranslate"] isKindOfClass:[NSString class]])  cfg.hotkeyTranslate = d[@"hotkeyTranslate"];
            if ([d[@"hotkeyAddNote"] isKindOfClass:[NSString class]])    cfg.hotkeyAddNote = d[@"hotkeyAddNote"];
            if (d[@"dedupe"] != nil)                                     cfg.dedupe = [d[@"dedupe"] boolValue];
            if ([d[@"mymemoryEmail"] isKindOfClass:[NSString class]])    cfg.mymemoryEmail = d[@"mymemoryEmail"];
            if (d[@"autoDirection"] != nil)                              cfg.autoDirection = [d[@"autoDirection"] boolValue];
            if (d[@"copyToClipboard"] != nil)                            cfg.copyToClipboard = [d[@"copyToClipboard"] boolValue];
            if (d[@"chunkBytes"] != nil)                                 cfg.chunkBytes = [d[@"chunkBytes"] integerValue];
            if (d[@"timeoutSeconds"] != nil)                             cfg.timeout = [d[@"timeoutSeconds"] doubleValue];
        }
    } else {
        needsRewrite = YES;
    }
    if (cfg.chunkBytes < 64)   cfg.chunkBytes = 450;
    if (cfg.timeout < 5)       cfg.timeout = 25.0;
    if (needsRewrite) [cfg save];
    return cfg;
}

- (void)save {
    NSString *path = [[self class] configPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    NSDictionary *d = @{
        @"engine":         self.engine ?: @"auto",
        @"sourceLanguage": self.sourceLanguage ?: @"en",
        @"targetLanguage": self.targetLanguage ?: @"zh-CN",
        @"autoDirection":  @(self.autoDirection),
        @"notesPath":      self.notesPath ?: [TNEngine defaultNotesPath],
        @"mymemoryEmail":  self.mymemoryEmail ?: @"",
        @"copyToClipboard": @(self.copyToClipboard),
        @"chunkBytes":     @(self.chunkBytes),
        @"timeoutSeconds": @(self.timeout),
        @"hotkeyTranslate": self.hotkeyTranslate ?: @"",
        @"hotkeyAddNote":   self.hotkeyAddNote ?: @"",
        @"dedupe":          @(self.dedupe),
    };
    NSData *out = [NSJSONSerialization dataWithJSONObject:d
                                                  options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                    error:NULL];
    [out writeToFile:path atomically:YES];
}

- (NSString *)expandedNotesPath {
    NSString *p = self.notesPath.length ? self.notesPath : [TNEngine defaultNotesPath];
    return [p stringByExpandingTildeInPath];
}

@end

#pragma mark - TNResult

@implementation TNResult
@end

#pragma mark - TNEngine

@implementation TNEngine

+ (NSString *)defaultNotesPath {
    return @"~/Documents/翻译笔记.md";
}

+ (void)copyToClipboard:(NSString *)text {
    if (!text.length) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
}

#pragma mark 文本切分

+ (NSInteger)byteLength:(NSString *)s {
    return (NSInteger)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

+ (NSArray<NSString *> *)splitText:(NSString *)text byPattern:(NSString *)pattern {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSUInteger loc = 0;
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        [out addObject:[text substringWithRange:NSMakeRange(loc, m.range.location - loc)]];
        loc = m.range.location + m.range.length;
    }
    [out addObject:[text substringFromIndex:loc]];
    return out;
}

+ (NSString *)hardCut:(NSString *)s limit:(NSInteger)limit {
    __block NSInteger total = 0;
    __block NSUInteger cut = 0;
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *sub, NSRange r, NSRange enclosing, BOOL *stop) {
        total += [TNEngine byteLength:sub];
        if (total > limit) { *stop = YES; return; }
        cut = r.location + r.length;
    }];
    return [s substringToIndex:cut];
}

+ (NSArray<NSString *> *)splitLong:(NSString *)text limit:(NSInteger)limit {
    if ([self byteLength:text] <= limit) return @[text];

    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSArray<NSString *> *parts = [self splitText:text byPattern:@"(?<=[.!?\u3002\uFF01\uFF1F\uFF1B;])\\s+"];
    NSMutableArray<NSString *> *chunks = [NSMutableArray array];
    NSString *current = @"";

    for (NSString *raw in parts) {
        NSString *part = raw;
        while ([self byteLength:part] > limit) {
            NSString *head = [self hardCut:part limit:limit];
            if (head.length == 0) break;
            if (current.length) { [chunks addObject:current]; current = @""; }
            [chunks addObject:head];
            part = [[part substringFromIndex:head.length] stringByTrimmingCharactersInSet:ws];
        }
        if (part.length == 0) continue;
        NSString *candidate = current.length ? [current stringByAppendingFormat:@" %@", part] : part;
        if ([self byteLength:candidate] > limit) {
            if (current.length) [chunks addObject:current];
            current = part;
        } else {
            current = candidate;
        }
    }
    if (current.length) [chunks addObject:current];
    return chunks;
}

+ (NSArray<NSString *> *)chunksForText:(NSString *)text limit:(NSInteger)limit {
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *chunks = [NSMutableArray array];
    for (NSString *para in [self splitText:text byPattern:@"\\n\\s*\\n"]) {
        NSString *p = [para stringByTrimmingCharactersInSet:ws];
        if (p.length) [chunks addObjectsFromArray:[self splitLong:p limit:limit]];
    }
    if (chunks.count == 0) {
        NSString *p = [text stringByTrimmingCharactersInSet:ws];
        if (p.length) [chunks addObject:p];
    }
    return chunks;
}

#pragma mark 网络

+ (NSData *)dataForRequest:(NSURLRequest *)request timeout:(NSTimeInterval)timeout error:(NSError **)error {
    NSURLSessionConfiguration *conf = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    conf.timeoutIntervalForRequest = timeout;
    conf.timeoutIntervalForResource = timeout + 5.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:conf];

    __block NSData *result = nil;
    __block NSError *inner = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *e) {
        result = data;
        inner = e;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 10.0) * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];

    if (!result && !inner) {
        inner = [NSError errorWithDomain:TNErrorDomain code:1
                               userInfo:@{NSLocalizedDescriptionKey: @"网络请求超时"}];
    }
    if (error) *error = inner;
    return result;
}

+ (NSString *)mymemoryChunk:(NSString *)chunk
                       from:(NSString *)src
                         to:(NSString *)tgt
                     config:(TNConfig *)config
                      error:(NSError **)error {
    NSURLComponents *comps = [NSURLComponents componentsWithString:kMyMemoryURL];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [items addObject:[NSURLQueryItem queryItemWithName:@"q" value:chunk]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"langpair"
                                                 value:[NSString stringWithFormat:@"%@|%@", src, tgt]]];
    if (config.mymemoryEmail.length) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"de" value:config.mymemoryEmail]];
    }
    comps.queryItems = items;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:comps.URL];
    req.HTTPMethod = @"GET";
    [req setValue:@"TransNote/1.0" forHTTPHeaderField:@"User-Agent"];

    NSData *data = [self dataForRequest:req timeout:config.timeout error:error];
    if (!data) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"没有收到响应"}];
        }
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:3
                                    userInfo:@{NSLocalizedDescriptionKey: @"接口返回的内容无法解析"}];
        }
        return nil;
    }

    NSDictionary *body = (NSDictionary *)json;
    NSString *status = [NSString stringWithFormat:@"%@", body[@"responseStatus"] ?: @""];
    if (![status isEqualToString:@"200"]) {
        id detail = body[@"responseDetails"];
        NSString *msg = [detail isKindOfClass:[NSString class]] && [detail length]
            ? detail : [NSString stringWithFormat:@"接口返回 %@", status];
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:4
                                    userInfo:@{NSLocalizedDescriptionKey: msg}];
        }
        return nil;
    }

    id responseData = body[@"responseData"];
    NSString *piece = nil;
    if ([responseData isKindOfClass:[NSDictionary class]]) {
        id t = ((NSDictionary *)responseData)[@"translatedText"];
        if ([t isKindOfClass:[NSString class]]) piece = t;
    }
    if (!piece) piece = @"";
    if ([[piece uppercaseString] containsString:@"MYMEMORY WARNING"]) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:5
                                    userInfo:@{NSLocalizedDescriptionKey:
                @"MyMemory 今日免费额度已用完。可在 ~/.transnote/config.json 里填入 mymemoryEmail 提升额度。"}];
        }
        return nil;
    }
    return [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)formEncode:(NSString *)text {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [text stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

+ (NSString *)youdaoLanguage:(NSString *)code {
    if ([code hasPrefix:@"zh"]) return @"zh-CHS";
    return code;
}

+ (NSString *)youdaoChunk:(NSString *)chunk
                     from:(NSString *)src
                       to:(NSString *)tgt
                   config:(TNConfig *)config
                    error:(NSError **)error {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kYoudaoURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"TransNote/1.0" forHTTPHeaderField:@"User-Agent"];
    NSString *body = [NSString stringWithFormat:@"q=%@&from=%@&to=%@",
                      [self formEncode:chunk],
                      [self formEncode:[self youdaoLanguage:src]],
                      [self formEncode:[self youdaoLanguage:tgt]]];
    req.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];

    NSData *data = [self dataForRequest:req timeout:config.timeout error:error];
    if (!data) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:20
                                    userInfo:@{NSLocalizedDescriptionKey: @"有道接口没有响应"}];
        }
        return nil;
    }

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:21
                                    userInfo:@{NSLocalizedDescriptionKey: @"有道接口返回的内容无法解析"}];
        }
        return nil;
    }
    NSDictionary *body2 = (NSDictionary *)json;
    NSString *code = [NSString stringWithFormat:@"%@", body2[@"errorCode"] ?: @""];
    if (![code isEqualToString:@"0"]) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:22
                                    userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"有道接口报错 (errorCode=%@)", code]}];
        }
        return nil;
    }
    NSArray *items = body2[@"translation"];
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:23
                                    userInfo:@{NSLocalizedDescriptionKey: @"有道接口没有返回译文"}];
        }
        return nil;
    }
    NSString *piece = [NSString stringWithFormat:@"%@", items[0]];
    return [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)translateChunk:(NSString *)chunk
                        from:(NSString *)src
                          to:(NSString *)tgt
                      engine:(NSString *)engine
                      config:(TNConfig *)config
                       error:(NSError **)error {
    if ([engine isEqualToString:@"youdao"]) {
        return [self youdaoChunk:chunk from:src to:tgt config:config error:error];
    }
    return [self mymemoryChunk:chunk from:src to:tgt config:config error:error];
}

+ (NSArray<NSString *> *)engineChainFor:(NSString *)engine {
    if ([engine isEqualToString:@"youdao"])   return @[@"youdao"];
    if ([engine isEqualToString:@"mymemory"]) return @[@"mymemory"];
    return @[@"youdao", @"mymemory"];   // auto
}

#pragma mark 词典（只有单个单词才用）

// 判断是不是「一个英文单词」：不含空格、不含数字和奇怪符号
+ (BOOL)looksLikeSingleWord:(NSString *)text {
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    t = [t stringByTrimmingCharactersInSet:
         [NSCharacterSet characterSetWithCharactersInString:@"\"'\u201C\u201D\u2018\u2019.,;:!?()[]{}"]];
    if (t.length == 0 || t.length > 32) return NO;

    NSInteger words = 0;
    BOOL inWord = NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        BOOL letter = ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                       c == '-' || c == '\'' || c == 0x2019);
        if (letter) {
            if (!inWord) { words++; inWord = YES; }
        } else if (c == ' ' || c == '\t') {
            inWord = NO;
        } else {
            return NO;   // 出现数字或别的符号，当句子处理
        }
    }
    return words == 1;
}

// 查词典，把音标和释义填进 result。查不到就静默跳过，不影响翻译。
+ (void)attachDictionaryTo:(TNResult *)result word:(NSString *)word config:(TNConfig *)config {
    NSURLComponents *comps = [NSURLComponents componentsWithString:kYoudaoDictURL];
    comps.queryItems = @[[NSURLQueryItem queryItemWithName:@"q" value:word]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:comps.URL];
    [req setValue:@"TransNote/1.0" forHTTPHeaderField:@"User-Agent"];

    NSData *data = [self dataForRequest:req timeout:config.timeout error:NULL];
    if (!data) return;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) return;

    id ec = ((NSDictionary *)json)[@"ec"];
    if (![ec isKindOfClass:[NSDictionary class]]) return;
    id wordList = ((NSDictionary *)ec)[@"word"];
    if (![wordList isKindOfClass:[NSArray class]] || [wordList count] == 0) return;
    id first = ((NSArray *)wordList)[0];
    if (![first isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *entry = (NSDictionary *)first;

    NSString *uk = [entry[@"ukphone"] isKindOfClass:[NSString class]] ? entry[@"ukphone"] : nil;
    NSString *us = [entry[@"usphone"] isKindOfClass:[NSString class]] ? entry[@"usphone"] : nil;
    if (uk.length && us.length && ![uk isEqualToString:us]) {
        result.phonetic = [NSString stringWithFormat:@"英 [%@]  美 [%@]", uk, us];
    } else if (us.length) {
        result.phonetic = [NSString stringWithFormat:@"[%@]", us];
    } else if (uk.length) {
        result.phonetic = [NSString stringWithFormat:@"[%@]", uk];
    }

    NSMutableArray<NSString *> *senses = [NSMutableArray array];
    id trs = entry[@"trs"];
    if ([trs isKindOfClass:[NSArray class]]) {
        for (id trsItem in (NSArray *)trs) {
            if (![trsItem isKindOfClass:[NSDictionary class]]) continue;
            id trList = ((NSDictionary *)trsItem)[@"tr"];
            if (![trList isKindOfClass:[NSArray class]]) continue;
            for (id trItem in (NSArray *)trList) {
                if (![trItem isKindOfClass:[NSDictionary class]]) continue;
                id l = ((NSDictionary *)trItem)[@"l"];
                if (![l isKindOfClass:[NSDictionary class]]) continue;
                id items = ((NSDictionary *)l)[@"i"];
                if (![items isKindOfClass:[NSArray class]]) continue;
                for (id one in (NSArray *)items) {
                    if ([one isKindOfClass:[NSString class]] && [one length]) {
                        [senses addObject:one];
                    }
                }
            }
        }
    }
    if (senses.count) result.definition = [senses componentsJoinedByString:@"\n"];
}

#pragma mark 翻译

+ (NSString *)labelFor:(NSString *)code {
    if ([code hasPrefix:@"zh"]) return @"中文";
    if ([code isEqualToString:@"en"]) return @"英文";
    return code;
}

+ (TNResult *)translate:(NSString *)text config:(TNConfig *)config error:(NSError **)error {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:6
                                    userInfo:@{NSLocalizedDescriptionKey: @"没有可以翻译的文本"}];
        }
        return nil;
    }
    NSArray<NSString *> *chain = [self engineChainFor:config.engine];
    if (chain.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:7
                                    userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"未知引擎：%@（可用：auto / youdao / mymemory）", config.engine]}];
        }
        return nil;
    }

    NSString *src = config.sourceLanguage;
    NSString *tgt = config.targetLanguage;

    if (config.autoDirection) {
        NSUInteger cjk = 0, letters = 0;
        for (NSUInteger i = 0; i < trimmed.length; i++) {
            unichar c = [trimmed characterAtIndex:i];
            if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF) ||
                (c >= 0xF900 && c <= 0xFAFF)) {
                cjk++;
            } else if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
                letters++;
            }
        }
        if (cjk > letters) {
            NSString *swap = src; src = tgt; tgt = swap;
        }
    }

    NSArray<NSString *> *chunks = [self chunksForText:trimmed limit:config.chunkBytes];
    NSString *translation = nil;
    NSString *usedEngine = nil;
    NSError *lastError = nil;

    // 依次尝试引擎链；只有整段文本全部成功采用它。
    for (NSString *engine in chain) {
        NSMutableArray<NSString *> *pieces = [NSMutableArray array];
        BOOL ok = YES;
        for (NSString *chunk in chunks) {
            NSError *chunkError = nil;
            NSString *piece = [self translateChunk:chunk from:src to:tgt
                                            engine:engine config:config error:&chunkError];
            if (!piece) {
                ok = NO;
                lastError = chunkError;
                break;
            }
            if (piece.length) [pieces addObject:piece];
        }
        if (ok && pieces.count) {
            translation = [pieces componentsJoinedByString:@"\n"];
            usedEngine = engine;
            break;
        }
    }

    if (!translation) {
        if (error) {
            *error = lastError ?: [NSError errorWithDomain:TNErrorDomain code:8
                                    userInfo:@{NSLocalizedDescriptionKey: @"没有拿到译文"}];
        }
        return nil;
    }

    TNResult *r = [[TNResult alloc] init];
    r.sourceLabel = [self labelFor:src];
    r.targetLabel = [self labelFor:tgt];
    r.translation = translation;
    r.engineUsed = usedEngine;
    r.isWord = [self looksLikeSingleWord:trimmed];

    // 单个单词额外查一次词典，补上音标和多义项（查不到就跳过）
    if (r.isWord) {
        NSString *bare = [trimmed stringByTrimmingCharactersInSet:
                          [NSCharacterSet characterSetWithCharactersInString:@"\"'\u201C\u201D\u2018\u2019"]];
        [self attachDictionaryTo:r word:bare config:config];
    }

    r.title = [NSString stringWithFormat:@"%@ → %@", r.sourceLabel, r.targetLabel];
    return r;
}

#pragma mark 笔记

+ (NSString *)quoteBlock:(NSString *)text {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [lines addObject:trimmed.length ? [@"> " stringByAppendingString:line]
                                        : @">"];
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (BOOL)appendNote:(TNResult *)result
            source:(NSString *)source
            config:(TNConfig *)config
             error:(NSError **)error {
    NSString *path = [config expandedNotesPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (dir.length) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm";
    NSString *stamp = [df stringFromDate:[NSDate date]];

    BOOL fresh = ![fm fileExistsAtPath:path];
    NSMutableString *entry = [NSMutableString string];
    if (fresh) [entry appendString:@"# 翻译笔记\n"];
    [entry appendFormat:@"\n## %@\n", stamp];
    [entry appendFormat:@"\n**原文（%@）**\n\n%@\n", result.sourceLabel, [self quoteBlock:source]];
    // 音标和词典释义是可选段落：只有单词且查到词典时才写；老记录没有这两段也能解析
    if (result.phonetic.length) {
        [entry appendFormat:@"\n**音标**\n\n> %@\n", result.phonetic];
    }
    if (result.definition.length) {
        [entry appendFormat:@"\n**词典释义**\n\n%@\n", [self quoteBlock:result.definition]];
    }
    [entry appendFormat:@"\n**译文（%@）**\n\n%@\n", result.targetLabel, [self quoteBlock:result.translation]];
    [entry appendString:@"\n---\n"];

    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    if (![fm fileExistsAtPath:path]) {
        return [data writeToFile:path atomically:YES];
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:9
                                    userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"无法写入 %@", path]}];
        }
        return NO;
    }
    @try {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
        return YES;
    } @catch (NSException *e) {
        if (error) {
            *error = [NSError errorWithDomain:TNErrorDomain code:10
                                    userInfo:@{NSLocalizedDescriptionKey: e.reason ?: @"写入失败"}];
        }
        return NO;
    }
}

@end
