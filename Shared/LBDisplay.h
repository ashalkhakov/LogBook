// How the model's objects are shown: what a pick list calls each
// (lbTitle), and a record's kind, day and cost as a list of records shows
// them. Categories on the generated classes, so that windows bind to them.

#pragma once
#import <Foundation/Foundation.h>
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"
#import "VolumeUnit+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"
#import "TyreSet+CoreDataClass.h"
#import "Checklist+CoreDataClass.h"
#import "Question+CoreDataClass.h"
#import "Income+CoreDataClass.h"
#import "Schedule+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"
#import "Rescheduling+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

// What a pick list calls an object.
@protocol LBTitled <NSObject>
- (NSString *)lbTitle;
@end

@interface Vehicle (LBDisplay) <LBTitled>
@end
@interface User (LBDisplay) <LBTitled>
// What the user's costs are in: the currency they prefer, else this
// device's locale's.
- (NSString *)lbCurrency;
// What a user has not said, taken from this device: the locale's currency
// (what costs by month are reported in), the time zone (where their today
// is, and the day of what they log with no zone of its own). YES when one
// was taken.
- (BOOL)lbTakeDeviceSettings;
@end
@interface DistanceUnit (LBDisplay) <LBTitled>
@end
@interface VolumeUnit (LBDisplay) <LBTitled>
@end
@interface CostKind (LBDisplay) <LBTitled>
// The kinds a service may be of: the model's ServiceKind ('Maintenance',
// 'Repair', the reference data every store starts with), as its rule
// (ServiceKindRule) finds them in the context, by name.
+ (NSArray<CostKind *> *)lbServiceKindsInContext:(NSManagedObjectContext *)context;
@end
// What a question is answered by, as the model names them (AnswerKind).
extern NSString * const LBYesOrNo;
extern NSString * const LBAnyOf;
@interface Question (LBDisplay)
// An any-of question: the one kind with options to choose from.
@property (nonatomic, readonly) BOOL lbTakesOptions;
@end
@interface TyreSet (LBDisplay) <LBTitled>
@end
@interface Checklist (LBDisplay) <LBTitled>
@end

@interface Record (LBDisplay)
// "Fill-up", "Service", ...: its kind, as a person says it.
@property (nonatomic, readonly) NSString *lbKind;
// When: an event's moment; a tyre set's or a document's day; nil else.
@property (nonatomic, readonly, nullable) NSDate *lbDate;
// That said short: "10/19/26, 8:57 PM", a day without its time.
@property (nonatomic, readonly, nullable) NSString *lbWhen;
// What it cost: "74.10 EUR"; nil when nothing.
@property (nonatomic, readonly, nullable) NSString *lbCost;
// The model's entities a record is of, in the order Add offers them.
+ (NSArray<NSString *> *)lbKinds;
+ (NSString *)lbKindOfEntityNamed:(NSString *)name;
@end

@interface Income (LBDisplay)
// What it earned: "120.00 EUR"; nil when nothing.
@property (nonatomic, readonly, nullable) NSString *lbEarned;
@end

@interface Record (LBDisplayTitle) <LBTitled>
// "Service, 10/20/26, 2:00 PM": its kind and when (what Mark Done offers).
@end

// A day of the model (a Date: due on, cancelled on), which is a UTC day,
// said short: "6/1/27".
FOUNDATION_EXPORT NSString *_Nullable LBDayText(NSDate *_Nullable day);
// A distance said: "163000 km".
FOUNDATION_EXPORT NSString *_Nullable LBDistanceText(NSDecimalNumber *_Nullable quantity, DistanceUnit *_Nullable unit);

@interface Schedule (LBDisplay)
// What it is for: the task, the kind of expense, the checklist.
@property (nonatomic, readonly) NSString *lbWork;
// "15000 km or 12 months".
@property (nonatomic, readonly) NSString *lbEvery;
// When its open reminder is due; nil when it has none open.
@property (nonatomic, readonly, nullable) NSString *lbNextDue;
@end

@interface Reminder (LBDisplay)
@property (nonatomic, readonly) NSString *lbWork;
// "6/1/27 or 163000 km".
@property (nonatomic, readonly) NSString *lbDue;
// "Open", "Overdue", "Done 5/20/27 by Service", "Done 5/20/27" (its event deleted),
// "Cancelled 5/25/27": overdue as the model's queries said last
// (+lbSetOverdue:).
@property (nonatomic, readonly) NSString *lbStatus;
// 0 open, 1 done or cancelled: what a list sorts the open first by.
@property (nonatomic, readonly) NSInteger lbOrder;
// The reminders overdue (OverdueReminders and OverdueByMileage, run by
// whoever shows them), by id; those shown told their status changed.
+ (void)lbSetOverdue:(NSSet<NSUUID *> *)overdue shown:(NSArray<Reminder *> *)shown;
@end

@interface Rescheduling (LBDisplay)
// When it was moved, local and short.
@property (nonatomic, readonly, nullable) NSString *lbWhen;
// What it was due at before: "6/1/27 or 163000 km".
@property (nonatomic, readonly) NSString *lbFrom;
@property (nonatomic, readonly) NSString *lbBy;
@end

NS_ASSUME_NONNULL_END
