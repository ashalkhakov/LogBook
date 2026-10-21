#import "LBDisplay.h"
#import "Event+CoreDataClass.h"
#import "Document+CoreDataClass.h"
#import "ExpenseKind+CoreDataClass.h"
#import "LogbookValidation.h"

/* A record's day as it is changed: of each kind, what it is. */
@implementation Event (LBDisplay)
+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbDate {
    return [NSSet setWithObject:NSStringFromSelector(@selector(timestamp))];
}
@end

@implementation Document (LBDisplay)
+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbDate {
    return [NSSet setWithObject:NSStringFromSelector(@selector(date))];
}
@end

@implementation Vehicle (LBDisplay)
- (NSString *)lbTitle { return self.vehicleName ?: @""; }
@end

@implementation User (LBDisplay)
- (NSString *)lbTitle { return self.personName.length ? self.personName : self.email ?: @""; }

static NSString *LBLocaleCurrency(void) {
    return [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode] ?: @"EUR";
}

- (NSString *)lbCurrency { return self.currency.length ? self.currency : LBLocaleCurrency(); }

- (BOOL)lbTakeLocaleCurrency {
    if (self.currency.length) return NO;
    self.currency = LBLocaleCurrency();
    return YES;
}
@end

@implementation DistanceUnit (LBDisplay)
- (NSString *)lbTitle { return self.code ?: @""; }
@end

@implementation VolumeUnit (LBDisplay)
- (NSString *)lbTitle { return self.code ?: @""; }
@end

@implementation CostKind (LBDisplay)
- (NSString *)lbTitle { return self.name ?: @""; }

+ (NSArray<CostKind *> *)lbServiceKindsInContext:(NSManagedObjectContext *)context {
    NSError *error = nil;
    ORMQueryResult *found = [LogbookQueries serviceKindRuleInContext:context error:&error];
    if (!found) NSLog(@"Logbook: the kinds of service not found: %@", error.localizedDescription);
    NSMutableArray *kinds = [NSMutableArray array];
    for (id object in found.objects) {
        if ([object isKindOfClass:[CostKind class]] && ![kinds containsObject:object]) [kinds addObject:object];
    }
    [kinds sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(name)) ascending:YES] ]];
    return kinds;
}
@end

@implementation TyreSet (LBDisplay)
- (NSString *)lbTitle { return self.tyreSetName ?: @""; }
+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbDate {
    return [NSSet setWithObject:NSStringFromSelector(@selector(date))];
}
@end

@implementation Checklist (LBDisplay)
- (NSString *)lbTitle { return self.checklistName ?: @""; }
@end

NSString * const LBYesOrNo = @"Yes or no";
NSString * const LBAnyOf = @"Any of";

@implementation Question (LBDisplay)
- (BOOL)lbTakesOptions { return [self.answerKind isEqualToString:LBAnyOf]; }

+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbTakesOptions {
    return [NSSet setWithObject:NSStringFromSelector(@selector(answerKind))];
}
@end

@implementation Record (LBDisplay)

+ (NSArray<NSString *> *)lbKinds {
    return @[ @"FillUp", @"Service", @"Expense", @"Trip", @"Income", @"TyreChange", @"TyreSet", @"Document", @"MeterReading",
              @"Inspection" ];
}

+ (NSString *)lbKindOfEntityNamed:(NSString *)name {
    NSDictionary *said = @{ @"FillUp": @"Fill-up", @"TyreChange": @"Tyre change", @"TyreSet": @"Tyre set",
                            @"MeterReading": @"Meter reading" };
    return said[name] ?: name;
}

- (NSString *)lbKind {
    return [Record lbKindOfEntityNamed:self.entity.name];
}

- (NSDate *)lbDate {
    if ([self isKindOfClass:[Event class]]) return ((Event *)self).timestamp;
    if ([self isKindOfClass:[TyreSet class]]) return ((TyreSet *)self).date;
    if ([self isKindOfClass:[Document class]]) return ((Document *)self).date;
    return nil;
}

- (NSString *)lbWhen {
    NSDate *when = self.lbDate;
    if (!when) return nil;
    NSDateFormatter *said = [[NSDateFormatter alloc] init];
    said.dateStyle = NSDateFormatterShortStyle;
    said.timeStyle = [self isKindOfClass:[Event class]] ? NSDateFormatterShortStyle : NSDateFormatterNoStyle;
    return [said stringFromDate:when];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbWhen {
    return [NSSet setWithObject:NSStringFromSelector(@selector(lbDate))];
}

- (NSString *)lbCost {
    if (!self.totalAmount) return nil;
    NSNumberFormatter *money = [[NSNumberFormatter alloc] init];
    money.numberStyle = NSNumberFormatterDecimalStyle;
    money.minimumFractionDigits = 2;
    money.maximumFractionDigits = 2;
    return [NSString stringWithFormat:@"%@ %@", [money stringFromNumber:self.totalAmount], self.totalCurrency ?: @""];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbCost {
    return [NSSet setWithObjects:NSStringFromSelector(@selector(totalAmount)), NSStringFromSelector(@selector(totalCurrency)), nil];
}

@end

@implementation Record (LBDisplayTitle)

- (NSString *)lbTitle {
    NSString *when = self.lbWhen;
    return when ? [NSString stringWithFormat:@"%@, %@", self.lbKind, when] : self.lbKind;
}

@end

NSString *LBDayText(NSDate *day) {
    if (!day) return nil;
    NSDateFormatter *said = [[NSDateFormatter alloc] init];
    said.dateStyle = NSDateFormatterShortStyle;
    said.timeStyle = NSDateFormatterNoStyle;
    said.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return [said stringFromDate:day];
}

NSString *LBDistanceText(NSDecimalNumber *quantity, DistanceUnit *unit) {
    if (!quantity) return nil;
    NSNumberFormatter *number = [[NSNumberFormatter alloc] init];
    number.numberStyle = NSNumberFormatterDecimalStyle;
    number.usesGroupingSeparator = NO;
    number.maximumFractionDigits = 3;
    return [NSString stringWithFormat:@"%@ %@", [number stringFromNumber:quantity], unit.code ?: @""];
}

/* "6/1/27 or 163000 km": a day, a distance, or both. */
static NSString *LBDueText(NSDate *day, NSDecimalNumber *quantity, DistanceUnit *unit) {
    NSMutableArray *parts = [NSMutableArray array];
    if (day) [parts addObject:LBDayText(day)];
    if (quantity) [parts addObject:LBDistanceText(quantity, unit)];
    return [parts componentsJoinedByString:@" or "];
}

/* What a schedule or a reminder is for. */
static NSString *LBWorkText(NSString *task, ExpenseKind *kind, Checklist *checklist) {
    return task ?: kind.name ?: checklist.checklistName ?: @"";
}

@implementation Schedule (LBDisplay)

- (NSString *)lbWork {
    return LBWorkText(self.task, self.expenseKind, self.checklist);
}

- (NSString *)lbEvery {
    NSMutableArray *parts = [NSMutableArray array];
    if (self.intervalQuantity) [parts addObject:LBDistanceText(self.intervalQuantity, self.intervalDistanceUnit)];
    if (self.duration > 0) [parts addObject:[NSString stringWithFormat:@"%d month%@", self.duration, self.duration == 1 ? @"" : @"s"]];
    return [parts componentsJoinedByString:@" or "];
}

- (NSString *)lbNextDue {
    for (Reminder *reminder in self.reminders) {
        if (!reminder.isDeleted && !reminder.doneAt && !reminder.cancelDate) return reminder.lbDue;
    }
    return nil;
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbNextDue {
    return [NSSet setWithObject:NSStringFromSelector(@selector(reminders))];
}

@end

static NSSet<NSUUID *> *LBOverdue;

@implementation Reminder (LBDisplay)

- (NSString *)lbWork {
    return self.schedule ? self.schedule.lbWork : LBWorkText(self.task, self.expenseKind, self.checklist);
}

- (NSString *)lbDue {
    return LBDueText(self.dueDate, self.dueMileageQuantity, self.dueMileageDistanceUnit);
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbDue {
    return [NSSet setWithObjects:NSStringFromSelector(@selector(dueDate)), NSStringFromSelector(@selector(dueMileageQuantity)),
                                 NSStringFromSelector(@selector(dueMileageDistanceUnit)), nil];
}

- (NSString *)lbStatus {
    if (self.cancelDate) return [@"Cancelled " stringByAppendingString:LBDayText(self.cancelDate)];
    if (self.doneAt) {
        NSDateFormatter *said = [[NSDateFormatter alloc] init];
        said.dateStyle = NSDateFormatterShortStyle;
        said.timeStyle = NSDateFormatterNoStyle;
        NSString *done = [@"Done " stringByAppendingString:[said stringFromDate:self.doneAt]];
        return self.event ? [NSString stringWithFormat:@"%@ by %@", done, self.event.lbKind] : done;
    }
    return self.id && [LBOverdue containsObject:self.id] ? @"Overdue" : @"Open";
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbStatus {
    return [NSSet setWithObjects:NSStringFromSelector(@selector(doneAt)), NSStringFromSelector(@selector(cancelDate)),
                                 NSStringFromSelector(@selector(event)), nil];
}

- (NSInteger)lbOrder {
    return self.doneAt || self.cancelDate ? 1 : 0;
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingLbOrder {
    return [NSSet setWithObjects:NSStringFromSelector(@selector(doneAt)), NSStringFromSelector(@selector(cancelDate)), nil];
}

+ (void)lbSetOverdue:(NSSet<NSUUID *> *)overdue shown:(NSArray<Reminder *> *)shown {
    NSString *status = NSStringFromSelector(@selector(lbStatus));
    for (Reminder *reminder in shown) [reminder willChangeValueForKey:status];
    LBOverdue = [overdue copy];
    for (Reminder *reminder in shown) [reminder didChangeValueForKey:status];
}

@end

@implementation Rescheduling (LBDisplay)

- (NSString *)lbWhen {
    if (!self.madeAt) return nil;
    NSDateFormatter *said = [[NSDateFormatter alloc] init];
    said.dateStyle = NSDateFormatterShortStyle;
    said.timeStyle = NSDateFormatterShortStyle;
    return [said stringFromDate:self.madeAt];
}

- (NSString *)lbFrom {
    return LBDueText(self.fromDate, self.fromMileageQuantity, self.fromMileageDistanceUnit);
}

- (NSString *)lbBy {
    return self.madeBy.lbTitle ?: @"";
}

@end
