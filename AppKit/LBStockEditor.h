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

@class LBStore, Catalog, User;

NS_ASSUME_NONNULL_BEGIN

// Posted after a stock window saved or called an action: the catalog's
// object ID under LBStockCatalogKey.
extern NSNotificationName const LBStockDidChangeNotification;
extern NSString *const LBStockCatalogKey;

@interface LBStockEditor : NSWindowController

- (instancetype)initWithStore:(LBStore *)store windowNibName:(NSString *)name;
@property (nonatomic, readonly, strong) LBStore *store;
// Its own, over the store's (LBStore -newContext): what the XIB binds to.
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
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

- (IBAction)save:(nullable id)sender;
- (IBAction)revertChanges:(nullable id)sender;
// Whether it may close: its changes saved, or let go, as the user says.
- (BOOL)shouldClose;

@end

NS_ASSUME_NONNULL_END
