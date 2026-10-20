// The owner's window (MainWindow.xib): the vehicles, and of the one chosen
// its details and what is recorded of it, each record in a form of its
// kind. What it shows and edits is bound in the XIB to array controllers
// of the model's entities over the store's context (entity mode); this
// keeps what the forms choose from (the vehicle's drivers and tyre sets),
// shows the form of the record chosen, makes a record of the kind asked,
// saves, reverts, and asks before closing on changes not saved.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBStore, User, TyreSet, LBReportsController;

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
// Whom the chosen vehicle is shared with (its VehicleDrivers).
@property (nonatomic, strong) IBOutlet NSArrayController *vehicleDrivers;
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

// A new record of the chosen vehicle, of the kind of the sender's tag (an
// index in +[Record lbKinds]), filled in as far as it can be and chosen.
- (IBAction)addRecord:(nullable id)sender;
// The records chosen deleted (Remove unlinks a relationship's otherwise).
- (IBAction)removeRecord:(nullable id)sender;
// The chosen vehicle shared with the user of shareEmail: one of the
// logbook's, or one added by their email alone, who can then drive it.
- (IBAction)share:(nullable id)sender;
// The sharings chosen ended.
- (IBAction)unshare:(nullable id)sender;

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

// The vehicles' controller: a new one is the signed-in user's.
@interface LBVehicleController : NSArrayController
@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@end

NS_ASSUME_NONNULL_END
