// The owner's window (MainWindow.xib): the vehicles, and of the one chosen
// its details and what is recorded of it, each record in a form of its
// kind; its schedules and reminders (LBRemindersController.h); reports. What it shows and edits is bound in the XIB to array controllers
// of the model's entities over the store's context (entity mode); this
// keeps what the forms choose from (the vehicle's drivers and tyre sets),
// shows the form of the record chosen, makes a record of the kind asked,
// saves, reverts, and asks before closing on changes not saved.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBStore, User, TyreSet, Trip, Vehicle, DistanceUnit, CostKind, Attachment, LBReportsController, LBRemindersController, LBAnswersController, Record;

NS_ASSUME_NONNULL_BEGIN

@interface LBMainWindowController : NSWindowController
- (instancetype)initWithStore:(LBStore *)store;
@property (nonatomic, readonly, strong) LBStore *store;
// What the XIB's controllers bind to.
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
@property (nonatomic, strong) IBOutlet NSArrayController *vehicles;
// The chosen vehicle's records.
@property (nonatomic, strong) IBOutlet NSArrayController *records;
// A form for each kind of record, each tab's identifier its entity's name
// ("none": no record chosen).
@property (nonatomic, strong) IBOutlet NSTabView *recordForms;
// Add's pull-down: an item for each kind of record.
@property (nonatomic, strong) IBOutlet NSPopUpButton *addRecordButton;
// The Reports tab's.
@property (nonatomic, strong) IBOutlet LBReportsController *reports;
// The Reminders tab's.
@property (nonatomic, strong) IBOutlet LBRemindersController *remindersController;
@property (nonatomic, strong) IBOutlet LBAnswersController *answersController;
// The chosen service's items (the Service form's list).
@property (nonatomic, strong) IBOutlet NSArrayController *serviceItems;
// Whom the chosen vehicle is shared with (its VehicleDrivers).
@property (nonatomic, strong) IBOutlet NSArrayController *vehicleDrivers;
// The chosen record's attachments (a receipt's photo, a policy), listed
// beside the records: opened by Open, or a double click.
@property (nonatomic, strong) IBOutlet NSArrayController *attachments;
@property (nonatomic, strong) IBOutlet NSTableView *attachmentsTable;
// The email the vehicle is to be shared with next.
@property (nonatomic, copy, nullable) NSString *shareEmail;

// The chosen record under its entity's name (none when there is no one
// record chosen): what each form's controller binds its content to.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *chosenRecords;
// What the pick lists are ordered by: their objects' titles.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;
// Who drives the chosen vehicle (its owner, and those it is shared with),
// and its tyre sets: what a record's form chooses from.
@property (nonatomic, readonly, copy) NSArray<User *> *drivers;
@property (nonatomic, readonly, copy) NSArray<TyreSet *> *tyreSets;
// Its trips, the latest first: what an income is picked for.
@property (nonatomic, readonly, copy) NSArray<Trip *> *trips;
// The kinds a service may be of: the model's (CostKind's
// lbServiceKindsInContext:).
@property (nonatomic, readonly, copy) NSArray<CostKind *> *serviceKinds;

// A new record of the chosen vehicle, of the kind of the sender's tag (an
// index in +[Record lbKinds]), filled in as far as it can be and chosen.
- (IBAction)addRecord:(nullable id)sender;
// The records chosen deleted (Remove unlinks a relationship's otherwise).
// An event saved that closed reminders is discarded on the server
// (Discard): what it closed closed by the next event or reopened, the owner
// asked when a next reminder it made has been changed since.
- (IBAction)removeRecord:(nullable id)sender;
// The chosen vehicle shared with the user of shareEmail: one of the
// logbook's, or one added by their email alone, who can then drive it.
- (IBAction)share:(nullable id)sender;
// The sharings chosen ended.
- (IBAction)unshare:(nullable id)sender;
// The attachment chosen opened, as the system opens a file of its kind
// (NSWorkspace): its content written to a file of its name first.
- (IBAction)openAttachment:(nullable id)sender;
// That file: in a folder of the attachment's own in the temporary
// directory. nil, and why, when it cannot be written (or has no content).
- (nullable NSURL *)fileOfAttachment:(Attachment *)attachment error:(NSError **)error;
// A file chosen in an open panel attached to the chosen record (Add…), or
// the chosen attachment removed (Remove): saved with the record's other
// changes.
- (IBAction)addAttachment:(nullable id)sender;
- (IBAction)removeAttachment:(nullable id)sender;
// The file at the URL attached to the record: its name and its content.
- (nullable Attachment *)attachFileAtURL:(NSURL *)url toRecord:(Record *)record error:(NSError **)error;

// The vehicle chosen, when one is.
- (nullable Vehicle *)chosenVehicle;
// The signed-in user's unit of distance, else kilometres.
- (nullable DistanceUnit *)distanceUnit;
// What is being typed kept: NO when a field holds what cannot be.
- (BOOL)commitEdits;

// One of the server's actions (Server/LBActions.h) called on the object,
// by its name, with its parameters: the changes saved first, then what the
// server changed read again. Its result (NSNull for none); nil when it was
// refused, said as a save's refusal is (lastError).
- (nullable id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(nullable NSDictionary<NSString *, id> *)parameters;
// What the server has of the chosen vehicle read again: what its actions,
// and the events saved, changed there (the reminders they closed).
- (void)readAgain;
// The changes saved; NO, said, when refused.
- (BOOL)saveChanges;
// An error said: kept in lastError, and shown unless quiet.
- (void)reportError:(NSError *)error;
// Warnings before saving: an event at no distance that would close a
// reminder of a schedule that recurs after a distance (its next would not
// be made). Said with the rules' warnings; the owner may save anyway.
- (NSArray<NSError *> *)reminderWarnings;

// Why the last save was refused (nil: it was not).
@property (nonatomic, readonly, strong, nullable) NSError *lastError;
// Said in no alert, kept in lastError: a self-test has no one to answer one.
@property (nonatomic) BOOL quiet;
// The changes sent; the rules' refusals and the warnings said.
- (IBAction)save:(nullable id)sender;
- (IBAction)revertChanges:(nullable id)sender;
// Whether it may close: nothing unsaved, or the user says so.
- (BOOL)shouldClose;
@end

// The service items' controller: a new one in the service's currency.
@interface LBServiceItemController : NSArrayController
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@end

// The vehicles' controller: a new one is the signed-in user's.
@interface LBVehicleController : NSArrayController
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@end

NS_ASSUME_NONNULL_END
