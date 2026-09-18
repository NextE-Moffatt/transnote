//  TNNotes.h — 解析「翻译笔记.md」里记录的生词

#import <Foundation/Foundation.h>

@interface TNNoteEntry : NSObject
@property (nonatomic, copy) NSString *date;          // 2026-09-18 13:49
@property (nonatomic, copy) NSString *source;        // 原文
@property (nonatomic, copy) NSString *translation;   // 译文
@property (nonatomic, copy) NSString *sourceLabel;   // 英文
@property (nonatomic, copy) NSString *targetLabel;   // 中文
@property (nonatomic, copy) NSString *phonetic;      // 音标（可选段落）
@property (nonatomic, copy) NSString *definition;    // 词典释义（可选段落）
@property (nonatomic, copy) NSString *searchBlob;    // 预拼的搜索用小写串
@property (nonatomic, assign) NSInteger blockIndex;   // 在笔记文件里的块序号（从 1 开始）
@end

@interface TNNotes : NSObject
+ (NSArray<TNNoteEntry *> *)entriesAtPath:(NSString *)path;
+ (NSArray<TNNoteEntry *> *)filterEntries:(NSArray<TNNoteEntry *> *)entries
                                    query:(NSString *)query;
// 归一化用于判重：忽略大小写、首尾空白和引号/标点
+ (NSString *)normalizeKey:(NSString *)text;
// 找已有的同词条目（用于去重）
+ (TNNoteEntry *)findEntryForSource:(NSString *)source inPath:(NSString *)path;
// 按块序号删除（同时把原文件备份到 backupPath，可为 nil）
// 导出成 CSV（供 Anki / Excel 导入）
+ (NSData *)csvDataForEntries:(NSArray<TNNoteEntry *> *)entries;
+ (BOOL)removeEntriesAtIndexes:(NSIndexSet *)indexes
                      fromPath:(NSString *)path
                    backupPath:(NSString *)backupPath
                         error:(NSError **)error;
@end
