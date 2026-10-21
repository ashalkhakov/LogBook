// Logbook on iOS: a driver's logbook in the pocket, offline first. What the
// phone does is what a driver (and the owner) does on the road: log a
// fill-up fast, a service, an expense, a trip, a meter reading, an
// inspection; see the vehicle's timeline and reminders, move one, cancel
// one; the owner adds a vehicle and shares it. Managing and reporting are
// the desktop app's.
//
// UIKit, programmatic controllers, over the shared offline store
// (Shared/LBLocalStore.h), as SimpleNotes' iOS app is over its own:
//
//   LBSignInViewController   the server's address and who you are
//   LBMainViewController     a tab bar (Timeline, Reminders, Vehicle) and
//                            the + over it, which logs a record
//   LBTimelineViewController the chosen vehicle's records, newest first,
//                            by month
//   LBRemindersViewController its reminders: open and overdue first
//   LBVehicleViewController  the vehicle chosen, its numbers, sharing (the
//                            owner's), sync and its conflicts, the account
//   LBRecordFormViewController  a record's form: a new one, or one to edit
//   LBConflictsViewController   pending conflicts, each settled here

#pragma once
#import <UIKit/UIKit.h>
#import "LBLocalStore.h"
#import "Vehicle+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

// Defaults: the server's root, the email with no sign-in, the vehicle chosen.
FOUNDATION_EXPORT NSString * const LBServerDefaultsKey;    // @"LBServer"
FOUNDATION_EXPORT NSString * const LBEmailDefaultsKey;     // @"LBEmail"
FOUNDATION_EXPORT NSString * const LBVehicleDefaultsKey;   // @"LBVehicle"

// Something the controllers share: the store, the vehicle chosen.
FOUNDATION_EXPORT NSNotificationName const LBPhoneVehicleDidChangeNotification;

@interface LBPhone : NSObject
- (instancetype)initWithStore:(LBLocalStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly) LBLocalStore *store;
// The vehicles the user drives (owns, or was shared), by name.
- (NSArray<Vehicle *> *)vehicles;
// The one chosen (kept across launches); the first, when none is.
@property (nonatomic, strong, nullable) Vehicle *vehicle;
// Whether the user owns it: who shares it, cancels its reminders.
- (BOOL)ownsVehicle;
@end

@class LBSignInViewController;

@protocol LBSignInViewControllerDelegate <NSObject>
// Connected: the server's root, signed in as it asks; email, the one given
// for a server that asks for no one.
- (void)signInViewController:(LBSignInViewController *)controller didConnect:(ODataSignIn *)signIn email:(nullable NSString *)email;
@end

@interface LBSignInViewController : UITableViewController <ODataSignInDelegate, UITextFieldDelegate>
@property (nonatomic, weak, nullable) id<LBSignInViewControllerDelegate> delegate;
// What is typed (the self-test types there too).
@property (nonatomic, copy) NSString *serverText;
@property (nonatomic, copy) NSString *emailText;
// The status line: "Asking …", a code to enter, why it failed.
@property (nonatomic, readonly, copy) NSString *status;
- (IBAction)connect:(nullable id)sender;
@end

@interface LBMainViewController : UITabBarController
- (instancetype)initWithPhone:(LBPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@property (nonatomic, readonly) LBPhone *phone;
// The + : what may be logged, fill-up first.
+ (NSArray<NSString *> *)loggedKinds;
- (IBAction)log:(nullable id)sender;
// A new record of the kind (an entity's name), its form shown.
- (nullable UIViewController *)logKind:(NSString *)entityName;
// Signed out: the app's delegate shows the sign-in again.
@property (nonatomic, weak, nullable) id signOutTarget;
@property (nonatomic, nullable) SEL signOutAction;
@end

@interface LBTimelineViewController : UITableViewController
- (instancetype)initWithPhone:(LBPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
// "October 2026: Service, Fill-up": each month and its records' kinds, as
// shown.
- (NSArray<NSString *> *)shownRows;
@end

@interface LBRemindersViewController : UITableViewController
- (instancetype)initWithPhone:(LBPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
- (NSArray<Reminder *> *)shownReminders;
// "Oil change — Overdue", as each row says it.
- (NSArray<NSString *> *)shownRows;
// Moved to the day (or the distance), with why; NO and the rule's words.
- (BOOL)reschedule:(Reminder *)reminder toDate:(nullable NSDate *)day mileage:(nullable NSDecimalNumber *)mileage
              note:(nullable NSString *)note problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
// Cancelled today (the owner's).
- (BOOL)cancel:(Reminder *)reminder problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
@end

// What signing out with changes waiting does, as the warning offers.
typedef NS_ENUM(NSInteger, LBSignOutChoice) {
    // Synced first (sync off too), then signed out if nothing is left to
    // lose; warned again with what is.
    LBSignOutSyncFirst,
    // Signed out, what waits lost.
    LBSignOutAnyway,
    LBSignOutCancel,
};

@interface LBVehicleViewController : UITableViewController
- (instancetype)initWithPhone:(LBPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
// Its sections' titles, as shown: "Sharing" only for the owner.
- (NSArray<NSString *> *)shownSections;
- (BOOL)showsSharing;
// The vehicle shared with the person of the email (a user of the logbook,
// made when there is none), saved; NO and why.
- (BOOL)shareWithEmail:(NSString *)email problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
// Sync's switch.
- (void)setSyncOn:(BOOL)on;
// A new vehicle's form.
- (IBAction)addVehicle:(nullable id)sender;
// Sign Out: at once with nothing waiting; else the warning shown first.
- (IBAction)signOut:(nullable id)sender;
// The warning, when signing out would lose something (the changes not
// sent, the pending conflicts: LBLocalStore's changesLostOnSignOut), how
// many said: Sync Now, Sign Out Anyway (destructive), Cancel. nil: nothing
// would be lost.
- (nullable UIAlertController *)signOutWarning;
// What the warning's buttons do.
- (void)signOutChoosing:(LBSignOutChoice)choice;
@end

@class LBRecordFormViewController;

// How large a photo is kept, its longest side in pixels.
FOUNDATION_EXPORT CGFloat const LBPhotoLongestSide;

@protocol LBRecordFormDelegate <NSObject>
@optional
- (void)recordFormDidSave:(LBRecordFormViewController *)form;
@end

// A record's form (or a vehicle's): its fields, a service's items, an
// inspection's answers, its photos. What is typed goes into the object as
// it is typed; Save does what the server does before saving, and says the
// deontic rules first (Save Anyway), the rules that refuse after (each as
// the model says it). Cancel takes back what was typed.
@interface LBRecordFormViewController : UITableViewController <UITextFieldDelegate, UIImagePickerControllerDelegate,
                                                                UINavigationControllerDelegate>
- (instancetype)initWithObject:(NSManagedObject *)object phone:(LBPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
// A new record of the kind for the chosen vehicle: now, by the user, in the
// user's units and currency.
+ (nullable NSManagedObject *)newRecordOfKind:(NSString *)entityName phone:(LBPhone *)phone;
// A new vehicle, the user's.
+ (NSManagedObject *)newVehicleForPhone:(LBPhone *)phone;
@property (nonatomic, readonly) NSManagedObject *object;
@property (nonatomic, weak, nullable) id<LBRecordFormDelegate> delegate;
// The fields, by their titles as shown ("Odometer", "Volume"...).
- (NSArray<NSString *> *)fieldTitles;
// What a user types into one, or picks: text for a text or number field,
// an NSDate, an NSNumber for a switch, an object for a choice.
- (BOOL)enter:(nullable id)value intoField:(NSString *)title;
// A service's item (a task and what it cost).
- (void)addItemTask:(NSString *)task cost:(NSDecimalNumber *)cost;
// An inspection's answer to the question.
- (void)answer:(BOOL)yes toQuestionAt:(NSUInteger)index;
// A receipt's photo (JPEG data), as one picked: the attachment's content.
- (void)addImageData:(NSData *)jpeg;
// A photo taken or chosen (UIImagePickerControllerDelegate's): kept as a
// JPEG, its longest side no more than LBPhotoLongestSide.
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info;
// Saved: NO when warnings stopped it (unless ignored) or a rule refused.
- (BOOL)saveIgnoringWarnings:(BOOL)ignoring;
@property (nonatomic, readonly, copy) NSArray<NSString *> *warnings;
@property (nonatomic, readonly, copy) NSArray<NSString *> *problems;
- (IBAction)save:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;
@end

@interface LBConflictsViewController : UITableViewController
- (instancetype)initWithPhone:(LBPhone *)phone NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibName bundle:(nullable NSBundle *)bundle NS_UNAVAILABLE;
// "Fill-up: station — mine Aral, theirs Esso"
- (NSArray<NSString *> *)shownRows;
- (void)keepTheirs:(LBPendingConflict *)conflict;
- (BOOL)keepMine:(LBPendingConflict *)conflict problems:(NSArray<NSString *> *_Nullable *_Nullable)problems;
// The object's form, the conflict settled once it is saved.
- (nullable LBRecordFormViewController *)editByHand:(LBPendingConflict *)conflict;
@end

NS_ASSUME_NONNULL_END
