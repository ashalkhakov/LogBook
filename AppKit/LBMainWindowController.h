// The owner's window (MainWindow.xib): the vehicles, and of the one chosen
// its details and what is recorded of it, each record in a form of its
// kind; its schedules and reminders (LBRemindersController.h); reports. What it shows and edits is bound in the XIB to array controllers
// of the model's entities over the store's context (entity mode); this
// keeps what the forms choose from (the vehicle's drivers and tyre sets),
// shows the form of the record chosen, makes a record of the kind asked,
// saves, reverts, and asks before closing on changes not saved.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBStore, User, TyreSet, Trip, Vehicle, DistanceUnit, CostKind, Attachment, LBReportsController, LBRemindersController, LBAnswersController, LBCalendarController, Record;

@class LBPartsPanelController;

@class LBImport, LBFieldIssues;

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
@property (nonatomic, strong) IBOutlet LBCalendarController *calendarController;
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
// record chosen): what each form's controller binds its content to. A
// fill-up is there as the model's RecordFillUp form has it (LBFormValues:
// its values, written through to the record; its choices; saved by the
// form, a refusal said under the field it is about).
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
// What a vehicle may be (the model's VehicleKind): its Kind pop-up's.
@property (nonatomic, readonly, copy) NSArray<NSString *> *vehicleKinds;
// The chosen component's wear, said: "1200 km since it was fitted".
@property (nonatomic, readonly, copy) NSString *componentWear;

// File > Import…: another app's export (LBImport.h) through the model's
// forms: Drivvo's CSV into the chosen vehicle, MainTrack's store into
// vehicles of its own (its bikes). What the export says that
// Logbook has no place for is shown first (ImportSummary.xib), and nothing
// is made unless the user says Import.
- (IBAction)importRecords:(nullable id)sender;
// The same of a file, with nothing asked when quiet (the self-test): the
// left out taken. Made and passed over said; NO and why where refused.
- (BOOL)importFile:(NSURL *)file intoVehicle:(nullable Vehicle *)vehicle made:(NSUInteger *_Nullable)made skipped:(NSUInteger *_Nullable)skipped
             error:(NSError **)error;
// The same, MainTrack's parts into the catalog named (nil: "Bike parts").
- (BOOL)importFile:(NSURL *)file intoVehicle:(nullable Vehicle *)vehicle catalogNamed:(nullable NSString *)catalog
              made:(NSUInteger *_Nullable)made skipped:(NSUInteger *_Nullable)skipped error:(NSError **)error;
// File > Import from InvenTree…: its address and an API token asked
// (InvenTreeConnect.xib; the address kept in the defaults, the token in
// the system's secret store), its stock read, then as an export: what
// Logbook has no place for shown, into the catalog the user names.
- (IBAction)importFromInvenTree:(nullable id)sender;
// An import read already (a file's, InvenTree's) into the vehicle (its
// stock into the catalog named): made and passed over said.
- (BOOL)importRecordsOf:(LBImport *)import intoVehicle:(nullable Vehicle *)vehicle catalogNamed:(nullable NSString *)catalog
                   made:(NSUInteger *_Nullable)made skipped:(NSUInteger *_Nullable)skipped error:(NSError **)error;
// InvenTreeConnect.xib's view and its fields, the owner's while shown.
@property (nonatomic, strong, nullable) IBOutlet NSView *inventreeConnectView;
@property (nonatomic, strong, nullable) IBOutlet NSTextField *inventreeAddressField;
@property (nonatomic, strong, nullable) IBOutlet NSSecureTextField *inventreeTokenField;
// The rules the shown record or vehicle breaks, at its fields.
@property (nonatomic, readonly, strong, nullable) LBFieldIssues *fieldIssues;
// ImportSummary.xib's view and its list, the owner's while it is shown.
@property (nonatomic, strong, nullable) IBOutlet NSView *importSummaryView;
@property (nonatomic, strong, nullable) IBOutlet NSTextView *importSummaryText;
// Its catalog field: where MainTrack's parts or InvenTree's stock go (a
// catalog of the user's, or a new one's name); hidden for an export that
// makes no stock.
@property (nonatomic, strong, nullable) IBOutlet NSComboBox *importCatalogField;
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
// The chosen service's or tyre change's parts, in a panel of their own
// (LBPartsPanelController); its window while it is open.
- (IBAction)showParts:(nullable id)sender;
@property (nonatomic, readonly, strong, nullable) LBPartsPanelController *partsPanel;
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
