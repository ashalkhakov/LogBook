// The procedures (Shared/LBProcedures.h) as the server's OData actions,
// bound to the entities they act on, by ODataKit's mechanism: protocols
// that inherit ODataActions, adopted here, in the server's categories on
// the generated classes, so that the apps' copies of the classes know
// nothing of ODataService. The desktop app calls them (ODataOperationCall),
// online; each is carried out and saved whole, the model's rules checked
// as for any write, or refused and nothing of it saved.
//
//   POST Records(<schedule>)/Default.Start
//        {LastDoneAt?, LastDoneMileage?, LastDoneMileageUnit?}  the first reminder
//   POST Records(<schedule>)/Default.Continue
//        {Task?, ExpenseKind?, Checklist?, Interval?, IntervalUnit?,
//         Months?, Note?}                                       the schedule going on from it
//   POST Records(<reminder>)/Default.Complete
//        {Event}                                                the next, or null
//   POST Records(<reminder>)/Default.Reschedule
//        {DueDate?, DueMileage?, DueMileageUnit?, Note?}        the rescheduling
//   POST Records(<reminder>)/Default.Cancel
//        {CancelDate?, ReplacementDueDate?, ReplacementDueMileage?,
//         ReplacementDueMileageUnit?}                           the replacement, or null
//   POST Records(<record>)/Default.Discard {KeepNextReminder?}  nothing (204)
//
// A unit is its code ('km'), an event a reference ({"@odata.id":
// "Records(<id>)"}), a date a moment whose UTC day is meant. Who may call
// each (LBPermissions.h): whoever drives the vehicle closes and moves its
// reminders; its owner starts and changes its schedules, cancels its reminders and
// discards its records (403 for anyone else). A procedure's refusal is a
// 400; Discard of an event whose next reminder was touched since is a 409,
// its code NextReminderTouched and its target the reminder's id, nothing
// changed: called again with KeepNextReminder false, the next reminders
// are changed or deleted all the same. KeepNextReminder true is refused
// (400): a reminder is done only by an event.

#pragma once
#import <ODataService/ODataService.h>
#import "LBProcedures.h"

NS_ASSUME_NONNULL_BEGIN

// The code of Discard's refusal when a next reminder was touched.
FOUNDATION_EXPORT NSString * const LBNextReminderTouchedCode;   // @"NextReminderTouched"

@protocol LBScheduleActions <ODataActions>
- (nullable Reminder *)startWithLastDoneAt:(nullable NSDate *)lastDoneAt
                           lastDoneMileage:(nullable NSDecimalNumber *)lastDoneMileage
                       lastDoneMileageUnit:(nullable NSString *)lastDoneMileageUnit
                                     reply:(ODataReply *)reply;
// The schedule changed (PROCESSES.md 11): -lb_continueWithTask:..., the
// work one of the three, an expense kind and a checklist by reference.
- (nullable Schedule *)continueWithTask:(nullable NSString *)task
                            expenseKind:(nullable ExpenseKind *)expenseKind
                              checklist:(nullable Checklist *)checklist
                               interval:(nullable NSDecimalNumber *)interval
                           intervalUnit:(nullable NSString *)intervalUnit
                                 months:(nullable NSNumber *)months
                                   note:(nullable NSString *)note
                                  reply:(ODataReply *)reply;
@end

@protocol LBReminderActions <ODataActions>
- (nullable Reminder *)completeWithEvent:(nullable Event *)event reply:(ODataReply *)reply;
- (nullable Rescheduling *)rescheduleWithDueDate:(nullable NSDate *)dueDate
                                      dueMileage:(nullable NSDecimalNumber *)dueMileage
                                  dueMileageUnit:(nullable NSString *)dueMileageUnit
                                            note:(nullable NSString *)note
                                           reply:(ODataReply *)reply;
- (nullable Reminder *)cancelWithCancelDate:(nullable NSDate *)cancelDate
                         replacementDueDate:(nullable NSDate *)replacementDueDate
                      replacementDueMileage:(nullable NSDecimalNumber *)replacementDueMileage
                  replacementDueMileageUnit:(nullable NSString *)replacementDueMileageUnit
                                      reply:(ODataReply *)reply;
@end

@protocol LBRecordActions <ODataActions>
- (void)discardWithKeepNextReminder:(nullable NSNumber *)keepNextReminder reply:(ODataReply *)reply;
@end

@interface Schedule (LBActions) <LBScheduleActions>
@end

@interface Reminder (LBActions) <LBReminderActions>
@end

@interface Record (LBActions) <LBRecordActions>
@end

NS_ASSUME_NONNULL_END
