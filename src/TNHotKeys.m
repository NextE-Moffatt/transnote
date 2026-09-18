//  TNHotKeys.m

#import "TNHotKeys.h"
#import <Carbon/Carbon.h>

static NSMutableDictionary<NSNumber *, void (^)(void)> *gHotKeyHandlers = nil;
static EventHandlerRef gHotKeyHandlerRef = NULL;

static OSStatus TNHotKeyEventHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotKeyID;
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                                        NULL, sizeof(hotKeyID), NULL, &hotKeyID);
    if (status == noErr) {
        void (^handler)(void) = gHotKeyHandlers[@(hotKeyID.id)];
        if (handler) handler();
    }
    return noErr;
}

typedef struct {
    const char *name;
    unsigned int code;
} TNKeyEntry;

static const TNKeyEntry kKeyTable[] = {
    {"a", kVK_ANSI_A}, {"b", kVK_ANSI_B}, {"c", kVK_ANSI_C}, {"d", kVK_ANSI_D},
    {"e", kVK_ANSI_E}, {"f", kVK_ANSI_F}, {"g", kVK_ANSI_G}, {"h", kVK_ANSI_H},
    {"i", kVK_ANSI_I}, {"j", kVK_ANSI_J}, {"k", kVK_ANSI_K}, {"l", kVK_ANSI_L},
    {"m", kVK_ANSI_M}, {"n", kVK_ANSI_N}, {"o", kVK_ANSI_O}, {"p", kVK_ANSI_P},
    {"q", kVK_ANSI_Q}, {"r", kVK_ANSI_R}, {"s", kVK_ANSI_S}, {"t", kVK_ANSI_T},
    {"u", kVK_ANSI_U}, {"v", kVK_ANSI_V}, {"w", kVK_ANSI_W}, {"x", kVK_ANSI_X},
    {"y", kVK_ANSI_Y}, {"z", kVK_ANSI_Z},
    {"0", kVK_ANSI_0}, {"1", kVK_ANSI_1}, {"2", kVK_ANSI_2}, {"3", kVK_ANSI_3},
    {"4", kVK_ANSI_4}, {"5", kVK_ANSI_5}, {"6", kVK_ANSI_6}, {"7", kVK_ANSI_7},
    {"8", kVK_ANSI_8}, {"9", kVK_ANSI_9},
    {"return", kVK_Return}, {"enter", kVK_Return}, {"space", kVK_Space},
    {"tab", kVK_Tab}, {"escape", kVK_Escape}, {"esc", kVK_Escape},
    {"comma", kVK_ANSI_Comma}, {"period", kVK_ANSI_Period}, {"slash", kVK_ANSI_Slash},
    {"semicolon", kVK_ANSI_Semicolon}, {"minus", kVK_ANSI_Minus}, {"equal", kVK_ANSI_Equal},
    {NULL, 0},
};

@implementation TNHotKey

+ (BOOL)parseSpec:(NSString *)spec keyCode:(unsigned int *)keyCode modifiers:(unsigned int *)modifiers {
    if (!spec.length) return NO;
    NSArray<NSString *> *tokens = [[spec lowercaseString] componentsSeparatedByString:@"+"];
    unsigned int mods = 0;
    NSString *keyToken = nil;

    for (NSString *raw in tokens) {
        NSString *t = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!t.length) continue;
        if ([t isEqualToString:@"cmd"] || [t isEqualToString:@"command"] || [t isEqualToString:@"\u2318"]) {
            mods |= cmdKey;
        } else if ([t isEqualToString:@"opt"] || [t isEqualToString:@"option"] ||
                   [t isEqualToString:@"alt"] || [t isEqualToString:@"\u2325"]) {
            mods |= optionKey;
        } else if ([t isEqualToString:@"ctrl"] || [t isEqualToString:@"control"] ||
                   [t isEqualToString:@"\u2303"]) {
            mods |= controlKey;
        } else if ([t isEqualToString:@"shift"] || [t isEqualToString:@"\u21e7"]) {
            mods |= shiftKey;
        } else {
            keyToken = t;
        }
    }

    if (!keyToken.length || mods == 0) return NO;

    for (int i = 0; kKeyTable[i].name != NULL; i++) {
        if ([keyToken isEqualToString:[NSString stringWithUTF8String:kKeyTable[i].name]]) {
            if (keyCode) *keyCode = kKeyTable[i].code;
            if (modifiers) *modifiers = mods;
            return YES;
        }
    }
    return NO;
}

+ (NSString *)displaySpec:(NSString *)spec {
    unsigned int keyCode = 0, mods = 0;
    if (![self parseSpec:spec keyCode:&keyCode modifiers:&mods]) return spec ?: @"";
    NSMutableString *out = [NSMutableString string];
    if (mods & controlKey) [out appendString:@"\u2303"];
    if (mods & optionKey)  [out appendString:@"\u2325"];
    if (mods & shiftKey)   [out appendString:@"\u21e7"];
    if (mods & cmdKey)     [out appendString:@"\u2318"];
    NSString *name = @"?";
    for (int i = 0; kKeyTable[i].name != NULL; i++) {
        if (kKeyTable[i].code == keyCode && strlen(kKeyTable[i].name) <= 2) {
            name = [[NSString stringWithUTF8String:kKeyTable[i].name] uppercaseString];
            break;
        }
    }
    [out appendString:name];
    return out;
}

@end

@implementation TNHotKeyCenter

- (BOOL)registerSpec:(NSString *)spec identifier:(unsigned int)identifier handler:(void (^)(void))handler {
    unsigned int keyCode = 0, mods = 0;
    if (![TNHotKey parseSpec:spec keyCode:&keyCode modifiers:&mods]) return NO;

    if (!gHotKeyHandlers) gHotKeyHandlers = [NSMutableDictionary dictionary];
    if (!gHotKeyHandlerRef) {
        EventTypeSpec eventType = { kEventClassKeyboard, kEventHotKeyPressed };
        InstallApplicationEventHandler(&TNHotKeyEventHandler, 1, &eventType, NULL, &gHotKeyHandlerRef);
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'TrNt';
    hotKeyID.id = identifier;

    EventHotKeyRef ref = NULL;
    OSStatus status = RegisterEventHotKey(keyCode, mods, hotKeyID,
                                          GetApplicationEventTarget(), 0, &ref);
    if (status != noErr) return NO;

    gHotKeyHandlers[@(identifier)] = [handler copy];
    return YES;
}

- (void)unregisterAll {
    [gHotKeyHandlers removeAllObjects];
}

@end
