#import "LBCalendarController.h"
#import "LBMainWindowController.h"
#import "LBCalendar.h"
#import "Vehicle+CoreDataClass.h"

/* An entry as the calendar view draws one. */
@interface LBCalendarItem : NSObject <UDCalendarItem>
@property (nonatomic, strong) LBCalendarEntry *entry;
@property (nonatomic) BOOL saysVehicle;
@end

@implementation LBCalendarItem

- (NSDate *)calendarDate {
    return _entry.moment ?: _entry.day;
}

- (BOOL)calendarAllDay {
    return _entry.moment == nil;
}

- (NSString *)calendarTitle {
    return _saysVehicle ? [NSString stringWithFormat:@"%@: %@", _entry.vehicleTitle, _entry.title] : _entry.title;
}

- (NSString *)calendarDetail {
    return _entry.detail;
}

- (BOOL)calendarTentative {
    return _entry.estimated;
}

- (NSColor *)calendarColor {
    switch (_entry.kind) {
    case LBCalendarDone: return [NSColor colorWithCalibratedRed:0.20 green:0.60 blue:0.30 alpha:1];
    case LBCalendarCancelled: return [NSColor colorWithCalibratedWhite:0.55 alpha:1];
    case LBCalendarOpen: return [NSColor colorWithCalibratedRed:0.15 green:0.40 blue:0.85 alpha:1];
    case LBCalendarOverdue: return [NSColor colorWithCalibratedRed:0.85 green:0.20 blue:0.20 alpha:1];
    case LBCalendarPlanned: return [NSColor colorWithCalibratedRed:0.45 green:0.65 blue:0.95 alpha:1];
    case LBCalendarRecord: return [NSColor textColor];
    }
    return [NSColor textColor];
}

@end

@interface LBCalendarController ()
@property (nonatomic, readwrite, copy) NSString *rangeTitle;
@property (nonatomic, readwrite, copy) NSArray<LBCalendarEntry *> *listed;
@property (nonatomic, readwrite, copy) NSArray<LBCalendarEntry *> *entries;
@end

@implementation LBCalendarController {
    NSArray<LBCalendarItem *> *_items;
}

- (instancetype)init {
    if ((self = [super init])) {
        _rangeTitle = @"";
        _listed = @[];
        _entries = @[];
        _items = @[];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    /* A day of the model is a UTC day. */
    _calendarView.allDayTimeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    _calendarView.mode = UDCalendarModeMonth;
    _modeControl.selectedSegment = UDCalendarModeMonth;
}

- (void)setAllVehicles:(BOOL)allVehicles {
    _allVehicles = allVehicles;
    [self refresh];
}

- (void)refresh {
    [_calendarView reloadData];
    [self list];
}

- (IBAction)previous:(id)sender {
    [_calendarView goBack:sender];
}

- (IBAction)next:(id)sender {
    [_calendarView goForward:sender];
}

- (IBAction)today:(id)sender {
    [_calendarView goToToday:sender];
}

- (IBAction)modeChosen:(id)sender {
    [_calendarView takeModeFrom:sender];
}

#pragma mark The view's data source and delegate

- (NSArray<id<UDCalendarItem>> *)calendarView:(UDCalendarView *)view itemsFrom:(NSDate *)start to:(NSDate *)end {
    NSArray *vehicles = _allVehicles ? _windowController.vehicles.arrangedObjects : nil;
    Vehicle *chosen = [_windowController chosenVehicle];
    /* The model's days around the range: a moment near midnight here may
       be another day there. */
    NSDate *from = [start dateByAddingTimeInterval:-24 * 60 * 60];
    NSDate *to = [end dateByAddingTimeInterval:24 * 60 * 60];
    NSArray<LBCalendarEntry *> *all = [LBCalendar entriesOfVehicles:vehicles ?: (chosen ? @[ chosen ] : @[]) from:from to:to
                                                               asOf:[NSDate date]];
    NSMutableArray<LBCalendarItem *> *items = [NSMutableArray array];
    NSMutableArray<LBCalendarEntry *> *entries = [NSMutableArray array];
    for (LBCalendarEntry *entry in all) {
        LBCalendarItem *item = [[LBCalendarItem alloc] init];
        item.entry = entry;
        item.saysVehicle = _allVehicles;
        NSDate *day = [view dayOfItem:item];
        if ([day compare:start] == NSOrderedAscending || [day compare:end] != NSOrderedAscending) continue;
        [items addObject:item];
        [entries addObject:entry];
    }
    _items = items;
    self.entries = entries;
    return items;
}

- (void)calendarView:(UDCalendarView *)view didChooseDay:(NSDate *)day {
    [self list];
}

- (void)calendarViewDidChangeRange:(UDCalendarView *)view {
    _modeControl.selectedSegment = view.mode;
    [self list];
}

/* The chosen day's entries, else the range's (a month's own days only). */
- (void)list {
    UDCalendarView *view = _calendarView;
    self.rangeTitle = view.rangeTitle ?: @"";
    NSCalendar *calendar = view.calendar;
    NSInteger month = [calendar component:NSCalendarUnitMonth fromDate:view.date];
    NSMutableArray *listed = [NSMutableArray array];
    for (LBCalendarItem *item in _items) {
        NSDate *day = [view dayOfItem:item];
        BOOL shown = view.chosenDay ? [day isEqualToDate:view.chosenDay]
                                    : view.mode != UDCalendarModeMonth || [calendar component:NSCalendarUnitMonth fromDate:day] == month;
        if (shown) [listed addObject:item.entry];
    }
    self.listed = listed;
}

@end
