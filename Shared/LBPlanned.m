#import "LBPlanned.h"
#import "LBProcedures.h"
#import "Event+CoreDataClass.h"

static const NSTimeInterval LBDaySeconds = 24 * 60 * 60;
// Readings over so many days tell how far a vehicle goes a day.
static const NSInteger LBRateDays = 90;
// By distance with no day to tell, so many planned at most.
static const NSUInteger LBUndatedPlanned = 3;
// Whatever the rules, so many planned at most.
static const NSUInteger LBMostPlanned = 60;

@interface LBPlannedReminder ()
@property (nonatomic, readwrite) Schedule *schedule;
@property (nonatomic, readwrite, nullable) NSDate *dueDate;
@property (nonatomic, readwrite, nullable) NSDecimalNumber *dueMileage;
@property (nonatomic, readwrite, nullable) DistanceUnit *dueUnit;
@property (nonatomic, readwrite, nullable) NSDate *day;
@property (nonatomic, readwrite) BOOL estimated;
@end

@implementation LBPlannedReminder
@end

/* A distance in kilometres; NaN for one of no unit. */
static double LBKilometres(NSDecimalNumber *quantity, DistanceUnit *unit) {
    if (!quantity || !unit.factor) return NAN;
    return quantity.doubleValue * unit.factor.doubleValue;
}

/* Kilometres in the unit, as a decimal of two places. */
static NSDecimalNumber *LBInUnitOf(double kilometres, DistanceUnit *unit) {
    double factor = unit.factor.doubleValue;
    if (!(factor > 0)) return nil;
    NSDecimalNumberHandler *two = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:2 raiseOnExactness:NO
                                                                               raiseOnOverflow:NO raiseOnUnderflow:NO
                                                                            raiseOnDivideByZero:NO];
    return [[NSDecimalNumber decimalNumberWithDecimal:@(kilometres / factor).decimalValue] decimalNumberByRoundingAccordingToBehavior:two];
}

/* The earlier of two days, either of which may be none. */
static NSDate *LBEarlier(NSDate *a, NSDate *b) {
    if (!a) return b;
    if (!b) return a;
    return [a compare:b] == NSOrderedDescending ? b : a;
}

@implementation Vehicle (LBPlanned)

/* Its odometer readings: events at a distance, earliest first. */
- (NSArray<Event *> *)lbReadings {
    NSMutableArray<Event *> *readings = [NSMutableArray array];
    for (Record *record in self.records) {
        if (record.isDeleted || ![record isKindOfClass:[Event class]]) continue;
        Event *event = (Event *)record;
        if (event.timestamp && !isnan(LBKilometres(event.mileageQuantity, event.mileageDistanceUnit))) [readings addObject:event];
    }
    [readings sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(timestamp)) ascending:YES] ]];
    return readings;
}

- (NSNumber *)lbKilometresADayAsOf:(NSDate *)now {
    NSDate *since = [now dateByAddingTimeInterval:-LBRateDays * LBDaySeconds];
    Event *first = nil;
    Event *last = nil;
    for (Event *reading in [self lbReadings]) {
        if ([reading.timestamp compare:since] == NSOrderedAscending || [reading.timestamp compare:now] == NSOrderedDescending) continue;
        if (!first) first = reading;
        last = reading;
    }
    if (!first || first == last) return nil;
    double days = [last.timestamp timeIntervalSinceDate:first.timestamp] / LBDaySeconds;
    double gone = LBKilometres(last.mileageQuantity, last.mileageDistanceUnit) - LBKilometres(first.mileageQuantity, first.mileageDistanceUnit);
    if (days < 1 || !(gone > 0)) return nil;
    return @(gone / days);
}

- (NSDate *)lbDayAtMileage:(NSDecimalNumber *)mileage unit:(DistanceUnit *)unit asOf:(NSDate *)now {
    NSNumber *rate = [self lbKilometresADayAsOf:now];
    Event *latest = nil;
    for (Event *reading in [self lbReadings]) {
        if ([reading.timestamp compare:now] != NSOrderedDescending) latest = reading;
    }
    double target = LBKilometres(mileage, unit);
    if (!rate || !latest || isnan(target)) return nil;
    double ahead = target - LBKilometres(latest.mileageQuantity, latest.mileageDistanceUnit);
    double days = ahead > 0 ? ceil(ahead / rate.doubleValue) : 0;
    return LBOwnerDay(self, [latest.timestamp dateByAddingTimeInterval:days * LBDaySeconds]);
}

@end

@implementation Reminder (LBPlanned)

- (NSDate *)lbDayAsOf:(NSDate *)now estimated:(BOOL *)estimated {
    NSDate *byDistance = self.dueMileageQuantity && self.dueMileageDistanceUnit
                             ? [self.vehicle lbDayAtMileage:self.dueMileageQuantity unit:self.dueMileageDistanceUnit asOf:now]
                             : nil;
    NSDate *day = LBEarlier(self.dueDate, byDistance);
    if (estimated) *estimated = day && day == byDistance && ![day isEqualToDate:self.dueDate ?: [NSDate distantPast]];
    return day;
}

@end

@implementation Schedule (LBPlanned)

- (NSArray<LBPlannedReminder *> *)lbPlannedUntil:(NSDate *)until asOf:(NSDate *)now {
    Reminder *open = self.lb_openReminder;
    NSMutableArray<LBPlannedReminder *> *planned = [NSMutableArray array];
    if (!open) return planned;
    Vehicle *vehicle = self.vehicle;
    NSNumber *rate = [vehicle lbKilometresADayAsOf:now];
    BOOL byDistance = self.intervalQuantity && self.intervalDistanceUnit;
    DistanceUnit *unit = open.dueMileageDistanceUnit ?: self.intervalDistanceUnit;
    double interval = byDistance ? LBKilometres(self.intervalQuantity, self.intervalDistanceUnit) : NAN;

    /* Done when due: on its day, at its distance (or the distance the
       vehicle is expected at on that day). */
    NSDate *day = [open lbDayAsOf:now estimated:NULL];
    double at = LBKilometres(open.dueMileageQuantity, open.dueMileageDistanceUnit);
    NSDate *latestDay = nil;
    double latestKm = NAN;
    for (Event *reading in [vehicle lbReadings]) {
        if ([reading.timestamp compare:now] == NSOrderedDescending) continue;
        latestDay = reading.timestamp;
        latestKm = LBKilometres(reading.mileageQuantity, reading.mileageDistanceUnit);
    }
    if (isnan(at) && byDistance && day && rate && latestDay) {
        at = latestKm + rate.doubleValue * MAX(0, [day timeIntervalSinceDate:latestDay] / LBDaySeconds);
    }
    NSUInteger undated = 0;
    while (planned.count < LBMostPlanned) {
        NSDate *nextDate = self.duration > 0 && day ? LBAddMonths(day, self.duration) : nil;
        double nextKm = byDistance && !isnan(at) ? at + interval : NAN;
        if (!nextDate && isnan(nextKm)) break;
        NSDecimalNumber *nextMileage = isnan(nextKm) ? nil : LBInUnitOf(nextKm, unit);
        NSDate *expected = nextMileage ? [vehicle lbDayAtMileage:nextMileage unit:unit asOf:now] : nil;
        LBPlannedReminder *one = [[LBPlannedReminder alloc] init];
        one.schedule = self;
        one.dueDate = nextDate;
        one.dueMileage = nextMileage;
        one.dueUnit = nextMileage ? unit : nil;
        one.day = LBEarlier(nextDate, expected);
        one.estimated = one.day && one.day == expected && ![one.day isEqualToDate:nextDate ?: [NSDate distantPast]];
        if (one.day && [one.day compare:until] == NSOrderedDescending) break;
        if (!one.day && ++undated > LBUndatedPlanned) break;
        [planned addObject:one];
        /* The next counted from this one, done when due. */
        if (one.day && !one.estimated && !isnan(nextKm) && rate && latestDay) {
            nextKm = MIN(nextKm, latestKm + rate.doubleValue * MAX(0, [one.day timeIntervalSinceDate:latestDay] / LBDaySeconds));
        }
        day = one.day;
        at = nextKm;
        if (!day && !byDistance) break;
    }
    return planned;
}

@end
