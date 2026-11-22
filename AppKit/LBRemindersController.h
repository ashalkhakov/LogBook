// The Reminders tab (MainWindow.xib): the chosen vehicle's schedules, its
// reminders (the open first, overdue marked as the model's
// OverdueReminders and OverdueByMileage say), and how the one chosen was
// moved before. Its buttons open a form beside them, each the view of the
// model's form (LBFormValues: its object controller <Name>Form):
// SetUpSchedule, a schedule saved by its form and started (the server's
// Start, from when it was last done); SetReminder, a one-off saved by its
// form. The rest stand for the server's procedures, their values submitted
// to its action (ORMFormSession's submitting), the desktop app being online
// or doing them here offline: RescheduleReminder (Reschedule),
// CancelReminder (Cancel, maybe replaced), MarkReminderDone (Complete: a
// reminder is done only by an event, one of those that may close it), and
// ChangeSchedule: a schedule is changed by going on in another, the
// server's Continue: its past as it was, its open reminder due anew by the
// change (cancelled instead when moved or noted by hand, said first). What
// the server made is read back after. The schedules listed are those in
// force.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBMainWindowController, LBFormValues;

NS_ASSUME_NONNULL_BEGIN

@interface LBRemindersController : NSObject
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@property (nonatomic, strong) IBOutlet NSArrayController *schedules;
@property (nonatomic, strong) IBOutlet NSArrayController *reminders;
@property (nonatomic, strong) IBOutlet NSArrayController *reschedulings;
// The forms, each tab's identifier the form's: none, schedule, change,
// reminder, reschedule, cancel, done.
@property (nonatomic, strong) IBOutlet NSTabView *forms;

// The form shown, its tab's object controller's content: nil but the one.
@property (nonatomic, readonly, strong, nullable) LBFormValues *scheduleForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *changeForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *reminderForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *rescheduleForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *cancelForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *doneForm;
// Whether the reminder cancelled is replaced: its replacement's due asked.
@property (nonatomic) BOOL replaces;
// A vehicle is chosen; an open reminder is chosen; a schedule is chosen.
@property (nonatomic, readonly) BOOL hasVehicle;
@property (nonatomic, readonly) BOOL chosenOpen;
@property (nonatomic, readonly) BOOL scheduleChosen;

- (IBAction)newSchedule:(nullable id)sender;
- (IBAction)editSchedule:(nullable id)sender;
- (IBAction)newReminder:(nullable id)sender;
- (IBAction)reschedule:(nullable id)sender;
- (IBAction)cancelReminder:(nullable id)sender;
- (IBAction)markDone:(nullable id)sender;
// The form shown carried out; or put away.
- (IBAction)saveForm:(nullable id)sender;
- (IBAction)closeForm:(nullable id)sender;

// The vehicle chosen changed, or what the server has of it was read again:
// overdue asked again, the lists arranged.
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
