//  TransNoteEngine.h
//  翻译 + 笔记写入，纯 Foundation / NSURLSession 实现。

#import <Foundation/Foundation.h>

extern NSString *const TNErrorDomain;

@interface TNConfig : NSObject
@property (nonatomic, copy)   NSString *engine;
@property (nonatomic, copy)   NSString *sourceLanguage;
@property (nonatomic, copy)   NSString *targetLanguage;
@property (nonatomic, assign) BOOL      autoDirection;
@property (nonatomic, copy)   NSString *notesPath;
@property (nonatomic, copy)   NSString *mymemoryEmail;
@property (nonatomic, assign) BOOL      copyToClipboard;
@property (nonatomic, assign) NSInteger chunkBytes;
@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, copy)   NSString *hotkeyTranslate;   // 例如 opt+cmd+T
@property (nonatomic, copy)   NSString *hotkeyAddNote;     // 例如 shift+opt+cmd+T
@property (nonatomic, assign) BOOL dedupe;                 // 同一个词已记过就不重复记

+ (instancetype)load;
+ (NSString *)configPath;
- (NSString *)expandedNotesPath;
- (void)save;
@end

@interface TNResult : NSObject
@property (nonatomic, copy) NSString *sourceLabel;
@property (nonatomic, copy) NSString *targetLabel;
@property (nonatomic, copy) NSString *translation;
@property (nonatomic, copy) NSString *title;      // 例如 英文 → 中文
@property (nonatomic, copy) NSString *engineUsed; // 实际生效的引擎
@property (nonatomic, copy) NSString *phonetic;    // 音标（只有单词才有）
@property (nonatomic, copy) NSString *definition;  // 词典释义（只有单词才有）
@property (nonatomic, assign) BOOL isWord;         // 是否按「单词」处理
@end

@interface TNEngine : NSObject
+ (TNResult *)translate:(NSString *)text config:(TNConfig *)config error:(NSError **)error;
+ (BOOL)appendNote:(TNResult *)result
            source:(NSString *)source
            config:(TNConfig *)config
             error:(NSError **)error;
+ (NSArray<NSString *> *)chunksForText:(NSString *)text limit:(NSInteger)limit;
+ (BOOL)looksLikeSingleWord:(NSString *)text;
+ (NSString *)defaultNotesPath;
+ (void)copyToClipboard:(NSString *)text;
@end
