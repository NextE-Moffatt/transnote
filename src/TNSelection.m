//  TNSelection.m

#import "TNSelection.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <unistd.h>

@implementation TNSelection

+ (BOOL)isTrusted {
    return AXIsProcessTrusted() ? YES : NO;
}

+ (void)requestTrust {
    NSDictionary *options = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @YES };
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

+ (NSString *)selectedTextViaAccessibility {
    if (!AXIsProcessTrusted()) return nil;

    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    if (!systemWide) return nil;

    CFTypeRef focused = NULL;
    NSString *result = nil;

    if (AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess
        && focused) {
        CFTypeRef value = NULL;
        if (AXUIElementCopyAttributeValue((AXUIElementRef)focused, kAXSelectedTextAttribute, &value) == kAXErrorSuccess
            && value) {
            if (CFGetTypeID(value) == CFStringGetTypeID()) {
                NSString *text = (__bridge NSString *)value;
                if (text.length > 0) result = [NSString stringWithString:text];
            }
            CFRelease(value);
        }
        CFRelease(focused);
    }
    CFRelease(systemWide);
    return result;
}

+ (NSString *)focusedElementDescription {
    NSMutableString *out = [NSMutableString string];
    AXUIElementRef systemWide = AXUIElementCreateSystemWide();
    CFTypeRef focused = NULL;
    if (systemWide &&
        AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, &focused) == kAXErrorSuccess &&
        focused) {
        pid_t pid = 0;
        AXUIElementGetPid((AXUIElementRef)focused, &pid);
        CFTypeRef role = NULL, sel = NULL;
        AXUIElementCopyAttributeValue((AXUIElementRef)focused, kAXRoleAttribute, &role);
        AXUIElementCopyAttributeValue((AXUIElementRef)focused, kAXSelectedTextAttribute, &sel);
        NSUInteger selLength = 0;
        if (sel && CFGetTypeID(sel) == CFStringGetTypeID()) selLength = [(__bridge NSString *)sel length];
        NSRunningApplication *owner = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        [out appendFormat:@"role=%@ pid=%d(%@)%@ 选中=%lu字",
         role ? (__bridge NSString *)role : @"?",
         pid,
         owner.localizedName ?: @"?",
         (pid == getpid() ? @"(自己!)" : @""),
         (unsigned long)selLength];
        if (role) CFRelease(role);
        if (sel) CFRelease(sel);
        CFRelease(focused);
    } else {
        [out appendString:@"拿不到焦点元素"];
    }
    if (systemWide) CFRelease(systemWide);
    return out;
}

+ (NSString *)selectedTextViaCopy {
    // 用户此刻物理上还按着 ⌥⌘，先等松开，否则合成的 ⌘C 会被带上多余修饰键。
    CGEventFlags stuck = kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate | kCGEventFlagMaskControl;
    NSDate *releaseDeadline = [NSDate dateWithTimeIntervalSinceNow:0.6];
    while ((CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & stuck) != 0 &&
           [releaseDeadline timeIntervalSinceNow] > 0) {
        usleep(8000);
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSInteger before = pasteboard.changeCount;

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    if (!source) return nil;

    CGEventRef down = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_ANSI_C, true);
    CGEventSetFlags(down, kCGEventFlagMaskCommand);
    CGEventRef up = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_ANSI_C, false);
    CGEventSetFlags(up, kCGEventFlagMaskCommand);

    CGEventPost(kCGHIDEventTap, down);
    usleep(25000);
    CGEventPost(kCGHIDEventTap, up);

    CFRelease(down);
    CFRelease(up);
    CFRelease(source);

    // 等剪贴板真正更新（最多 0.5 秒）
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ([deadline timeIntervalSinceNow] > 0) {
        if (pasteboard.changeCount != before) break;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }

    if (pasteboard.changeCount == before) return nil;   // 没有选区，剪贴板没动
    return [pasteboard stringForType:NSPasteboardTypeString];
}

@end
