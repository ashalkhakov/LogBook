#import "LBCalendar.h"
#import "LBPlanned.h"
#import "LBProcedures.h"
#import "LBDisplay.h"
#import "Event+CoreDataClass.h"
#import "Schedule+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"

@interface LBCalendarEntry ()
@property (nonatomic, readwrite) NSDate *day;
@property (nonatomic, readwrite, nullable) NSDate *moment;
@property (nonatomic, readwrite) LBCalendarKind kind;
@property (nonatomic, readwrite) NSString *kindText;
@property (nonatomic, readwrite) NSString *title;
@property (nonatomic, readwrite) NSString *detail;
@property (nonatomic, readwrite) BOOL estimated;
@property (nonatomic, readwrite, nullable) id object;
@property (nonatomic, readwrite) Vehicle *vehicle;
@end

@implementation LBCalendarEntry
- (NSString *)dayText {
    return LBDayText(_day) ?: @"";
}

- (NSString *)vehicleTitle {
    return _vehicle.lbTitle ?: @"";
}
@end

static LBCalendarEntry *LBEntry(NSDate *day, LBCalendarKind kind, NSString *kindText, NSString *title, NSString *detail, id object) {
    LBCalendarEntry *entry = [[LBCalendarEntry alloc] init];
    entry.day = LBDay(day);
    entry.kind = kind;
    entry.kindText = kindText;
    entry.title = title ?: @"";
    entry.detail = detail ?: @"";
    entry.object = object;
    return entry;
}

static NSString *LBJoined(NSArray<NSString *> *parts) {
    NSMutableArray *said = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length) [said addObject:part];
    }
    return [said componentsJoinedByString:@", "];
}

/* By day; on a day, reminders before records, then by title. */
static NSInteger LBEntryOrder(id a, id b, void *context) {
    LBCalendarEntry *x = a;
    LBCalendarEntry *y = b;
    NSComparisonResult byDay = [x.day compare:y.day];
    if (byDay != NSOrderedSame) return byDay;
    if (x.kind != y.kind) return x.kind < y.kind ? NSOrderedAscending : NSOrderedDescending;
    NSComparisonResult byVehicle = [x.vehicleTitle compare:y.vehicleTitle];
    if (byVehicle != NSOrderedSame) return byVehicle;
    return [x.title compare:y.title];
}

@implementation LBCalendar

+ (NSArray<LBCalendarEntry *> *)entriesOfVehicle:(Vehicle *)vehicle from:(NSDate *)from to:(NSDate *)to asOf:(NSDate *)now {
    return [self entriesOfVehicles:vehicle ? @[ vehicle ] : @[] from:from to:to asOf:now];
}

+ (NSArray<LBCalendarEntry *> *)entriesOfVehicles:(NSArray<Vehicle *> *)vehicles from:(NSDate *)from to:(NSDate *)to asOf:(NSDate *)now {
    NSMutableArray<LBCalendarEntry *> *all = [NSMutableArray array];
    for (Vehicle *vehicle in vehicles) {
        for (LBCalendarEntry *entry in [self entriesOfOne:vehicle from:from to:to asOf:now]) {
            entry.vehicle = vehicle;
            [all addObject:entry];
        }
    }
    [all sortUsingFunction:LBEntryOrder context:NULL];
    return all;
}

/* One vehicle's entries on the days, by day. */
+ (NSArray<LBCalendarEntry *> *)entriesOfOne:(Vehicle *)vehicle from:(NSDate *)from to:(NSDate *)to asOf:(NSDate *)now {
    NSMutableArray<LBCalendarEntry *> *entries = [NSMutableArray array];
    NSDate *today = LBDay(now);
    for (Record *record in vehicle.records) {
        if (record.isDeleted || [record isKindOfClass:[Schedule class]]) continue;
        if ([record isKindOfClass:[Reminder class]]) {
            Reminder *reminder = (Reminder *)record;
            if (reminder.doneAt) {
                BOOL late = reminder.dueDate && [LBDay(reminder.doneAt) compare:reminder.dueDate] == NSOrderedDescending;
                NSString *by = reminder.event ? [NSString stringWithFormat:@"by %@", reminder.event.lbKind] : @"by hand";
                LBCalendarEntry *entry = LBEntry(reminder.doneAt, LBCalendarDone, @"Done", reminder.lbWork,
                                                 LBJoined(@[ by, reminder.event.driver.lbTitle ?: @"", late ? @"late" : @"" ]), reminder);
                entry.moment = reminder.doneAt;
                [entries addObject:entry];
            } else if (reminder.cancelDate) {
                [entries addObject:LBEntry(reminder.cancelDate, LBCalendarCancelled, @"Cancelled", reminder.lbWork,
                                           reminder.replacement ? [NSString stringWithFormat:@"replaced, due %@", reminder.replacement.lbDue]
                                                                : @"",
                                           reminder)];
            } else {
                BOOL estimated = NO;
                NSDate *day = [reminder lbDayAsOf:now estimated:&estimated];
                if (!day) continue;
                BOOL overdue = [day compare:today] == NSOrderedAscending || [reminder.lbStatus hasPrefix:@"Overdue"];
                NSString *moved = reminder.reschedulings.count ? @"moved" : @"";
                LBCalendarEntry *entry = LBEntry(day, overdue ? LBCalendarOverdue : LBCalendarOpen, overdue ? @"Overdue" : @"Open",
                                                 reminder.lbWork,
                                                 LBJoined(@[ [@"due " stringByAppendingString:reminder.lbDue], moved,
                                                             estimated ? @"day estimated" : @"" ]),
                                                 reminder);
                entry.estimated = estimated;
                [entries addObject:entry];
            }
            continue;
        }
        NSDate *when = record.lbDate;
        if (!when) continue;
        NSString *driver = [record isKindOfClass:[Event class]] ? ((Event *)record).driver.lbTitle : nil;
        LBCalendarEntry *entry = LBEntry(when, LBCalendarRecord, record.lbKind, record.lbKind,
                                         LBJoined(@[ record.lbCost ?: @"", driver ?: @"" ]), record);
        if ([record isKindOfClass:[Event class]]) entry.moment = when;
        [entries addObject:entry];
    }
    /* What the schedules in force plan, past their open reminders. */
    for (Record *record in vehicle.records) {
        if (record.isDeleted || ![record isKindOfClass:[Schedule class]]) continue;
        Schedule *schedule = (Schedule *)record;
        if (schedule.continuation && !schedule.continuation.isDeleted) continue;
        for (LBPlannedReminder *planned in [schedule lbPlannedUntil:to asOf:now]) {
            if (!planned.day) continue;
            NSString *due = planned.dueMileage ? LBDistanceText(planned.dueMileage, planned.dueUnit) : @"";
            LBCalendarEntry *entry = LBEntry(planned.day, LBCalendarPlanned, @"Planned", schedule.lbWork,
                                             LBJoined(@[ due.length ? [@"at " stringByAppendingString:due] : @"",
                                                         planned.estimated ? @"day estimated" : @"" ]),
                                             nil);
            entry.estimated = planned.estimated;
            [entries addObject:entry];
        }
    }
    NSMutableArray<LBCalendarEntry *> *shown = [NSMutableArray array];
    NSDate *first = LBDay(from);
    for (LBCalendarEntry *entry in entries) {
        if ([entry.day compare:first] != NSOrderedAscending && [entry.day compare:to] == NSOrderedAscending) [shown addObject:entry];
    }
    [shown sortUsingFunction:LBEntryOrder context:NULL];
    return shown;
}

@end
