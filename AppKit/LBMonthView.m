#import "LBMonthView.h"
#import "LBCalendar.h"

static const CGFloat LBHeaderHeight = 20;
static const CGFloat LBLineHeight = 14;
static const NSInteger LBWeeks = 6;

static NSCalendar *LBUTC(void) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    calendar.firstWeekday = [NSCalendar currentCalendar].firstWeekday;
    return calendar;
}

static NSDate *LBDayAfter(NSDate *day, NSInteger days) {
    NSDateComponents *by = [[NSDateComponents alloc] init];
    by.day = days;
    return [LBUTC() dateByAddingComponents:by toDate:day options:0];
}

static NSColor *LBColorOf(LBCalendarKind kind) {
    switch (kind) {
    case LBCalendarDone: return [NSColor colorWithCalibratedRed:0.20 green:0.60 blue:0.30 alpha:1];
    case LBCalendarCancelled: return [NSColor colorWithCalibratedWhite:0.55 alpha:1];
    case LBCalendarOpen: return [NSColor colorWithCalibratedRed:0.15 green:0.40 blue:0.85 alpha:1];
    case LBCalendarOverdue: return [NSColor colorWithCalibratedRed:0.85 green:0.20 blue:0.20 alpha:1];
    case LBCalendarPlanned: return [NSColor colorWithCalibratedRed:0.45 green:0.65 blue:0.95 alpha:1];
    case LBCalendarRecord: return [NSColor textColor];
    }
    return [NSColor textColor];
}

@implementation LBMonthView

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self setUp];
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    if (!_month) [self setUp];
}

- (void)setUp {
    NSCalendar *utc = LBUTC();
    NSDateComponents *now = [utc components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:[NSDate date]];
    _month = [utc dateFromComponents:now];
    _entries = @[];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setMonth:(NSDate *)month {
    _month = [month copy];
    [self setNeedsDisplay:YES];
}

- (void)setEntries:(NSArray<LBCalendarEntry *> *)entries {
    _entries = [entries copy];
    [self setNeedsDisplay:YES];
}

- (void)setShowsVehicles:(BOOL)showsVehicles {
    _showsVehicles = showsVehicles;
    [self setNeedsDisplay:YES];
}

- (void)setChosenDay:(NSDate *)chosenDay {
    _chosenDay = [chosenDay copy];
    [self setNeedsDisplay:YES];
}

- (NSDate *)firstDay {
    NSCalendar *utc = LBUTC();
    NSInteger weekday = [utc component:NSCalendarUnitWeekday fromDate:_month];
    NSInteger back = (weekday - utc.firstWeekday + 7) % 7;
    return LBDayAfter(_month, -back);
}

- (NSDate *)endDay {
    return LBDayAfter(self.firstDay, LBWeeks * 7);
}

- (NSRect)cellOfIndex:(NSInteger)index {
    NSRect bounds = self.bounds;
    CGFloat width = floor(bounds.size.width / 7);
    CGFloat height = floor((bounds.size.height - LBHeaderHeight) / LBWeeks);
    return NSMakeRect((index % 7) * width, LBHeaderHeight + (index / 7) * height, width, height);
}

- (NSDate *)dayAtPoint:(NSPoint)point {
    for (NSInteger i = 0; i < LBWeeks * 7; i++) {
        if (NSPointInRect(point, [self cellOfIndex:i])) return LBDayAfter(self.firstDay, i);
    }
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    NSDate *day = [self dayAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    self.chosenDay = [day isEqualToDate:_chosenDay] ? nil : day;
    if (_action) [NSApp sendAction:_action to:_target from:self];
}

- (void)drawRect:(NSRect)dirty {
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(self.bounds);
    NSCalendar *utc = LBUTC();
    NSDictionary *small = @{ NSFontAttributeName: [NSFont systemFontOfSize:10], NSForegroundColorAttributeName: [NSColor textColor] };
    NSDictionary *dim = @{ NSFontAttributeName: [NSFont systemFontOfSize:10], NSForegroundColorAttributeName: [NSColor disabledControlTextColor] };

    /* The weekdays' names, the calendar's first first. */
    NSArray<NSString *> *names = [[NSDateFormatter alloc] init].shortWeekdaySymbols;
    for (NSInteger column = 0; column < 7; column++) {
        NSString *name = names[(NSUInteger)((utc.firstWeekday - 1 + column) % 7)];
        NSRect cell = [self cellOfIndex:column];
        [name drawAtPoint:NSMakePoint(NSMinX(cell) + 4, 3) withAttributes:small];
    }

    NSDate *first = self.firstDay;
    NSInteger month = [utc component:NSCalendarUnitMonth fromDate:_month];
    NSMutableDictionary<NSDate *, NSMutableArray<LBCalendarEntry *> *> *byDay = [NSMutableDictionary dictionary];
    for (LBCalendarEntry *entry in _entries) {
        NSMutableArray *those = byDay[entry.day];
        if (!those) byDay[entry.day] = those = [NSMutableArray array];
        [those addObject:entry];
    }
    for (NSInteger i = 0; i < LBWeeks * 7; i++) {
        NSDate *day = LBDayAfter(first, i);
        NSRect cell = [self cellOfIndex:i];
        if ([day isEqualToDate:_chosenDay]) {
            [[NSColor selectedTextBackgroundColor] setFill];
            NSRectFill(cell);
        }
        [[NSColor gridColor] setStroke];
        [NSBezierPath strokeRect:NSInsetRect(cell, 0.5, 0.5)];
        BOOL inMonth = [utc component:NSCalendarUnitMonth fromDate:day] == month;
        NSString *number = [NSString stringWithFormat:@"%ld", (long)[utc component:NSCalendarUnitDay fromDate:day]];
        NSMutableDictionary *numbered = [(inMonth ? small : dim) mutableCopy];
        if ([day isEqualToDate:_today]) numbered[NSFontAttributeName] = [NSFont boldSystemFontOfSize:10];
        [number drawAtPoint:NSMakePoint(NSMinX(cell) + 4, NSMinY(cell) + 2) withAttributes:numbered];

        NSArray<LBCalendarEntry *> *those = byDay[day];
        NSInteger room = (NSInteger)floor((NSHeight(cell) - 16) / LBLineHeight);
        for (NSInteger line = 0; line < (NSInteger)those.count && line < room; line++) {
            LBCalendarEntry *entry = those[(NSUInteger)line];
            BOOL last = line == room - 1 && (NSInteger)those.count > room;
            NSString *title = _showsVehicles ? [NSString stringWithFormat:@"%@: %@", entry.vehicleTitle, entry.title] : entry.title;
            NSString *text = last ? [NSString stringWithFormat:@"+%ld more", (long)(those.count - (NSUInteger)line)] : title;
            NSFont *font = entry.estimated ? [[NSFontManager sharedFontManager] convertFont:[NSFont systemFontOfSize:10]
                                                                                toHaveTrait:NSItalicFontMask]
                                           : [NSFont systemFontOfSize:10];
            NSRect row = NSMakeRect(NSMinX(cell) + 4, NSMinY(cell) + 16 + line * LBLineHeight, NSWidth(cell) - 8, LBLineHeight);
            if (!last) {
                [LBColorOf(entry.kind) setFill];
                NSRectFill(NSMakeRect(NSMinX(row), NSMinY(row) + 4, 5, 5));
            }
            [text drawInRect:NSMakeRect(NSMinX(row) + (last ? 0 : 8), NSMinY(row), NSWidth(row) - 8, LBLineHeight)
              withAttributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: last ? [NSColor disabledControlTextColor]
                                                                                                : LBColorOf(entry.kind) }];
        }
    }
}

@end
