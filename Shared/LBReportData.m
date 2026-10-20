#import "LBReportData.h"
#import "LBDisplay.h"
#import "LBStore.h"
#import "LogbookValidation.h"
#import "FillUp+CoreDataClass.h"

@implementation LBReportData {
    NSManagedObjectContext *_context;
}

- (instancetype)initWithContext:(NSManagedObjectContext *)context {
    if ((self = [super init])) _context = context;
    return self;
}

/* A query's objects by their key, the first column of each of its rows. */
static NSDictionary *LBObjectsByKey(ORMQueryResult *result) {
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    for (NSManagedObject<LBIdentified> *object in result.objects) {
        if (object.id) byKey[object.id] = object;
    }
    return byKey;
}

/* A date as a dataset reads one: local, to the second. */
static NSString *LBDateText(NSDate *date) {
    if (!date) return nil;
    NSDateFormatter *iso = [[NSDateFormatter alloc] init];
    iso.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    return [iso stringFromDate:date];
}

- (NSArray *)costsByMonth:(NSError **)error {
    ORMQueryResult *result = [LogbookQueries costsByMonthInContext:_context error:error];
    if (!result) return nil;
    NSDictionary *vehicles = LBObjectsByKey(result);
    NSMutableArray *rows = [NSMutableArray array];
    for (NSArray *row in result.rows) {
        Vehicle *vehicle = vehicles[row[0]];
        [rows addObject:@{ @"Vehicle": vehicle.lbTitle ?: @"", @"Currency": row[1], @"Month": LBDateText(row[2]) ?: @"",
                           @"Total": row[3] }];
    }
    return rows;
}

- (NSArray *)fillUpsOfVehicle:(Vehicle *)vehicle error:(NSError **)error {
    ORMQueryResult *prices = [LogbookQueries pricePerVolumeInContext:_context error:error];
    ORMQueryResult *consumption = prices ? [LogbookQueries fullTankConsumptionInContext:_context error:error] : nil;
    if (!consumption) return nil;
    NSMutableDictionary *priceOf = [NSMutableDictionary dictionary];
    for (NSArray *row in prices.rows) priceOf[row[0]] = row[3];
    NSMutableDictionary *consumptionOf = [NSMutableDictionary dictionary];
    for (NSArray *row in consumption.rows) consumptionOf[row[0]] = row[3];

    NSMutableArray<FillUp *> *fillUps = [NSMutableArray array];
    for (Record *record in vehicle.records) {
        if ([record isKindOfClass:[FillUp class]] && !record.isDeleted) [fillUps addObject:(FillUp *)record];
    }
    [fillUps sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(timestamp)) ascending:YES] ]];
    NSMutableArray *rows = [NSMutableArray array];
    for (FillUp *fillUp in fillUps) {
        NSMutableDictionary *row = [@{ @"When": LBDateText(fillUp.timestamp) ?: @"", @"Full": fillUp.filledTheTank ? @"YES" : @"NO" }
            mutableCopy];
        row[@"Odometer"] = fillUp.mileageQuantity;
        row[@"DistanceUnit"] = fillUp.mileageDistanceUnit.code;
        row[@"Volume"] = fillUp.volumeQuantity;
        row[@"VolumeUnit"] = fillUp.volumeVolumeUnit.code;
        row[@"Cost"] = fillUp.totalAmount;
        row[@"Currency"] = fillUp.totalCurrency;
        row[@"Station"] = fillUp.station;
        row[@"Price"] = fillUp.id ? priceOf[fillUp.id] : nil;
        row[@"Consumption"] = fillUp.id ? consumptionOf[fillUp.id] : nil;
        [rows addObject:row];
    }
    return rows;
}

- (NSArray *)recordsOfVehicle:(Vehicle *)vehicle from:(NSDate *)from to:(NSDate *)to {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *start = from ? [calendar startOfDayForDate:from] : nil;
    NSDate *end = to ? [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:[calendar startOfDayForDate:to] options:0] : nil;
    NSMutableArray<Record *> *records = [NSMutableArray array];
    for (Record *record in vehicle.records) {
        NSDate *when = record.lbDate;
        if (record.isDeleted || (start && (!when || [when compare:start] == NSOrderedAscending))
            || (end && (!when || [when compare:end] != NSOrderedAscending))) continue;
        [records addObject:record];
    }
    [records sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbDate)) ascending:YES] ]];
    NSMutableArray *rows = [NSMutableArray array];
    for (Record *record in records) {
        NSMutableDictionary *row = [@{ @"Kind": record.lbKind } mutableCopy];
        row[@"When"] = LBDateText(record.lbDate);
        row[@"Cost"] = record.totalAmount;
        row[@"Currency"] = record.totalCurrency;
        row[@"Note"] = record.note;
        if ([record isKindOfClass:[Event class]]) row[@"Driver"] = ((Event *)record).driver.lbTitle;
        [rows addObject:row];
    }
    return rows;
}

+ (NSString *)JSONOfRows:(NSArray *)rows {
    NSMutableArray *plain = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSMutableDictionary *each = [NSMutableDictionary dictionary];
        for (NSString *field in row) {
            id value = row[field];
            /* Decimals as JSON numbers, which is what they are. */
            each[field] = [value isKindOfClass:[NSDecimalNumber class]] ? @([value doubleValue]) : value;
        }
        [plain addObject:each];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:plain options:NSJSONWritingSortedKeys error:NULL];
    return [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"[]";
}

@end
