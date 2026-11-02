// Rex builds terminal input from an event's keycode. Some input methods
// post keycode 0 with the real text attached, so Rex types "a" instead. Deliver the
// attached text when it differs from what the keycode would produce.
#import <AppKit/AppKit.h>

static BOOL debugEnabled;

static void debugLog(NSEvent *event, NSString *expected, id responder) {
    if (!debugEnabled) return;
    NSString *path = [@"~/Library/Application Support/rexmod-vntyping/debug.log" stringByExpandingTildeInPath];
    NSString *line = [NSString stringWithFormat:@"key=%hu chars=%@ expected=%@ source=%lld responder=%@ insertText=%d\n",
        event.keyCode, event.characters, expected,
        CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceStateID),
        NSStringFromClass([responder class]),
        [responder respondsToSelector:@selector(insertText:replacementRange:)]];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!file) {
        [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [file seekToEndOfFile];
    [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [file closeFile];
}

static BOOL hasFunctionKey(NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= 0xF700 && c <= 0xF8FF) return YES;
    }
    return NO;
}

static NSEvent *handleKeyDown(NSEvent *event) {
    // Physical keys stay on Rex's normal path. Input methods post their backspaces
    // here too, which keeps them ordered with the text that follows.
    if (CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceStateID) == kCGEventSourceStateHIDSystemState) return event;
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) return event;
    NSString *text = event.characters;
    if (text.length == 0 || hasFunctionKey(text)) return event;
    NSString *expected = [event charactersByApplyingModifiers:event.modifierFlags];
    if ([text isEqualToString:expected]) return event;

    id responder = NSApp.keyWindow.firstResponder;
    debugLog(event, expected, responder);
    if ([responder isKindOfClass:[NSTextView class]]) return event;
    if (![responder respondsToSelector:@selector(insertText:replacementRange:)]) return event;
    if ([responder respondsToSelector:@selector(hasMarkedText)] && [responder hasMarkedText]) return event;
    [responder insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
    return nil;
}

__attribute__((constructor)) static void install(void) {
    NSString *flag = [@"~/Library/Application Support/rexmod-vntyping/debug" stringByExpandingTildeInPath];
    debugEnabled = [NSFileManager.defaultManager fileExistsAtPath:flag];
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification
                                                    object:nil queue:nil usingBlock:^(NSNotification *note) {
        [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
            return handleKeyDown(event);
        }];
    }];
}
