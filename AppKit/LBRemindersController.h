// The Reminders tab (MainWindow.xib): the chosen vehicle's schedules, its
// reminders (the open first, overdue marked as the model's
// OverdueReminders and OverdueByMileage say), and how the one chosen was
// moved before. Its buttons open a form beside them, each bound through an
// object controller of its own to the form object (LBReminderForm);
// saving one carries out the procedure on the server, as its action
// (Server/LBActions.h), the desktop app being online: a new schedule is
// saved and started (Start), a one-off reminder saved, a reminder moved
// (Reschedule), cancelled and maybe replaced (Cancel), or closed by an
// event of its work (Complete): a reminder is done only by an event. What the server made is read back after.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBMainWindowController, Event, ExpenseKind, Checklist, DistanceUnit;

NS_ASSUME_NONNULL_BEGIN

// What a form says: each form uses the part of it it asks for.
@interface LBReminderForm : NSObject
// The work: a task, a kind of expense or a checklist (one).
@property (nonatomic, copy, nullable) NSString *task;
@property (nonatomic, strong, nullable) ExpenseKind *expenseKind;
@property (nonatomic, strong, nullable) Checklist *checklist;
// A schedule's intervals.
@property (nonatomic, copy, nullable) NSDecimalNumber *every;
@property (nonatomic, strong, nullable) DistanceUnit *everyUnit;
@property (nonatomic, copy, nullable) NSNumber *months;
// Last done on, due on, cancelled on: a day of the calendar here.
@property (nonatomic, copy, nullable) NSDate *date;
// Last done at, due at.
@property (nonatomic, copy, nullable) NSDecimalNumber *mileage;
@property (nonatomic, strong, nullable) DistanceUnit *unit;
@property (nonatomic, copy, nullable) NSString *note;
// A cancelled reminder's replacement, due on or at.
@property (nonatomic) BOOL replace;
@property (nonatomic, copy, nullable) NSDate *replacementDate;
@property (nonatomic, copy, nullable) NSDecimalNumber *replacementMileage;
@property (nonatomic, strong, nullable) DistanceUnit *replacementUnit;
// The event that closed a reminder.
@property (nonatomic, strong, nullable) Event *event;
@end

@interface LBRemindersController : NSObject
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@property (nonatomic, strong) IBOutlet NSArrayController *schedules;
@property (nonatomic, strong) IBOutlet NSArrayController *reminders;
@property (nonatomic, strong) IBOutlet NSArrayController *reschedulings;
// The forms, each tab's identifier the form's: none, schedule, reminder,
// reschedule, cancel, done.
@property (nonatomic, strong) IBOutlet NSTabView *forms;

// What the form shown says.
@property (nonatomic, readonly, strong) LBReminderForm *form;
// The events Mark Done offers: those of the vehicle that may close the
// chosen reminder, the latest first.
@property (nonatomic, readonly, copy) NSArray<Event *> *doneEvents;
// A vehicle is chosen; an open reminder is chosen.
@property (nonatomic, readonly) BOOL hasVehicle;
@property (nonatomic, readonly) BOOL chosenOpen;

- (IBAction)newSchedule:(nullable id)sender;
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
