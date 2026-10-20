// What the reports show (Reports/*.rdl), as rows a report's dataset reads:
// dictionaries of its fields' names and values (strings, numbers; a date as
// "2026-10-20T08:30:00", in this machine's time zone). Each from the model's
// queries (LogbookQueries) or its records, run in the store's context.

#pragma once
#import <CoreData/CoreData.h>

@class Vehicle;

NS_ASSUME_NONNULL_BEGIN

@interface LBReportData : NSObject

- (instancetype)initWithContext:(NSManagedObjectContext *)context NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// What each vehicle cost each month, in its owner's currency, the latest
// month first (CostsByMonth): Vehicle, Currency, Month (its first day),
// Total. None for a vehicle whose owner prefers no currency.
- (nullable NSArray<NSDictionary<NSString *, id> *> *)costsByMonth:(NSError **)error;

// A vehicle's fill-ups, oldest first: When, Odometer, DistanceUnit,
// Volume, VolumeUnit, Cost, Currency, Station, Full (YES or NO), Price
// (PricePerVolume: a unit's, in its currency) and Consumption (at a full
// tank after another, per 100 of its distance unit: FullTankConsumption).
- (nullable NSArray<NSDictionary<NSString *, id> *> *)fillUpsOfVehicle:(Vehicle *)vehicle error:(NSError **)error;

// A vehicle's records on the days from..to (either nil: open), oldest
// first: Kind, When, Cost, Currency, Driver, Note.
- (NSArray<NSDictionary<NSString *, id> *> *)recordsOfVehicle:(Vehicle *)vehicle
                                                          from:(nullable NSDate *)from
                                                            to:(nullable NSDate *)to;

// Rows as the JSON a dataset binds.
+ (NSString *)JSONOfRows:(NSArray<NSDictionary<NSString *, id> *> *)rows;

@end

NS_ASSUME_NONNULL_END
