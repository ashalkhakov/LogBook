// A vehicle's days, as a calendar shows them (docs/PROCESSES.md 12): its
// reminders, done (by what, whose; late or not), cancelled, open (due,
// overdue) and planned (worked out, estimated where by distance); and its
// records, each on its day. Days are the model's, UTC days.

#pragma once
#import <Foundation/Foundation.h>
#import "Vehicle+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LBCalendarKind) {
    LBCalendarDone,
    LBCalendarCancelled,
    LBCalendarOpen,
    LBCalendarOverdue,
    LBCalendarPlanned,
    LBCalendarRecord,
};

@interface LBCalendarEntry : NSObject
// The day it falls on, a model day.
@property (nonatomic, readonly) NSDate *day;
@property (nonatomic, readonly) LBCalendarKind kind;
// "Done", "Cancelled", "Open", "Overdue", "Planned", or the record's kind.
@property (nonatomic, readonly) NSString *kindText;
// What: the reminder's work, the record's kind.
@property (nonatomic, readonly) NSString *title;
// The rest, said short: "by Service, Anna; late", "at 164000 km, estimated".
@property (nonatomic, readonly) NSString *detail;
// Its day estimated from a distance.
@property (nonatomic, readonly) BOOL estimated;
// The reminder or record; nil for one planned.
@property (nonatomic, readonly, nullable) id object;
// The day said short, for a list: "2/28/27".
@property (nonatomic, readonly) NSString *dayText;
@end

@interface LBCalendar : NSObject
// The vehicle's entries on the days from the first up to (not including)
// the last, by day, reminders before records; as of now (what is overdue,
// what is planned, how far the vehicle goes a day).
+ (NSArray<LBCalendarEntry *> *)entriesOfVehicle:(nullable Vehicle *)vehicle from:(NSDate *)from to:(NSDate *)to asOf:(NSDate *)now;
@end

NS_ASSUME_NONNULL_END
