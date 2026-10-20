// What the app does with schedules and reminders (docs/PROCESSES.md): the
// procedures, not derivations. Each changes objects of the model in their
// context, and nothing else: no save, no request. The model's rules,
// checked at save by the generated code, say whether what a procedure
// leaves may be kept. Foundation and Core Data only: the server runs them
// (its actions, and its save of an event), and so will the mobile app,
// offline.
//
// Deterministic: what a procedure makes is named by what it is made of. Its
// id is a name-based UUID (version 5: SHA-1 of Logbook's namespace and the
// name), the name saying the source object's id and the purpose:
//
//   a schedule's first reminder   "start of <schedule id>" ("... after <n>"
//                                 when it had n reminders before)
//   a reminder's next             "next of <reminder id>"
//   a cancelled one's replacement "replacement of <reminder id>"
//   a reminder's nth rescheduling "<reminder id> rescheduled <n>"
//
// (ids written as lower-case UUIDs), so two devices that carry out the
// same procedure on the same objects, offline, make the same objects, and
// their syncs meet as one. What is chosen among several (the latest event
// of the work, the earliest of the reminders an event may close) is chosen
// by moment, then by id: never by the order objects were fetched in.
//
// Dates of the model (Date: due on, cancelled on) are days as its queries
// have them: Gregorian, in UTC (LBDay). Moments are moments.

#pragma once
#import <CoreData/CoreData.h>
#import "Record+CoreDataClass.h"
#import "Event+CoreDataClass.h"
#import "Schedule+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"
#import "Rescheduling+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"
#import "ExpenseKind+CoreDataClass.h"
#import "Checklist+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const LBProceduresErrorDomain;
typedef NS_ENUM(NSInteger, LBProceduresErrorCode) {
    // What was asked cannot be done (a done reminder cancelled, nothing to
    // move a reminder to): the message says why. Nothing was changed.
    LBProceduresErrorRefused = 1,
    // Discarding a record would delete the next reminder its closing made,
    // which has been touched since (moved, closed, noted): the owner says
    // whether to keep it (LBNextRemindersErrorKey: those reminders). Nothing
    // was changed.
    LBProceduresErrorNextReminderTouched = 2,
};
// The touched next reminders of an LBProceduresErrorNextReminderTouched.
FOUNDATION_EXPORT NSString * const LBNextRemindersErrorKey;

// The name-based UUID of a name, in Logbook's namespace
// (3dfab34a-71f4-530a-98a1-5e6711f543a6, itself uuid5(URL,
// "https://github.com/ashalkhakov/LogBook/reminders")): Python's
// uuid.uuid5(namespace, name).
FOUNDATION_EXPORT NSUUID *LBNamedUUID(NSString *name);
// The day of a moment, as the model's date() has it: its start, in UTC.
FOUNDATION_EXPORT NSDate *LBDay(NSDate *moment);
// A day so many months on, as addMonths() has it.
FOUNDATION_EXPORT NSDate *LBAddMonths(NSDate *day, NSInteger months);

@interface Event (LBProcedures)
// Whether the event does the reminder's work (its schedule's, or its own):
// a service with an item of the task, an expense of the kind, an inspection
// through the checklist.
- (BOOL)lb_doesWorkOfReminder:(Reminder *)reminder;
// Whether it may close the reminder: it does its work, it is of its
// vehicle, on or after the day the reminder was set, and the reminder is
// not cancelled.
- (BOOL)lb_mayCloseReminder:(Reminder *)reminder;
// Of two events, whether this one came first: by moment, then by id.
- (BOOL)lb_isBeforeEvent:(Event *)other;
@end

@interface Schedule (LBProcedures)
// Its reminder open (neither done nor cancelled); nil when none.
@property (nonatomic, readonly, nullable) Reminder *lb_openReminder;
// The latest event of its vehicle that did its work; nil when none.
@property (nonatomic, readonly, nullable) Event *lb_lastDoneBy;

// Its first reminder (PROCESSES.md 2), entered by the user and set at now:
// due its intervals after where it is counted from, which is the moment and
// distance given; else the latest event of the vehicle that did its work,
// its moment and its distance (the vehicle's latest at its moment where it
// has none); else now and the vehicle's latest distance. A distance where
// none is known is left out (due on a date only); refused when it would be
// due at nothing, or the schedule has an open reminder already.
- (nullable Reminder *)lb_startFrom:(nullable NSDate *)lastDone
                            mileage:(nullable NSDecimalNumber *)mileage
                               unit:(nullable DistanceUnit *)unit
                                 by:(User *)user
                                 at:(NSDate *)now
                              error:(NSError **)error;
@end

@interface Reminder (LBProcedures)
// Neither done nor cancelled.
@property (nonatomic, readonly) BOOL lb_isOpen;
// Its work: its schedule's, or its own (one of the three).
@property (nonatomic, readonly, nullable) NSString *lb_task;
@property (nonatomic, readonly, nullable) ExpenseKind *lb_expenseKind;
@property (nonatomic, readonly, nullable) Checklist *lb_checklist;
// The reminder its closing made (PROCESSES.md 5): its schedule's reminder
// of the id "next of" it; nil when there is none.
@property (nonatomic, readonly, nullable) Reminder *lb_nextReminder;
// Whether the next reminder is as its closing made it (PROCESSES.md 9):
// never moved, neither done nor cancelled, replacing and replaced by none,
// with no note and no attachment, and due on and at just what closing this
// one works out. NO when there is no next.
@property (nonatomic, readonly) BOOL lb_nextReminderUntouched;

// Closed (PROCESSES.md 4): by the event, at its moment, and at its distance
// where it has one; or with no event, by hand, at the moment given (now,
// for none) and the distance given. The event must be one that may close
// it (-lb_mayCloseReminder:). For a schedule's reminder the next is made
// (5), entered by the user, set at the moment it was done: due on the day
// done plus the schedule's months, as ReminderNextDue says, and at the
// distance done (else the vehicle's latest at that moment) plus its
// interval, in the unit done. Refused for one done or cancelled already.
- (BOOL)lb_completeByEvent:(nullable Event *)event
                        at:(nullable NSDate *)moment
                   mileage:(nullable NSDecimalNumber *)mileage
                      unit:(nullable DistanceUnit *)unit
                        by:(User *)user
                      next:(Reminder *_Nullable *_Nullable)next
                     error:(NSError **)error;

// Moved (PROCESSES.md 6) to the day or the distance given (nil: as it is),
// what it was due at before recorded with the move, made at now by the
// user. Refused for one that is not open, or a move to where it is due
// already.
- (nullable Rescheduling *)lb_rescheduleToDate:(nullable NSDate *)date
                                       mileage:(nullable NSDecimalNumber *)mileage
                                          unit:(nullable DistanceUnit *)unit
                                          note:(nullable NSString *)note
                                            by:(User *)user
                                            at:(NSDate *)now
                                         error:(NSError **)error;

// Cancelled (PROCESSES.md 8) on the day given (now's, for none); with a
// due day or distance, a replacement made that replaces it: of its
// vehicle, for its work (from its schedule, where it has one), entered by
// the user, set at now. Refused for one that is not open.
- (BOOL)lb_cancelOn:(nullable NSDate *)day
      replacementDueDate:(nullable NSDate *)dueDate
                 mileage:(nullable NSDecimalNumber *)mileage
                    unit:(nullable DistanceUnit *)unit
                      by:(User *)user
                      at:(NSDate *)now
             replacement:(Reminder *_Nullable *_Nullable)replacement
                   error:(NSError **)error;
@end

@interface Record (LBProcedures)
// Discarded, as entered in error (PROCESSES.md 9). For an event, what it
// closed is undone first: each reminder it closed is reopened, and the next
// one that closing made deleted with it, where untouched. Where one has
// been touched, keep says what the owner chose: nil, refused
// (LBProceduresErrorNextReminderTouched) before anything is changed; YES,
// the next is kept, and the reminder stays done, by hand, at the moment and
// distance it was (no longer by the event); NO, the next is deleted all the
// same, and the reminder reopened. Then the record is deleted.
- (BOOL)lb_discardKeepingNextReminders:(nullable NSNumber *)keep error:(NSError **)error;
@end

@interface NSManagedObjectContext (LBProcedures)
// Automatic completion (PROCESSES.md 4 and 9), for the events the context
// is about to save: added, or changed in what makes them do a reminder's
// work (moment, vehicle, distance, kind, checklist, items). Earliest first
// (moment, then id), each event:
// - what it closed and can no longer (it is not of the work now, of
//   another vehicle, before the day the reminder was set) is undone as in
//   discarding it, the event kept; a touched next reminder refuses it
//   (LBProceduresErrorNextReminderTouched);
// - what it closed and still does follows it: done at its moment and
//   distance now, and the untouched next due from them;
// - for each schedule of its work, and each one-off reminder of it, of its
//   vehicle, it closes one: of the reminders it may close that are open,
//   or done by a later event (whose next is untouched), the one set first.
//   One done by a later event is taken from it (its next due from this one
//   now), and that later event is then given what it may close in turn. One
//   done by hand stays as the owner said.
// So whatever the order events of the same work are added in, each closes
// the reminder that was open at its moment: the result is the same.
- (BOOL)lb_completeRemindersOfChangedEvents:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
