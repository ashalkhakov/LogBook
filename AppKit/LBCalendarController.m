#import "LBCalendarController.h"
#import "LBMainWindowController.h"
#import "LBMonthView.h"
#import "LBCalendar.h"
#import "LBProcedures.h"
#import "Vehicle+CoreDataClass.h"

@interface LBCalendarController ()
@property (nonatomic, readwrite, copy) NSString *monthTitle;
@property (nonatomic, readwrite, copy) NSArray<LBCalendarEntry *> *listed;
@property (nonatomic, readwrite, copy) NSArray<LBCalendarEntry *> *entries;
@end

@implementation LBCalendarController

- (instancetype)init {
    if ((self = [super init])) {
        _monthTitle = @"";
        _listed = @[];
        _entries = @[];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    _monthView.target = self;
    _monthView.action = @selector(dayChosen:);
    [self refresh];
}

- (NSCalendar *)utc {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return calendar;
}

- (void)showMonth:(NSDate *)month {
    _monthView.month = month;
    _monthView.chosenDay = nil;
    [self refresh];
}

- (void)moveBy:(NSInteger)months {
    NSDateComponents *by = [[NSDateComponents alloc] init];
    by.month = months;
    [self showMonth:[[self utc] dateByAddingComponents:by toDate:_monthView.month options:0]];
}

- (IBAction)previousMonth:(id)sender {
    [self moveBy:-1];
}

- (IBAction)nextMonth:(id)sender {
    [self moveBy:1];
}

- (IBAction)thisMonth:(id)sender {
    NSCalendar *utc = [self utc];
    [self showMonth:[utc dateFromComponents:[utc components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:[NSDate date]]]];
}

- (void)setAllVehicles:(BOOL)allVehicles {
    _allVehicles = allVehicles;
    [self refresh];
}

- (IBAction)dayChosen:(id)sender {
    [self list];
}

- (void)refresh {
    if (!_monthView) return;
    NSDate *now = [NSDate date];
    NSDateFormatter *title = [[NSDateFormatter alloc] init];
    title.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    title.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMMyyyy" options:0 locale:[NSLocale currentLocale]];
    self.monthTitle = [title stringFromDate:_monthView.month];
    NSArray *vehicles = _allVehicles ? _windowController.vehicles.arrangedObjects : nil;
    Vehicle *chosen = [_windowController chosenVehicle];
    self.entries = [LBCalendar entriesOfVehicles:vehicles ?: (chosen ? @[ chosen ] : @[]) from:_monthView.firstDay to:_monthView.endDay
                                            asOf:now];
    _monthView.showsVehicles = _allVehicles;
    _monthView.today = LBDay(now);
    _monthView.entries = _entries;
    [self list];
}

/* The chosen day's entries, else those of the month itself (not the days
   of the weeks around it). */
- (void)list {
    NSDate *chosen = _monthView.chosenDay;
    NSCalendar *utc = [self utc];
    NSInteger month = [utc component:NSCalendarUnitMonth fromDate:_monthView.month];
    NSMutableArray *listed = [NSMutableArray array];
    for (LBCalendarEntry *entry in _entries) {
        BOOL shown = chosen ? [entry.day isEqualToDate:chosen] : [utc component:NSCalendarUnitMonth fromDate:entry.day] == month;
        if (shown) [listed addObject:entry];
    }
    self.listed = listed;
}

@end
