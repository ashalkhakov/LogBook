// What the phone shows of a vehicle, from the store it has (online or not):
// its timeline, its reminders in the order they matter, and a few numbers.
// The model's queries (LogbookQueries) where the model says what a number
// is: consumption at full tanks, overdue. Foundation and Core Data only.

#pragma once
#import <CoreData/CoreData.h>
#import "Vehicle+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

// A month of the timeline: "October 2026", its records newest first.
@interface LBMonth : NSObject
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSArray<Record *> *records;
@end

@interface LBVehicleSummary : NSObject

- (instancetype)initWithVehicle:(Vehicle *)vehicle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly) Vehicle *vehicle;

// What happened to it (its events, documents and tyre sets: not its
// schedules and reminders), newest first, by month.
- (NSArray<LBMonth *> *)months;

// Its reminders: open ones first, the overdue first among them (as the
// model's OverdueReminders and OverdueByMileage say), then by when they are
// due; then those done or cancelled, the latest first.
- (NSArray<Reminder *> *)reminders;
// Of those, the overdue (asked when -reminders was).
- (BOOL)isOverdue:(Reminder *)reminder;

// "6.42 L/100 km": at the latest full tank after another
// (FullTankConsumption); nil: none yet.
- (nullable NSString *)consumption;
// "123.40 EUR": what its records of this month cost, by currency; nil:
// nothing.
- (nullable NSString *)costThisMonth;
// "Oil change: 6/1/27 or 163000 km": the open reminder due soonest; nil:
// none.
- (nullable NSString *)nextDue;

@end

NS_ASSUME_NONNULL_END
