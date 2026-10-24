// The stock window (StockWindow.xib; docs/STOCK.md): a catalog chosen, and
// in its tabs what the design has: its items, each with its quantities,
// holdings, recipe and history, and its stock adjusted, moved and
// assembled from it. What it shows and edits is bound in the XIB to array
// controllers over the store's context, as the logbook's window is; what
// changes stock is the server's actions (Server/LBStockActions.h), the
// changes saved first.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBStore, Catalog, StockItem, Location, Category, Supplier;

NS_ASSUME_NONNULL_BEGIN

@interface LBStockWindowController : NSWindowController
- (instancetype)initWithStore:(LBStore *)store;
@property (nonatomic, readonly, strong) LBStore *store;
// What the XIB's controllers bind to.
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;
@property (nonatomic, strong) IBOutlet NSArrayController *catalogs;
// The chosen catalog's items, as the search leaves them.
@property (nonatomic, strong) IBOutlet NSArrayController *items;
// The chosen item's holdings, recipe and moves.
@property (nonatomic, strong) IBOutlet NSArrayController *holdings;
@property (nonatomic, strong) IBOutlet NSArrayController *kitLines;
@property (nonatomic, strong) IBOutlet NSArrayController *moves;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;
@property (nonatomic, strong) IBOutlet NSSearchField *itemSearch;

// The orders lists are in: by title, by name, the latest first.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byName;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *latestFirst;
// What the chosen catalog's forms choose from: its categories, its
// suppliers, its locations (every warehouse's), the items a kit may take
// (all but the chosen one), and the reasons for an adjustment.
@property (nonatomic, readonly, copy) NSArray<Category *> *categories;
@property (nonatomic, readonly, copy) NSArray<Supplier *> *suppliers;
@property (nonatomic, readonly, copy) NSArray<Location *> *locations;
@property (nonatomic, readonly, copy) NSArray<StockItem *> *components;
@property (nonatomic, readonly, copy) NSArray<NSString *> *reasons;

// What moving stock is about to do, typed and chosen under the item: how
// many (less than none, an adjustment out), where (at, or from), where
// to, and why.
@property (nonatomic, copy, nullable) NSString *stockQuantity;
@property (nonatomic, strong, nullable) Location *stockAt;
@property (nonatomic, strong, nullable) Location *stockTo;
@property (nonatomic, copy, nullable) NSString *stockReason;

// The catalog chosen, and the item, when one is.
- (nullable Catalog *)chosenCatalog;
- (nullable StockItem *)chosenItem;

// A new catalog of the user's, named "New Catalog" to be typed over, with
// its warehouse and location; chosen.
- (IBAction)newCatalog:(nullable id)sender;
- (IBAction)addItem:(nullable id)sender;
- (IBAction)removeItem:(nullable id)sender;
// The items listed narrowed to those whose name, tag or description has
// what the search field says.
- (IBAction)search:(nullable id)sender;
- (IBAction)addKitLine:(nullable id)sender;
- (IBAction)removeKitLine:(nullable id)sender;
// The chosen item's stock: adjusted at stockAt by stockQuantity for
// stockReason; moved from stockAt to stockTo; so many batches assembled,
// or taken apart, at stockAt. Each the server's action, saved first.
- (IBAction)adjust:(nullable id)sender;
- (IBAction)transfer:(nullable id)sender;
- (IBAction)assemble:(nullable id)sender;
- (IBAction)disassemble:(nullable id)sender;

// One of the server's actions (Server/LBStockActions.h) called on the
// object, the changes saved first, what it changed read again. Its result;
// nil when refused, said (lastError).
- (nullable id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(nullable NSDictionary<NSString *, id> *)parameters;
// What the server has read again.
- (void)readAgain;
- (BOOL)commitEdits;
- (BOOL)saveChanges;
@property (nonatomic, readonly, strong, nullable) NSError *lastError;
// Said in no alert, kept in lastError: a self-test has no one to answer one.
@property (nonatomic) BOOL quiet;
- (IBAction)save:(nullable id)sender;
- (IBAction)revertChanges:(nullable id)sender;
- (BOOL)shouldClose;
@end

// The items' controller: a new one made now, named to be typed over.
@interface LBStockItemController : NSArrayController
@property (nonatomic, weak) IBOutlet LBStockWindowController *windowController;
@end

// The recipe's controller: a new line takes one of its component.
@interface LBKitLineController : NSArrayController
@end

NS_ASSUME_NONNULL_END
