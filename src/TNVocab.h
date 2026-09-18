//  TNVocab.h — 生词本窗口

#import <Cocoa/Cocoa.h>
#import "TNNotes.h"

@class AVSpeechSynthesizer;

@interface TNVocabWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, copy) NSString *notesPath;
@property (nonatomic, strong) NSArray<TNNoteEntry *> *entries;
@property (nonatomic, strong) NSArray<TNNoteEntry *> *filtered;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *sourceClipButton;
@property (nonatomic, strong) NSButton *translationClipButton;
@property (nonatomic, strong) NSButton *speakButton;
@property (nonatomic, strong) AVSpeechSynthesizer *speaker;
@property (nonatomic, strong) NSPopUpButton *timePopup;     // 时间范围预设
@property (nonatomic, strong) NSDatePicker *startPicker;    // 自定义起始日
@property (nonatomic, strong) NSDatePicker *endPicker;      // 自定义结束日
@property (nonatomic, strong) NSButton *resetOrderButton;   // 恢复记录顺序
@property (nonatomic, strong) NSButton *deleteButton;       // 删除选中记录
@property (nonatomic, assign) BOOL recordReversed;          // 记录顺序是否倒过来
@property (nonatomic, strong) NSButton *exportButton;       // 导出当前显示的内容

- (instancetype)initWithNotesPath:(NSString *)path;
- (void)reload;
- (void)reloadAndShow;
- (void)setSearchQuery:(NSString *)query;
- (void)setSortKey:(NSString *)key ascending:(BOOL)ascending;
- (void)setTimeFilterIndex:(NSInteger)index;
- (void)toggleRecordOrder:(id)sender;

@end
