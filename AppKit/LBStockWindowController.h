// The stock window (StockWindow.xib; docs/STOCK.md): a catalog chosen, and
// in its tabs what the design has: its items, each with its quantities,
// holdings, recipe and history, and its stock adjusted, moved and
// assembled from it. What it shows and edits is bound in the XIB to array
// controllers over the store's context, as the logbook's window is; what
// changes stock is the server's actions (Server/LBStockActions.h), the
// changes saved first.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBStore, Catalog, StockItem, Location, Category, Supplier, Customer;

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
// The Setup tab's: the catalog's warehouses, the chosen one's locations,
// the catalog's categories and contacts.
@property (nonatomic, strong) IBOutlet NSArrayController *warehouses;
@property (nonatomic, strong) IBOutlet NSArrayController *warehouseLocations;
@property (nonatomic, strong) IBOutlet NSArrayController *catalogCategories;
@property (nonatomic, strong) IBOutlet NSArrayController *contacts;
// The Sales and Purchases tabs': the catalog's orders, the chosen one's
// lines, and its shipments or receipts.
@property (nonatomic, strong) IBOutlet NSArrayController *saleOrders;
@property (nonatomic, strong) IBOutlet NSArrayController *saleLines;
@property (nonatomic, strong) IBOutlet NSArrayController *shipments;
@property (nonatomic, strong) IBOutlet NSArrayController *purchaseOrders;
@property (nonatomic, strong) IBOutlet NSArrayController *purchaseLines;
@property (nonatomic, strong) IBOutlet NSArrayController *receipts;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;
// Where a new row's name is typed.
@property (nonatomic, strong) IBOutlet NSTableView *itemsTable;
@property (nonatomic, strong) IBOutlet NSTableView *warehousesTable;
@property (nonatomic, strong) IBOutlet NSTableView *locationsTable;
@property (nonatomic, strong) IBOutlet NSTableView *categoriesTable;
@property (nonatomic, strong) IBOutlet NSTableView *contactsTable;
@property (nonatomic, strong) IBOutlet NSSearchField *itemSearch;

// The orders lists are in: by title, by name, the latest first.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byName;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *latestFirst;
// Orders, shipments and receipts, the latest number first; an order's
// lines, by item, a kit's components under it.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *latestNumberFirst;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *linesInOrder;
// What the chosen catalog's forms choose from: its categories, its
// suppliers, its locations (every warehouse's), the items a kit may take
// (all but the chosen one), and the reasons for an adjustment.
@property (nonatomic, readonly, copy) NSArray<Category *> *categories;
@property (nonatomic, readonly, copy) NSArray<Supplier *> *suppliers;
@property (nonatomic, readonly, copy) NSArray<Customer *> *customers;
// The items an order's line may be of: the catalog's.
@property (nonatomic, readonly, copy) NSArray<StockItem *> *catalogItems;
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

// What an order's line is about to ship or receive, typed and chosen
// under its lines: how many, and where from or at.
@property (nonatomic, copy, nullable) NSString *orderQuantity;
@property (nonatomic, strong, nullable) Location *orderAt;

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
// Setup: a new row of each, named to be typed over, chosen; the chosen
// ones removed (refused at save where something is of them).
- (IBAction)addWarehouse:(nullable id)sender;
- (IBAction)removeWarehouse:(nullable id)sender;
- (IBAction)addLocation:(nullable id)sender;
- (IBAction)removeLocation:(nullable id)sender;
- (IBAction)addCategory:(nullable id)sender;
- (IBAction)removeCategory:(nullable id)sender;
- (IBAction)addContact:(nullable id)sender;
- (IBAction)removeContact:(nullable id)sender;
// Orders: a new draft, numbered, to the first customer (from the first
// supplier), chosen; a draft not saved removed (a saved one is
// cancelled); lines added, of the first item, at its price or cost, and
// removed; the server's Confirm, Close, Cancel and Reopen. Shipped or
// received: the chosen line, so many as typed, from or at orderAt; or
// every line's outstanding (what orderAt holds of each, shipping).
- (IBAction)newSale:(nullable id)sender;
- (IBAction)removeSale:(nullable id)sender;
- (IBAction)addSaleLine:(nullable id)sender;
- (IBAction)removeSaleLine:(nullable id)sender;
- (IBAction)confirmSale:(nullable id)sender;
- (IBAction)closeSale:(nullable id)sender;
- (IBAction)cancelSale:(nullable id)sender;
- (IBAction)reopenSale:(nullable id)sender;
- (IBAction)shipLine:(nullable id)sender;
- (IBAction)shipOutstanding:(nullable id)sender;
- (IBAction)newPurchase:(nullable id)sender;
- (IBAction)removePurchase:(nullable id)sender;
- (IBAction)addPurchaseLine:(nullable id)sender;
- (IBAction)removePurchaseLine:(nullable id)sender;
- (IBAction)confirmPurchase:(nullable id)sender;
- (IBAction)closePurchase:(nullable id)sender;
- (IBAction)cancelPurchase:(nullable id)sender;
- (IBAction)reopenPurchase:(nullable id)sender;
- (IBAction)receiveLine:(nullable id)sender;
- (IBAction)receiveOutstanding:(nullable id)sender;
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
