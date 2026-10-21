#import "LBVehicleSummary.h"
#import "LBDisplay.h"
#import "LBProcedures.h"
#import "LogbookValidation.h"
#import "Event+CoreDataClass.h"
#import "Document+CoreDataClass.h"
#import "TyreSet+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"

@interface LBMonth ()
@property (nonatomic, readwrite, copy) NSString *title;
@property (nonatomic, readwrite, copy) NSArray<Record *> *records;
@end

@implementation LBMonth
@end

@implementation LBVehicleSummary {
    NSMutableSet<NSUUID *> *_overdue;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithVehicle:(Vehicle *)vehicle {
    if ((self = [super init])) {
        _vehicle = vehicle;
        _overdue = [NSMutableSet set];
    }
    return self;
}

/* Newest first; of the same moment, by id, so the order holds. */
static NSComparisonResult LBNewestFirst(Record *a, Record *b, void *unused) {
    NSComparisonResult order = [b.lbDate compare:a.lbDate];
    return order != NSOrderedSame ? order : [b.id.UUIDString compare:a.id.UUIDString];
}

- (NSArray<LBMonth *> *)months {
    NSMutableArray<Record *> *records = [NSMutableArray array];
    for (Record *record in _vehicle.records) {
        if (record.isDeleted || !record.lbDate) continue;
        if ([record isKindOfClass:[Event class]] || [record isKindOfClass:[Document class]] || [record isKindOfClass:[TyreSet class]])
            [records addObject:record];
    }
    [records sortUsingFunction:LBNewestFirst context:NULL];
    NSDateFormatter *monthOf = [[NSDateFormatter alloc] init];
    monthOf.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"MMMM yyyy" options:0 locale:[NSLocale currentLocale]] ?: @"MMMM yyyy";
    NSMutableArray<LBMonth *> *months = [NSMutableArray array];
    NSMutableArray *current = nil;
    NSString *title = nil;
    for (Record *record in records) {
        NSString *month = [monthOf stringFromDate:record.lbDate];
        if (![month isEqualToString:title]) {
            if (current) {
                LBMonth *done = [[LBMonth alloc] init];
                done.title = title;
                done.records = current;
                [months addObject:done];
            }
            title = month;
            current = [NSMutableArray array];
        }
        [current addObject:record];
    }
    if (current) {
        LBMonth *done = [[LBMonth alloc] init];
        done.title = title;
        done.records = current;
        [months addObject:done];
    }
    return months;
}

/* The overdue, as the model's queries say, of this vehicle. */
- (void)askOverdue {
    [_overdue removeAllObjects];
    NSManagedObjectContext *context = _vehicle.managedObjectContext;
    if (!context) return;
    NSError *error = nil;
    ORMQueryResult *byDate = [LogbookQueries overdueRemindersInContext:context error:&error];
    ORMQueryResult *byMileage = [LogbookQueries overdueByMileageInContext:context error:&error];
    for (ORMQueryResult *result in @[ byDate ?: [ORMQueryResult resultWithObjects:@[] columnTitles:@[] rows:@[]],
                                      byMileage ?: [ORMQueryResult resultWithObjects:@[] columnTitles:@[] rows:@[]] ]) {
        for (id object in result.objects) {
            if ([object isKindOfClass:[Reminder class]] && ((Reminder *)object).vehicle == _vehicle && ((Reminder *)object).id)
                [_overdue addObject:((Reminder *)object).id];
        }
    }
}

- (BOOL)isOverdue:(Reminder *)reminder {
    return reminder.id && [_overdue containsObject:reminder.id];
}

/* Where a reminder is in the list: open before closed, overdue before not;
   open ones by when they are due (a date before none), closed ones by
   when they were closed, the latest first. */
static NSInteger LBRank(Reminder *r, LBVehicleSummary *summary) {
    if (!r.lb_isOpen) return 2;
    return [summary isOverdue:r] ? 0 : 1;
}

static NSDate *LBClosedOn(Reminder *r) {
    return r.doneAt ?: r.cancelDate ?: r.setAt;
}

static NSComparisonResult LBReminderOrder(Reminder *a, Reminder *b, void *context) {
    LBVehicleSummary *summary = (__bridge LBVehicleSummary *)context;
    NSInteger ra = LBRank(a, summary), rb = LBRank(b, summary);
    if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
    NSComparisonResult order;
    if (ra < 2) {
        NSDate *da = a.dueDate ?: [NSDate distantFuture], *db = b.dueDate ?: [NSDate distantFuture];
        order = [da compare:db];
        if (order == NSOrderedSame && a.dueMileageQuantity && b.dueMileageQuantity) order = [a.dueMileageQuantity compare:b.dueMileageQuantity];
    } else {
        order = [LBClosedOn(b) compare:LBClosedOn(a)];
    }
    return order != NSOrderedSame ? order : [a.id.UUIDString compare:b.id.UUIDString];
}

- (NSArray<Reminder *> *)reminders {
    [self askOverdue];
    NSMutableArray<Reminder *> *reminders = [NSMutableArray array];
    for (Record *record in _vehicle.records) {
        if ([record isKindOfClass:[Reminder class]] && !record.isDeleted) [reminders addObject:(Reminder *)record];
    }
    [reminders sortUsingFunction:LBReminderOrder context:(__bridge void *)self];
    return reminders;
}

- (NSString *)consumption {
    NSManagedObjectContext *context = _vehicle.managedObjectContext;
    ORMQueryResult *result = context ? [LogbookQueries fullTankConsumptionInContext:context error:NULL] : nil;
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    for (id object in result.objects) {
        if ([object isKindOfClass:[FillUp class]] && ((FillUp *)object).id) byKey[((FillUp *)object).id] = object;
    }
    FillUp *latest = nil;
    NSDecimalNumber *value = nil;
    NSString *units = nil;
    for (NSArray *row in result.rows) {
        FillUp *fillUp = row.count > 3 ? byKey[row[0]] : nil;
        if (fillUp.vehicle != _vehicle) continue;
        if (latest && [fillUp.timestamp compare:latest.timestamp] != NSOrderedDescending) continue;
        latest = fillUp;
        value = row[3];
        units = [NSString stringWithFormat:@"%@/100 %@", fillUp.volumeVolumeUnit.code ?: @"", fillUp.mileageDistanceUnit.code ?: @""];
    }
    if (!value || ![value isKindOfClass:[NSNumber class]]) return nil;
    NSNumberFormatter *number = [[NSNumberFormatter alloc] init];
    number.numberStyle = NSNumberFormatterDecimalStyle;
    number.minimumFractionDigits = 2;
    number.maximumFractionDigits = 2;
    return [NSString stringWithFormat:@"%@ %@", [number stringFromNumber:value], units];
}

- (NSString *)costThisMonth {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *start = nil;
    NSTimeInterval length = 0;
    [calendar rangeOfUnit:NSCalendarUnitMonth startDate:&start interval:&length forDate:[NSDate date]];
    NSMutableDictionary<NSString *, NSDecimalNumber *> *byCurrency = [NSMutableDictionary dictionary];
    for (Record *record in _vehicle.records) {
        NSDate *when = record.lbDate;
        if (record.isDeleted || !record.totalAmount || !when || [when compare:start] == NSOrderedAscending
            || [when timeIntervalSinceDate:start] >= length) continue;
        NSString *currency = record.totalCurrency ?: @"";
        byCurrency[currency] = [byCurrency[currency] ?: [NSDecimalNumber zero] decimalNumberByAdding:record.totalAmount];
    }
    if (!byCurrency.count) return nil;
    NSNumberFormatter *money = [[NSNumberFormatter alloc] init];
    money.numberStyle = NSNumberFormatterDecimalStyle;
    money.minimumFractionDigits = 2;
    money.maximumFractionDigits = 2;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *currency in [byCurrency.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"%@ %@", [money stringFromNumber:byCurrency[currency]], currency]];
    }
    return [parts componentsJoinedByString:@", "];
}

- (NSString *)nextDue {
    for (Reminder *reminder in [self reminders]) {
        if (reminder.lb_isOpen) return [NSString stringWithFormat:@"%@: %@", reminder.lbWork, reminder.lbDue];
    }
    return nil;
}

@end
