// A stock window (docs/STOCK.md) over a context of its own. What it shows
// it reads by its own fetches (-readAgain): when it opens, and again
// whenever stock of its catalog changes (LBStockDidChangeNotification,
// posted by any stock window after a save or an action). What it edits it
// saves itself; what changes stock is the server's actions
// (Server/LBStockActions.h), its own changes saved first.
//
// The windows: the catalog's lists (LBStockWindowController), an item
// (LBStockItemWindowController), an order (LBStockOrderWindowController),
// a count (LBStockCountWindowController), the catalog's settings
// (LBCatalogSettingsWindowController).

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>
#import "LBScreen.h"

@class LBStore, Catalog, User, LBTask, LBTasks, LBFormValues, LBPendingSubmission, Move;

NS_ASSUME_NONNULL_BEGIN

// Posted after a stock window saved or called an action: the catalog's
// object ID under LBStockCatalogKey.
extern NSNotificationName const LBStockDidChangeNotification;
extern NSString *const LBStockCatalogKey;

@class LBFieldIssues;

@interface LBStockEditor : LBScreen

- (instancetype)initWithStore:(LBStore *)store nibName:(NSString *)name;
@property (nonatomic, readonly, strong) LBStore *store;
// Its own, over the store's (LBStore -newContext): what the XIB binds to.
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
// The rules what is edited breaks, at its fields.
@property (nonatomic, readonly, strong, nullable) LBFieldIssues *fieldIssues;
// The catalog it is of, in its context; nil, none yet.
@property (nonatomic, strong, nullable) Catalog *catalog;
// The user, in its context.
@property (nonatomic, readonly, nullable) User *user;

// What it shows read again, by its own fetches: each window's. Called
// when its window has loaded, and when stock of its catalog changes.
- (void)readAgain;
// The objects of the class the predicate takes, sorted so, from the
// server's rows now: any of them already in the context read again from
// those rows (their own changes kept).
- (NSArray *)fetch:(Class)cls where:(nullable NSPredicate *)predicate sortedBy:(nullable NSArray<NSSortDescriptor *> *)order;
// The object in this context: another context's, by its ID.
- (nullable id)own:(nullable NSManagedObject *)object;

// What the lists are in: by title.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;

// Its edits committed: those of the first responder, and of the array
// controllers it names (each window's -editedControllers).
- (BOOL)commitEdits;
- (NSArray<NSArrayController *> *)editedControllers;
// Its changes saved (an amount typed with no currency given the
// catalog's); stock said to have changed. NO, said, when refused.
- (BOOL)saveChanges;
// Each line, item and kit's money given the catalog's currency where it has
// none, as saving does.
- (void)completeMoney;
// One of the server's actions called on the object, its changes saved
// first; stock said to have changed. Its result; nil when refused, said.
- (nullable id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(nullable NSDictionary<NSString *, id> *)parameters;
// Said in an alert, kept in lastError; in no alert when quiet (a self-test
// has no one to answer one).
- (void)reportError:(nullable NSError *)error;
- (void)refuse:(NSString *)why;
@property (nonatomic, readonly, strong, nullable) NSError *lastError;
@property (nonatomic) BOOL quiet;
// What was typed as a quantity: a decimal number; nil, said, otherwise.
- (nullable NSDecimalNumber *)typed:(nullable NSString *)text;

// Its forms (LBFormValues.h; ORMKit's docs/FORMS.md): the model's form of
// the name opened on the object as the context has it now, given what it
// comes with, saved as the store saves; nil, and why said, where it does
// not open. A save refused said under its controls where the view has
// them, the rest in the form's words.
- (nullable LBFormValues *)valuesOfForm:(NSString *)name given:(NSDictionary *)given object:(NSManagedObject *)object;
- (void)refuseForm:(LBFormValues *)values error:(nullable NSError *)error under:(NSView *)view;

// The process's task it was opened for (LBTasksWindowController.h), named
// in its title; nil: no task. What its processes are about: an order's,
// a count's id (each window's -businessKey). A step's form saved in its
// sheet, then its instance submitted to the open task of it about that
// (this one, or found), which the server's process goes on with
// (Server/LBWorkflow.h); the tasks are asked again. Offline first, where
// the server cannot be reached, the step waits, saved (Go > Tasks:
// waiting), and is submitted after a sync. NO, said, where refused.
@property (nonatomic, strong, nullable) LBTask *task;
@property (nonatomic, strong, nullable) LBTasks *tasks;
@property (nonatomic, readonly, strong, nullable) LBPendingSubmission *waiting;
- (nullable NSString *)businessKey;
- (BOOL)submitForm:(LBFormValues *)values sheet:(NSWindow *)sheet;
- (BOOL)wait:(NSString *)formName about:(NSString *)about instance:(NSString *)instance task:(nullable NSString *)taskName;
- (void)stepDone:(NSString *)form;

// What made the move shown, in its screen: its purchase or sale (a
// receipt's, a shipment's, a line's, a return's), its count; a part fitted
// or taken off, its record on the vehicle's page. NO, and a beep, where
// nothing else made it (an adjustment, a transfer, an assembly: the item's
// own).
- (BOOL)openSourceOfMove:(nullable Move *)move;

- (IBAction)save:(nullable id)sender;
- (IBAction)revertChanges:(nullable id)sender;
// Whether it may close: its changes saved, or let go, as the user says.
- (BOOL)shouldClose;

@end

NS_ASSUME_NONNULL_END
