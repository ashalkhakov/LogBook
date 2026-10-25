// The stock window (StockWindow.xib; docs/STOCK.md): the catalog chosen,
// and its lists, each in a tab: its items, its sales and purchases, the
// changelog, its counts, the overview. It only lists: what is listed opens
// in a window of its own, which edits it (an item, an order, a count, the
// catalog's settings). A tab reads what it lists when it is shown, and
// again when stock changes.

#import "LBStockEditor.h"

@class Catalog, StockItem, Location, Warehouse, Move, StockCount, ReorderRule, LBChange, LBStockTotals;

NS_ASSUME_NONNULL_BEGIN

@interface LBStockWindowController : LBStockEditor

- (instancetype)initWithStore:(LBStore *)store;

// The catalogs the user sees; the one chosen is the editor's catalog.
@property (nonatomic, readonly, copy) NSArray<Catalog *> *catalogs;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;

// Items: the catalog's, as the search leaves them (itemList).
@property (nonatomic, readonly, copy) NSArray<StockItem *> *items;
@property (nonatomic, strong) IBOutlet NSArrayController *itemList;
@property (nonatomic, strong) IBOutlet NSTableView *itemsTable;
@property (nonatomic, strong) IBOutlet NSSearchField *itemSearch;
// Sales and purchases, the latest number first.
@property (nonatomic, readonly, copy) NSArray *saleOrders;
@property (nonatomic, readonly, copy) NSArray *purchaseOrders;
@property (nonatomic, strong) IBOutlet NSArrayController *saleList;
@property (nonatomic, strong) IBOutlet NSArrayController *purchaseList;
@property (nonatomic, strong) IBOutlet NSTableView *salesTable;
@property (nonatomic, strong) IBOutlet NSTableView *purchasesTable;

// The changelog: every move of the catalog's items, newest first, with
// before and after (changeList, as its filters leave it); the filters: an
// item, a location (from or to), what made it ("All", or one of Move's
// lbKinds), a day from which on.
@property (nonatomic, readonly, copy) NSArray<Move *> *catalogMoves;
@property (nonatomic, readonly, copy) NSArray<LBChange *> *catalogChanges;
@property (nonatomic, strong) IBOutlet NSArrayController *changeList;
@property (nonatomic, readonly, copy) NSArray<Location *> *locations;
@property (nonatomic, readonly, copy) NSArray<NSString *> *changeKinds;
@property (nonatomic, strong, nullable) StockItem *changeItem;
@property (nonatomic, strong, nullable) Location *changeLocation;
@property (nonatomic, copy) NSString *changeKind;
@property (nonatomic, copy, nullable) NSDate *changeSince;

// Counts: the catalog's, the latest first (countList); the chosen one's
// adjustments, by item.
@property (nonatomic, readonly, copy) NSArray<StockCount *> *catalogCounts;
@property (nonatomic, strong) IBOutlet NSArrayController *countList;
@property (nonatomic, readonly, copy) NSArray<NSSortDescriptor *> *byItem;

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
@property (nonatomic, readonly, strong, nullable) LBStockTotals *overviewTotals;
@property (nonatomic, readonly, copy) NSString *overviewWeight;
@property (nonatomic, readonly, copy) NSString *overviewVolume;
@property (nonatomic, readonly, copy) NSArray<ReorderRule *> *rulesDue;
@property (nonatomic, readonly, copy) NSArray<NSManagedObject *> *ordersOpen;
@property (nonatomic, readonly, copy) NSArray<Warehouse *> *warehouses;
@property (nonatomic, strong) IBOutlet NSArrayController *openList;
@property (nonatomic, strong) IBOutlet NSTableView *openOrdersTable;

// A new catalog of the user's, named "New Catalog", with its warehouse
// and location: saved, chosen, its settings opened.
- (IBAction)newCatalog:(nullable id)sender;
- (IBAction)showSettings:(nullable id)sender;
// Items: a new one in a window of its own; the chosen one opened; the
// chosen ones removed (refused where something is of them); the list
// narrowed to what has the search's text in its name, SKU or description.
- (IBAction)addItem:(nullable id)sender;
- (IBAction)openItem:(nullable id)sender;
- (IBAction)removeItem:(nullable id)sender;
- (IBAction)search:(nullable id)sender;
// Orders: a new draft, numbered, to the first customer (from the first
// supplier), opened; the chosen one opened.
- (IBAction)newSale:(nullable id)sender;
- (IBAction)newPurchase:(nullable id)sender;
- (IBAction)openSale:(nullable id)sender;
- (IBAction)openPurchase:(nullable id)sender;
// A count opened, to be taken.
- (IBAction)newCount:(nullable id)sender;
// The server's Reorder for each warehouse with a rule due: its drafts
// chosen in Purchases. The open order chosen in the overview opened.
- (IBAction)reorder:(nullable id)sender;
- (IBAction)showOrder:(nullable id)sender;

// The windows it opened that are open: the one of the object, or of the
// class (the count's, the settings').
- (nullable __kindof LBStockEditor *)windowOf:(NSManagedObject *)object;
- (nullable __kindof LBStockEditor *)windowOfClass:(Class)cls;

@end

NS_ASSUME_NONNULL_END
