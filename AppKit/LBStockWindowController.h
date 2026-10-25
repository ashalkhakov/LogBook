// The stock window (StockWindow.xib; docs/STOCK.md): a catalog chosen, and
// in its tabs what the design has: its items, each with its quantities,
// holdings, recipe, supplier items, codes, reorder rules and history, and
// its stock adjusted, moved and assembled from it; its sales and
// purchases; the changelog; its counts; the overview; its setup. What it shows and edits is bound in the XIB to array
// controllers over the store's context, as the logbook's window is; what
// changes stock is the server's actions (Server/LBStockActions.h), the
// changes saved first.

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class LBStore, Catalog, StockItem, Location, Category, Supplier, Customer, Warehouse, Move, StockCount, ReorderRule;

NS_ASSUME_NONNULL_BEGIN

// What a count may be of: a warehouse, all of it, or one of its locations.
@interface LBCountPlace : NSObject
@property (nonatomic, readonly, strong) Warehouse *warehouse;
@property (nonatomic, readonly, strong, nullable) Location *location;
@property (nonatomic, readonly, copy) NSString *lbTitle;
// Its locations: the one, or every one of the warehouse.
@property (nonatomic, readonly, copy) NSArray<Location *> *locations;
@end

// A row of a count being taken: an item at a location, how many are held
// there, and how many were found (typed; none yet, nil).
@interface LBCountRow : NSObject
@property (nonatomic, strong, nullable) StockItem *item;
@property (nonatomic, strong, nullable) Location *location;
@property (nonatomic, copy, nullable) NSDecimalNumber *found;
@property (nonatomic) BOOL showsExpected;
// What is held there, when the counter chooses to see it; else nothing.
@property (nonatomic, readonly, nullable) id expectedShown;
@end

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
// The chosen item's supplier items, codes and reorder rules.
@property (nonatomic, strong) IBOutlet NSArrayController *supplierItems;
@property (nonatomic, strong) IBOutlet NSArrayController *itemCodes;
@property (nonatomic, strong) IBOutlet NSArrayController *reorderRules;
// The changelog's moves, as its filters leave them.
@property (nonatomic, strong) IBOutlet NSArrayController *changes;
// The Counts tab's: the catalog's counts, the chosen one's adjustments,
// and the rows of the count being taken.
@property (nonatomic, strong) IBOutlet NSArrayController *stockCounts;
@property (nonatomic, strong) IBOutlet NSArrayController *countMoves;
@property (nonatomic, strong) IBOutlet NSArrayController *countRows;
// The overview's: the reorder rules due, the open orders, the warehouses
// and their counts.
@property (nonatomic, strong) IBOutlet NSArrayController *dueRules;
@property (nonatomic, strong) IBOutlet NSArrayController *openOrders;
@property (nonatomic, strong) IBOutlet NSArrayController *countsDue;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;
// The item card's: Stock, Recipe, Suppliers, Codes, Reorder.
@property (nonatomic, strong) IBOutlet NSTabView *cardTabs;
// Where a new row's name is typed.
@property (nonatomic, strong) IBOutlet NSTableView *itemsTable;
@property (nonatomic, strong) IBOutlet NSTableView *warehousesTable;
@property (nonatomic, strong) IBOutlet NSTableView *locationsTable;
@property (nonatomic, strong) IBOutlet NSTableView *categoriesTable;
@property (nonatomic, strong) IBOutlet NSTableView *contactsTable;
@property (nonatomic, strong) IBOutlet NSTableView *supplierItemsTable;
@property (nonatomic, strong) IBOutlet NSTableView *itemCodesTable;
@property (nonatomic, strong) IBOutlet NSTableView *reorderRulesTable;
@property (nonatomic, strong) IBOutlet NSTableView *countRowsTable;
@property (nonatomic, strong) IBOutlet NSSearchField *itemSearch;

// The orders lists are in: by title, by name, the latest first.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byTitle;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byName;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *latestFirst;
// Orders, shipments and receipts, the latest number first; an order's
// lines, by item, a kit's components under it.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *latestNumberFirst;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *linesInOrder;
// Supplier items by supplier, codes by code, reorder rules by warehouse,
// a count's adjustments by item.
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *bySupplier;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byCode;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byWarehouse;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byItem;
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
// The kinds a code may be of (the model's).
@property (nonatomic, readonly, copy) NSArray<NSString *> *codeKinds;

// The changelog: every move of the catalog's items, newest first; and its
// filters, each narrowing the list when set: an item, a location (from or
// to), what made it ("All", or one of Move's lbKinds), and a day from
// which on.
@property (nonatomic, readonly, copy) NSArray<Move *> *catalogMoves;
@property (nonatomic, readonly, copy) NSArray<NSString *> *changeKinds;
@property (nonatomic, strong, nullable) StockItem *changeItem;
@property (nonatomic, strong, nullable) Location *changeLocation;
@property (nonatomic, copy) NSString *changeKind;
@property (nonatomic, copy, nullable) NSDate *changeSince;

// Counts: the catalog's, the latest first; what a new one may be of, and
// the one chosen; the rows of the count being taken (started), and the
// locations a row may be at; whether what is held is shown.
@property (nonatomic, readonly, copy) NSArray<StockCount *> *catalogCounts;
@property (nonatomic, readonly, copy) NSArray<LBCountPlace *> *countPlaces;
@property (nonatomic, strong, nullable) LBCountPlace *countPlace;
@property (nonatomic, readonly, copy) NSArray<LBCountRow *> *rowsCounted;
@property (nonatomic, readonly, copy) NSArray<Location *> *countLocations;
@property (nonatomic) BOOL showsExpected;

// The overview: the catalog's statistics; its reorder rules due, its
// orders open (drafts and confirmed), its warehouses with their counts.
@property (nonatomic, readonly, strong) NSNumber *overviewItems;
@property (nonatomic, readonly, strong) NSDecimalNumber *overviewQuantity;
@property (nonatomic, readonly, copy) NSString *overviewValueAtPrice;
@property (nonatomic, readonly, copy) NSString *overviewValueAtCost;
@property (nonatomic, readonly, strong) NSNumber *overviewCategories;
@property (nonatomic, readonly, strong) NSNumber *overviewLocations;
@property (nonatomic, readonly, strong) NSNumber *overviewSuppliers;
@property (nonatomic, readonly, strong) NSNumber *overviewCustomers;
@property (nonatomic, readonly, copy) NSArray<ReorderRule *> *rulesDue;
@property (nonatomic, readonly, copy) NSArray<NSManagedObject *> *ordersOpen;
@property (nonatomic, readonly, copy) NSArray<Warehouse *> *warehousesToCount;

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
// A new item of the chosen catalog, its SKU the next, its name to be
// typed over.
- (IBAction)addItem:(nullable id)sender;
- (IBAction)removeItem:(nullable id)sender;
// The items listed narrowed to those whose name, SKU or description has
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
// The item card's tables: a supplier item from the first supplier it has
// none from, its SKU to be typed; a code, a GTIN, to be typed over; a
// reorder rule at the first warehouse it has none at, its point to be
// typed. The chosen ones removed.
- (IBAction)addSupplierItem:(nullable id)sender;
- (IBAction)removeSupplierItem:(nullable id)sender;
- (IBAction)addItemCode:(nullable id)sender;
- (IBAction)removeItemCode:(nullable id)sender;
- (IBAction)addReorderRule:(nullable id)sender;
- (IBAction)removeReorderRule:(nullable id)sender;
// A count of countPlace started: a row for each holding there, nothing
// found yet. A row added (an item found that was not expected) or removed.
// Posted: the server's Count, of what was found in each row; refused
// while a row has nothing typed.
- (IBAction)startCount:(nullable id)sender;
- (IBAction)addCountRow:(nullable id)sender;
- (IBAction)removeCountRow:(nullable id)sender;
- (IBAction)postCount:(nullable id)sender;
// The server's Reorder for each warehouse with a rule due: its drafts
// shown in Purchases. The open order chosen in the overview shown in its
// tab.
- (IBAction)reorder:(nullable id)sender;
- (IBAction)showOrder:(nullable id)sender;
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

// The items' controller: a new one made now, its SKU the catalog's next,
// named to be typed over.
@interface LBStockItemController : NSArrayController
@property (nonatomic, weak) IBOutlet LBStockWindowController *windowController;
@end

// The recipe's controller: a new line takes one of its component.
@interface LBKitLineController : NSArrayController
@end

NS_ASSUME_NONNULL_END
