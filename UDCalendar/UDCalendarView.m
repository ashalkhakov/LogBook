#import "UDCalendarView.h"

static const CGFloat UDMonthHeader = 20;
static const CGFloat UDLineHeight = 14;
static const NSInteger UDWeeks = 6;
static const CGFloat UDDaysHeader = 34;
static const CGFloat UDHourGutter = 60;

static BOOL UDAllDay(id<UDCalendarItem> item) {
    return [item respondsToSelector:@selector(calendarAllDay)] && item.calendarAllDay;
}

static BOOL UDTentative(id<UDCalendarItem> item) {
    return [item respondsToSelector:@selector(calendarTentative)] && item.calendarTentative;
}

static NSString *UDDetail(id<UDCalendarItem> item) {
    return [item respondsToSelector:@selector(calendarDetail)] ? item.calendarDetail : nil;
}

static NSFont *UDFont(BOOL tentative, BOOL bold) {
    NSFont *font = bold ? [NSFont boldSystemFontOfSize:10] : [NSFont systemFontOfSize:10];
    return tentative ? [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask] : font;
}

/* All-day items first, then by when. */
static NSInteger UDItemOrder(id a, id b, void *context) {
    BOOL allDayA = UDAllDay(a);
    BOOL allDayB = UDAllDay(b);
    if (allDayA != allDayB) return allDayA ? NSOrderedAscending : NSOrderedDescending;
    return [[(id<UDCalendarItem>)a calendarDate] compare:[(id<UDCalendarItem>)b calendarDate]];
}

@implementation UDCalendarView {
    NSArray<id<UDCalendarItem>> *_items;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self setUp];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) [self setUp];
    return self;
}

- (void)setUp {
    _calendar = [[NSCalendar currentCalendar] copy];
    _allDayTimeZone = _calendar.timeZone;
    _mode = UDCalendarModeMonth;
    _date = [_calendar startOfDayForDate:[NSDate date]];
    _firstHour = 7;
    _lastHour = 22;
    _items = @[];
}

- (BOOL)isFlipped {
    return YES;
}

#pragma mark What is shown

- (void)setMode:(UDCalendarMode)mode {
    _mode = mode;
    [self rangeChanged];
}

- (void)setDate:(NSDate *)date {
    _date = [[_calendar startOfDayForDate:date] copy];
    [self rangeChanged];
}

- (void)setCalendar:(NSCalendar *)calendar {
    _calendar = [calendar copy];
    _date = [_calendar startOfDayForDate:_date];
    [self rangeChanged];
}

- (void)setAllDayTimeZone:(NSTimeZone *)allDayTimeZone {
    _allDayTimeZone = [allDayTimeZone copy];
    [self setNeedsDisplay:YES];
}

- (void)setChosenDay:(NSDate *)chosenDay {
    _chosenDay = chosenDay ? [_calendar startOfDayForDate:chosenDay] : nil;
    [self setNeedsDisplay:YES];
}

- (void)setFirstHour:(NSInteger)firstHour {
    _firstHour = firstHour;
    [self setNeedsDisplay:YES];
}

- (void)setLastHour:(NSInteger)lastHour {
    _lastHour = lastHour;
    [self setNeedsDisplay:YES];
}

- (void)setDataSource:(id<UDCalendarViewDataSource>)dataSource {
    _dataSource = dataSource;
    [self reloadData];
}

- (void)rangeChanged {
    [self reloadData];
    if ([_delegate respondsToSelector:@selector(calendarViewDidChangeRange:)]) [_delegate calendarViewDidChangeRange:self];
}

- (NSArray<id<UDCalendarItem>> *)items {
    return _items;
}

- (void)reloadData {
    NSArray *items = [_dataSource calendarView:self itemsFrom:self.rangeStart to:self.rangeEnd] ?: @[];
    _items = [items sortedArrayUsingFunction:UDItemOrder context:NULL];
    [self setNeedsDisplay:YES];
}

- (NSDate *)day:(NSDate *)day plus:(NSInteger)days {
    NSDateComponents *by = [[NSDateComponents alloc] init];
    by.day = days;
    return [_calendar dateByAddingComponents:by toDate:day options:0];
}

- (NSDate *)monthStart {
    return [_calendar dateFromComponents:[_calendar components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:_date]];
}

- (NSDate *)weekStartOf:(NSDate *)day {
    NSInteger weekday = [_calendar component:NSCalendarUnitWeekday fromDate:day];
    return [self day:day plus:-((weekday - (NSInteger)_calendar.firstWeekday + 7) % 7)];
}

- (NSInteger)days {
    return _mode == UDCalendarModeDay ? 1 : _mode == UDCalendarModeWeek ? 7 : UDWeeks * 7;
}

- (NSDate *)rangeStart {
    switch (_mode) {
    case UDCalendarModeDay: return _date;
    case UDCalendarModeWeek: return [self weekStartOf:_date];
    case UDCalendarModeMonth: return [self weekStartOf:[self monthStart]];
    }
    return _date;
}

- (NSDate *)rangeEnd {
    return [self day:self.rangeStart plus:[self days]];
}

- (NSString *)rangeTitle {
    NSDateFormatter *say = [[NSDateFormatter alloc] init];
    say.calendar = _calendar;
    say.timeZone = _calendar.timeZone;
    if (_mode == UDCalendarModeDay) {
        say.dateStyle = NSDateFormatterFullStyle;
        say.timeStyle = NSDateFormatterNoStyle;
        return [say stringFromDate:_date];
    }
    if (_mode == UDCalendarModeMonth) {
        say.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMMyyyy" options:0 locale:[NSLocale currentLocale]];
        return [say stringFromDate:_date];
    }
    NSDate *first = self.rangeStart;
    NSDate *last = [self day:first plus:6];
    say.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMd" options:0 locale:[NSLocale currentLocale]];
    NSString *from = [say stringFromDate:first];
    say.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMdyyyy" options:0 locale:[NSLocale currentLocale]];
    return [NSString stringWithFormat:@"%@ – %@", from, [say stringFromDate:last]];
}

- (void)moveBy:(NSInteger)steps {
    NSDateComponents *by = [[NSDateComponents alloc] init];
    if (_mode == UDCalendarModeMonth) by.month = steps;
    else by.day = steps * (_mode == UDCalendarModeWeek ? 7 : 1);
    self.date = [_calendar dateByAddingComponents:by toDate:_date options:0];
}

- (IBAction)goBack:(id)sender {
    [self moveBy:-1];
}

- (IBAction)goForward:(id)sender {
    [self moveBy:1];
}

- (IBAction)goToToday:(id)sender {
    self.date = [NSDate date];
}

- (IBAction)takeModeFrom:(id)sender {
    NSInteger mode = [sender respondsToSelector:@selector(selectedSegment)] ? [sender selectedSegment] : [sender tag];
    if (mode >= UDCalendarModeDay && mode <= UDCalendarModeMonth) self.mode = (UDCalendarMode)mode;
}

#pragma mark Days

- (NSDate *)dayOfItem:(id<UDCalendarItem>)item {
    if (!UDAllDay(item)) return [_calendar startOfDayForDate:item.calendarDate];
    NSCalendar *read = [_calendar copy];
    read.timeZone = _allDayTimeZone;
    NSDateComponents *day = [read components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:item.calendarDate];
    return [_calendar dateFromComponents:day];
}

- (NSDictionary<NSDate *, NSMutableArray<id<UDCalendarItem>> *> *)itemsByDay {
    NSMutableDictionary *byDay = [NSMutableDictionary dictionary];
    for (id<UDCalendarItem> item in _items) {
        NSDate *day = [self dayOfItem:item];
        NSMutableArray *those = byDay[day];
        if (!those) byDay[day] = those = [NSMutableArray array];
        [those addObject:item];
    }
    return byDay;
}

/* Month mode's cell of a day's index; day and week mode's column. */
- (NSRect)cellOfIndex:(NSInteger)index {
    NSRect bounds = self.bounds;
    if (_mode == UDCalendarModeMonth) {
        CGFloat width = floor(bounds.size.width / 7);
        CGFloat height = floor((bounds.size.height - UDMonthHeader) / UDWeeks);
        return NSMakeRect((index % 7) * width, UDMonthHeader + (index / 7) * height, width, height);
    }
    CGFloat width = floor((bounds.size.width - UDHourGutter) / [self days]);
    return NSMakeRect(UDHourGutter + index * width, 0, width, bounds.size.height);
}

- (NSDate *)dayAtPoint:(NSPoint)point {
    NSDate *first = self.rangeStart;
    for (NSInteger i = 0; i < [self days]; i++) {
        if (NSPointInRect(point, [self cellOfIndex:i])) return [self day:first plus:i];
    }
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    NSDate *day = [self dayAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (event.clickCount > 1 && day && _mode != UDCalendarModeDay) {
        self.chosenDay = day;
        _date = day;
        self.mode = UDCalendarModeDay;
    } else {
        self.chosenDay = [day isEqualToDate:_chosenDay] ? nil : day;
    }
    if ([_delegate respondsToSelector:@selector(calendarView:didChooseDay:)]) [_delegate calendarView:self didChooseDay:_chosenDay];
}

#pragma mark Drawing

- (NSDictionary *)textOf:(NSColor *)color font:(NSFont *)font {
    return @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color };
}

- (NSString *)timeOf:(NSDate *)moment {
    NSDateFormatter *say = [[NSDateFormatter alloc] init];
    say.timeZone = _calendar.timeZone;
    say.dateStyle = NSDateFormatterNoStyle;
    say.timeStyle = NSDateFormatterShortStyle;
    return [say stringFromDate:moment];
}

- (void)drawRect:(NSRect)dirty {
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(self.bounds);
    if (_mode == UDCalendarModeMonth) [self drawMonth];
    else [self drawDays];
}

- (void)drawMonth {
    NSDictionary *small = [self textOf:[NSColor textColor] font:UDFont(NO, NO)];
    NSDictionary *dim = [self textOf:[NSColor disabledControlTextColor] font:UDFont(NO, NO)];
    NSArray<NSString *> *names = [[NSDateFormatter alloc] init].shortWeekdaySymbols;
    for (NSInteger column = 0; column < 7; column++) {
        NSString *name = names[(NSUInteger)(((NSInteger)_calendar.firstWeekday - 1 + column) % 7)];
        [name drawAtPoint:NSMakePoint(NSMinX([self cellOfIndex:column]) + 4, 3) withAttributes:small];
    }
    NSDate *first = self.rangeStart;
    NSDate *today = [_calendar startOfDayForDate:[NSDate date]];
    NSInteger month = [_calendar component:NSCalendarUnitMonth fromDate:_date];
    NSDictionary *byDay = [self itemsByDay];
    for (NSInteger i = 0; i < UDWeeks * 7; i++) {
        NSDate *day = [self day:first plus:i];
        NSRect cell = [self cellOfIndex:i];
        if ([day isEqualToDate:_chosenDay]) {
            [[NSColor selectedTextBackgroundColor] setFill];
            NSRectFill(cell);
        }
        [[NSColor gridColor] setStroke];
        [NSBezierPath strokeRect:NSInsetRect(cell, 0.5, 0.5)];
        BOOL inMonth = [_calendar component:NSCalendarUnitMonth fromDate:day] == month;
        NSMutableDictionary *numbered = [(inMonth ? small : dim) mutableCopy];
        if ([day isEqualToDate:today]) numbered[NSFontAttributeName] = UDFont(NO, YES);
        [[NSString stringWithFormat:@"%ld", (long)[_calendar component:NSCalendarUnitDay fromDate:day]]
               drawAtPoint:NSMakePoint(NSMinX(cell) + 4, NSMinY(cell) + 2)
            withAttributes:numbered];
        NSArray<id<UDCalendarItem>> *those = byDay[day];
        NSInteger room = (NSInteger)floor((NSHeight(cell) - 16) / UDLineHeight);
        for (NSInteger line = 0; line < (NSInteger)those.count && line < room; line++) {
            id<UDCalendarItem> item = those[(NSUInteger)line];
            NSRect row = NSMakeRect(NSMinX(cell) + 4, NSMinY(cell) + 16 + line * UDLineHeight, NSWidth(cell) - 8, UDLineHeight);
            if (line == room - 1 && (NSInteger)those.count > room) {
                [[NSString stringWithFormat:@"+%ld more", (long)(those.count - (NSUInteger)line)] drawInRect:row withAttributes:dim];
                break;
            }
            [self drawLineOf:item in:row];
        }
    }
}

/* An item as a line: a dot of its colour, its title. */
- (void)drawLineOf:(id<UDCalendarItem>)item in:(NSRect)row {
    [item.calendarColor setFill];
    NSRectFill(NSMakeRect(NSMinX(row), NSMinY(row) + 4, 5, 5));
    NSString *title = UDAllDay(item) ? item.calendarTitle
                                     : [NSString stringWithFormat:@"%@ %@", [self timeOf:item.calendarDate], item.calendarTitle];
    [title drawInRect:NSMakeRect(NSMinX(row) + 8, NSMinY(row), NSWidth(row) - 8, UDLineHeight)
       withAttributes:[self textOf:item.calendarColor font:UDFont(UDTentative(item), NO)]];
}

- (void)drawDays {
    NSDate *first = self.rangeStart;
    NSDate *today = [_calendar startOfDayForDate:[NSDate date]];
    NSDictionary *byDay = [self itemsByDay];
    NSDictionary *small = [self textOf:[NSColor textColor] font:UDFont(NO, NO)];
    NSDictionary *dim = [self textOf:[NSColor disabledControlTextColor] font:UDFont(NO, NO)];
    NSInteger days = [self days];

    /* The all-day band: as tall as its fullest day, three lines at most. */
    NSUInteger allDay = 0;
    for (NSInteger i = 0; i < days; i++) {
        NSUInteger count = 0;
        for (id<UDCalendarItem> item in byDay[[self day:first plus:i]]) {
            if (UDAllDay(item)) count++;
        }
        allDay = MAX(allDay, count);
    }
    NSUInteger bandLines = MIN(MAX(allDay, (NSUInteger)1), (NSUInteger)3);
    CGFloat band = bandLines * UDLineHeight + 6;
    CGFloat top = UDDaysHeader + band;
    NSInteger hours = MAX(_lastHour - _firstHour, 1);
    CGFloat hourHeight = (NSHeight(self.bounds) - top) / hours;

    /* The hours. */
    for (NSInteger hour = 0; hour <= hours; hour++) {
        CGFloat y = floor(top + hour * hourHeight) + 0.5;
        [[NSColor gridColor] setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(UDHourGutter, y) toPoint:NSMakePoint(NSMaxX(self.bounds), y)];
        if (hour < hours) {
            NSDateComponents *at = [[NSDateComponents alloc] init];
            at.hour = _firstHour + hour;
            NSDate *moment = [_calendar dateByAddingComponents:at toDate:today options:0];
            [[self timeOf:moment] drawAtPoint:NSMakePoint(2, y + 1) withAttributes:dim];
        }
    }
    NSArray<NSString *> *names = [[NSDateFormatter alloc] init].shortWeekdaySymbols;
    for (NSInteger i = 0; i < days; i++) {
        NSDate *day = [self day:first plus:i];
        NSRect column = [self cellOfIndex:i];
        if ([day isEqualToDate:_chosenDay]) {
            [[NSColor selectedTextBackgroundColor] setFill];
            NSRectFill(column);
        }
        [[NSColor gridColor] setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(column) + 0.5, 0) toPoint:NSMakePoint(NSMinX(column) + 0.5, NSMaxY(column))];
        NSInteger weekday = [_calendar component:NSCalendarUnitWeekday fromDate:day];
        NSString *heading = [NSString stringWithFormat:@"%@ %ld", names[(NSUInteger)(weekday - 1)],
                                                       (long)[_calendar component:NSCalendarUnitDay fromDate:day]];
        NSMutableDictionary *headed = [small mutableCopy];
        if ([day isEqualToDate:today]) headed[NSFontAttributeName] = UDFont(NO, YES);
        [heading drawAtPoint:NSMakePoint(NSMinX(column) + 4, 8) withAttributes:headed];

        NSArray<id<UDCalendarItem>> *those = byDay[day];
        NSUInteger line = 0;
        NSMutableArray<id<UDCalendarItem>> *timed = [NSMutableArray array];
        for (id<UDCalendarItem> item in those) {
            if (!UDAllDay(item)) {
                [timed addObject:item];
                continue;
            }
            if (line >= bandLines) continue;
            NSRect row = NSMakeRect(NSMinX(column) + 4, UDDaysHeader + line * UDLineHeight, NSWidth(column) - 8, UDLineHeight);
            if (line == bandLines - 1 && allDay > bandLines) {
                [[NSString stringWithFormat:@"+%lu more", (unsigned long)(allDay - line)] drawInRect:row withAttributes:dim];
            } else {
                [self drawLineOf:item in:row];
            }
            line++;
        }
        [self drawTimed:timed in:column top:top hourHeight:hourHeight day:day];
    }
}

/* A day's timed items at their times: those that meet side by side, as
   many as are wide enough to read; past them, how many more. */
- (void)drawTimed:(NSArray<id<UDCalendarItem>> *)timed in:(NSRect)column top:(CGFloat)top hourHeight:(CGFloat)hourHeight day:(NSDate *)day {
    CGFloat blockHeight = MAX(UDLineHeight + 2, hourHeight * 0.75);
    if (_mode == UDCalendarModeDay) blockHeight = MAX(blockHeight, 2 * UDLineHeight + 4);
    CGFloat bottom = NSMaxY(self.bounds);
    CGFloat readable = _mode == UDCalendarModeDay ? 120 : 70;
    NSUInteger fit = MAX((NSUInteger)floor((NSWidth(column) - 6) / readable), (NSUInteger)1);
    NSMutableArray<NSNumber *> *ys = [NSMutableArray array];
    for (id<UDCalendarItem> item in timed) {
        double hours = [item.calendarDate timeIntervalSinceDate:day] / 3600.0 - _firstHour;
        CGFloat y = top + MAX(0, MIN(hours, (double)(_lastHour - _firstHour))) * hourHeight;
        [ys addObject:@(MIN(y, bottom - blockHeight))];
    }
    /* Clusters of those that meet, each laid out on its own. */
    NSUInteger start = 0;
    while (start < timed.count) {
        NSUInteger end = start + 1;
        CGFloat reach = ys[start].doubleValue + blockHeight;
        while (end < timed.count && ys[end].doubleValue < reach) {
            reach = MAX(reach, ys[end].doubleValue + blockHeight);
            end++;
        }
        [self drawCluster:[timed subarrayWithRange:NSMakeRange(start, end - start)]
                       ys:[ys subarrayWithRange:NSMakeRange(start, end - start)]
                       in:column
              blockHeight:blockHeight
                      fit:fit];
        start = end;
    }
}

- (void)drawCluster:(NSArray<id<UDCalendarItem>> *)items ys:(NSArray<NSNumber *> *)ys in:(NSRect)column
        blockHeight:(CGFloat)blockHeight fit:(NSUInteger)fit {
    NSMutableArray<NSNumber *> *lanes = [NSMutableArray array];
    NSMutableArray<NSNumber *> *laneEnds = [NSMutableArray array];
    for (NSNumber *y in ys) {
        NSUInteger lane = 0;
        while (lane < laneEnds.count && laneEnds[lane].doubleValue > y.doubleValue) lane++;
        if (lane == laneEnds.count) [laneEnds addObject:@(y.doubleValue + blockHeight)];
        else laneEnds[lane] = @(y.doubleValue + blockHeight);
        [lanes addObject:@(lane)];
    }
    BOOL overflows = laneEnds.count > fit;
    /* Overflowing: the first ones a lane each, the last lane for how many
       more (with one lane only, the first says it). */
    NSUInteger shown = overflows ? MAX(fit - 1, (NSUInteger)1) : items.count;
    NSUInteger laneCount = overflows ? fit : laneEnds.count;
    CGFloat laneWidth = (NSWidth(column) - 6) / laneCount;
    NSUInteger more = items.count - MIN(shown, items.count);
    for (NSUInteger i = 0; i < MIN(shown, items.count); i++) {
        id<UDCalendarItem> item = items[i];
        NSUInteger lane = overflows ? i : lanes[i].unsignedIntegerValue;
        NSRect block = NSMakeRect(NSMinX(column) + 3 + lane * laneWidth, ys[i].doubleValue, laneWidth - 2, blockHeight);
        NSString *suffix = overflows && fit == 1 && i == 0 ? [NSString stringWithFormat:@"+%lu", (unsigned long)more] : @"";
        [self drawBlockOf:item in:block suffix:suffix];
    }
    if (overflows && fit > 1) {
        NSRect block = NSMakeRect(NSMinX(column) + 3 + (fit - 1) * laneWidth, ys[0].doubleValue, laneWidth - 2, blockHeight);
        [[NSColor colorWithCalibratedWhite:0.5 alpha:0.25] setFill];
        NSRectFill(block);
        [[NSString stringWithFormat:@"+%lu more", (unsigned long)more]
                drawInRect:NSMakeRect(NSMinX(block) + 6, NSMinY(block) + 1, NSWidth(block) - 8, UDLineHeight)
            withAttributes:[self textOf:[NSColor textColor] font:UDFont(NO, NO)]];
    }
}

/* An item as a block: its colour, its time and title; in day mode its
   detail beneath. */
- (void)drawBlockOf:(id<UDCalendarItem>)item in:(NSRect)block suffix:(NSString *)suffix {
    [[item.calendarColor colorWithAlphaComponent:0.25] setFill];
    NSRectFill(block);
    [item.calendarColor setFill];
    NSRectFill(NSMakeRect(NSMinX(block), NSMinY(block), 3, NSHeight(block)));
    NSDictionary *text = [self textOf:[NSColor textColor] font:UDFont(UDTentative(item), NO)];
    /* How many more, at the right; the title in what is left. */
    CGFloat counted = 0;
    if (suffix.length) {
        NSDictionary *bold = [self textOf:[NSColor textColor] font:UDFont(NO, YES)];
        counted = [suffix sizeWithAttributes:bold].width + 4;
        [suffix drawAtPoint:NSMakePoint(NSMaxX(block) - counted, NSMinY(block) + 1) withAttributes:bold];
    }
    NSString *title = [NSString stringWithFormat:@"%@ %@", [self timeOf:item.calendarDate], item.calendarTitle];
    [title drawInRect:NSMakeRect(NSMinX(block) + 6, NSMinY(block) + 1, NSWidth(block) - 8 - counted, UDLineHeight) withAttributes:text];
    NSString *detail = UDDetail(item);
    if (_mode == UDCalendarModeDay && detail.length) {
        [detail drawInRect:NSMakeRect(NSMinX(block) + 6, NSMinY(block) + 1 + UDLineHeight, NSWidth(block) - 8, UDLineHeight)
            withAttributes:[self textOf:[NSColor disabledControlTextColor] font:UDFont(NO, NO)]];
    }
}
@end
