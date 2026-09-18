//  TNSelection.h — 读取「当前选中的文字」
//
//  两种手段：
//    1) 辅助功能 API，直接问焦点元素要选区（最准）
//    2) 模拟 ⌘C 把选区复制到剪贴板（更通用，很多 App 不实现 AXSelectedText）
//  两者都需要「辅助功能」授权；没授权时只能退回读剪贴板。

#import <Foundation/Foundation.h>

@interface TNSelection : NSObject
+ (BOOL)isTrusted;
+ (void)requestTrust;                         // 弹系统授权对话框
+ (NSString *)selectedTextViaAccessibility;   // 失败返回 nil
+ (NSString *)selectedTextViaCopy;            // 失败返回 nil
+ (NSString *)focusedElementDescription;      // 诊断：焦点元素是谁、选中多少字
@end
