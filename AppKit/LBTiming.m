#import "LBTiming.h"
#include <stdlib.h>
#include <stdio.h>

BOOL LBTimingOn(void) {
    static int on = -1;
    if (on < 0) {
        const char *value = getenv("LB_TIMING");
        on = value && *value && strcmp(value, "0") != 0;
    }
    return on;
}

static NSString *LBTimeOfDay(void) {
    static NSDateFormatter *format;
    if (!format) {
        format = [[NSDateFormatter alloc] init];
        format.dateFormat = @"HH:mm:ss.SSS";
    }
    return [format stringFromDate:[NSDate date]];
}

void LBTimingNote(NSString *format, ...) {
    if (!LBTimingOn()) return;
    va_list arguments;
    va_start(arguments, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    fprintf(stderr, "TIMING %s %s\n", LBTimeOfDay().UTF8String, text.UTF8String);
    fflush(stderr);
}

void LBTimed(NSString *what, void (^work)(void)) {
    if (!LBTimingOn()) {
        work();
        return;
    }
    NSDate *start = [NSDate date];
    work();
    LBTimingNote(@"%@ %.1f ms", what, -[start timeIntervalSinceNow] * 1000);
}
