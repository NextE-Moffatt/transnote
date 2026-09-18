//  TNHotKeys.h — 全局快捷键（Carbon RegisterEventHotKey，无需辅助功能权限）

#import <Foundation/Foundation.h>

@interface TNHotKey : NSObject
// 解析 "opt+cmd+T" 这类描述，返回 Carbon 键码和修饰键
+ (BOOL)parseSpec:(NSString *)spec keyCode:(unsigned int *)keyCode modifiers:(unsigned int *)modifiers;
// 规范化成可显示的写法，例如 "⌥⌘T"
+ (NSString *)displaySpec:(NSString *)spec;
@end

@interface TNHotKeyCenter : NSObject
- (BOOL)registerSpec:(NSString *)spec identifier:(unsigned int)identifier handler:(void (^)(void))handler;
- (void)unregisterAll;
@end
