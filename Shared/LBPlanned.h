// What a schedule plans past its open reminder (docs/PROCESSES.md 12),
// worked out when it is shown and never saved, so a changed schedule
// plans otherwise at once: by months, the due date plus the months again
// and again; by distance, the due distance plus the interval, on the day
// the vehicle is expected to reach it by the distance it went a day over
// its last 90 days of odometer readings (an estimate); both, whichever
// comes first. Foundation and Core Data only, for both apps.

#pragma once
#import <Foundation/Foundation.h>
#import "Vehicle+CoreDataClass.h"
#import "Schedule+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

// One occurrence a schedule plans.
@interface LBPlannedReminder : NSObject
@property (nonatomic, readonly) Schedule *schedule;
// Due on (by months), a model day; due at (by distance), in a unit.
@property (nonatomic, readonly, nullable) NSDate *dueDate;
@property (nonatomic, readonly, nullable) NSDecimalNumber *dueMileage;
@property (nonatomic, readonly, nullable) DistanceUnit *dueUnit;
// The day it falls on: its due date, or the day its distance is expected,
// whichever comes first; nil when neither is known.
@property (nonatomic, readonly, nullable) NSDate *day;
// The day is the distance's, estimated.
@property (nonatomic, readonly) BOOL estimated;
@end

@interface Vehicle (LBPlanned)
// Kilometres a day over its odometer readings of the 90 days to now; nil
// with fewer than two a day or more apart, or none going up.
- (nullable NSNumber *)lbKilometresADayAsOf:(NSDate *)now;
// The day it is expected at the distance (a model day): from its latest
// reading, at that rate; nil when it cannot be told.
- (nullable NSDate *)lbDayAtMileage:(NSDecimalNumber *)mileage unit:(DistanceUnit *)unit asOf:(NSDate *)now;
@end

@interface Reminder (LBPlanned)
// The day it falls on: its due date, or the day its due distance is
// expected (*estimated YES), whichever comes first; nil when neither is
// known.
- (nullable NSDate *)lbDayAsOf:(NSDate *)now estimated:(nullable BOOL *)estimated;
@end

@interface Schedule (LBPlanned)
// What it plans after its open reminder, each counted from the one before
// as if done when due, up to the day (by distance with no day to tell,
// three at most); none without an open reminder.
- (NSArray<LBPlannedReminder *> *)lbPlannedUntil:(NSDate *)until asOf:(NSDate *)now;
@end

NS_ASSUME_NONNULL_END
