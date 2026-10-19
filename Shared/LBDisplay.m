#import "LBDisplay.h"
#import "Event+CoreDataClass.h"
#import "Document+CoreDataClass.h"

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
@end

@implementation DistanceUnit (LBDisplay)
- (NSString *)lbTitle { return self.code ?: @""; }
@end

@implementation VolumeUnit (LBDisplay)
- (NSString *)lbTitle { return self.code ?: @""; }
@end

@implementation CostKind (LBDisplay)
- (NSString *)lbTitle { return self.name ?: @""; }
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
