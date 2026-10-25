// An item's window (StockItem.xib; docs/STOCK.md, Items): its card, and
// in its tabs its stock (holdings and moves, and the stock adjusted, moved
// and assembled from it), its recipe, its supplier items, its codes, its
// size and its reorder rules. It reads the item and what is of it.

#import "LBStockEditor.h"

@class StockItem, Holding, Move, KitLine, SupplierItem, ItemCode, ReorderRule, Category, Supplier, Location, Warehouse,
    WeightUnit, SizeUnit;

NS_ASSUME_NONNULL_BEGIN

@interface LBStockItemWindowController : LBStockEditor

// The item's window; a new item of the catalog's (its SKU the next, named
// "New Item" to be typed over) for none.
- (instancetype)initWithStore:(LBStore *)store item:(nullable StockItem *)item catalog:(Catalog *)catalog;
@property (nonatomic, readonly, strong) StockItem *item;
@property (nonatomic, strong) IBOutlet NSTabView *cardTabs;

// What is of it: its holdings, its moves newest first, its recipe, its
// supplier items, codes and reorder rules.
@property (nonatomic, readonly, copy) NSArray<Holding *> *holdings;
@property (nonatomic, readonly, copy) NSArray<Move *> *moves;
@property (nonatomic, readonly, copy) NSArray<KitLine *> *kitLines;
@property (nonatomic, readonly, copy) NSArray<SupplierItem *> *supplierItems;
@property (nonatomic, readonly, copy) NSArray<ItemCode *> *itemCodes;
@property (nonatomic, readonly, copy) NSArray<ReorderRule *> *reorderRules;
@property (nonatomic, strong) IBOutlet NSArrayController *kitLineList;
@property (nonatomic, strong) IBOutlet NSArrayController *supplierItemList;
@property (nonatomic, strong) IBOutlet NSArrayController *itemCodeList;
@property (nonatomic, strong) IBOutlet NSArrayController *reorderRuleList;
@property (nonatomic, strong) IBOutlet NSTableView *supplierItemsTable;
@property (nonatomic, strong) IBOutlet NSTableView *itemCodesTable;
@property (nonatomic, strong) IBOutlet NSTableView *reorderRulesTable;

// What its forms choose from: the catalog's categories, suppliers,
// locations, other items (a kit's components) and warehouses; the
// reasons for an adjustment; the kinds of code; the units.
@property (nonatomic, readonly, copy) NSArray<Category *> *categories;
@property (nonatomic, readonly, copy) NSArray<Supplier *> *suppliers;
@property (nonatomic, readonly, copy) NSArray<Location *> *locations;
@property (nonatomic, readonly, copy) NSArray<StockItem *> *components;
@property (nonatomic, readonly, copy) NSArray<Warehouse *> *catalogWarehouses;
@property (nonatomic, readonly, copy) NSArray<NSString *> *reasons;
@property (nonatomic, readonly, copy) NSArray<NSString *> *codeKinds;
@property (nonatomic, readonly, copy) NSArray<WeightUnit *> *weightUnits;
@property (nonatomic, readonly, copy) NSArray<SizeUnit *> *sizeUnits;
// Whom it is preferably bought from: chosen, its supplier item made where
// it has none (StockItem lb_preferredSupplier), and listed.
@property (nonatomic, strong, nullable) Supplier *preferredSupplier;

// What moving its stock is about to do, typed and chosen: how many (less
// than none, an adjustment out), where (at, or from), where to, and why.
@property (nonatomic, copy, nullable) NSString *stockQuantity;
@property (nonatomic, strong, nullable) Location *stockAt;
@property (nonatomic, strong, nullable) Location *stockTo;
@property (nonatomic, copy, nullable) NSString *stockReason;

// Its stock adjusted at stockAt by stockQuantity for stockReason; moved
// from stockAt to stockTo; so many batches assembled, or taken apart, at
// stockAt. Each the server's action.
- (IBAction)adjust:(nullable id)sender;
- (IBAction)transfer:(nullable id)sender;
- (IBAction)assemble:(nullable id)sender;
- (IBAction)disassemble:(nullable id)sender;
// Its tables: a recipe line of a component, one of it; a supplier item
// from the first supplier it has none from, its SKU to be typed; a code,
// a GTIN, to be typed over; a reorder rule at the first warehouse it has
// none at, its point to be typed. The chosen ones removed.
- (IBAction)addKitLine:(nullable id)sender;
- (IBAction)removeKitLine:(nullable id)sender;
- (IBAction)addSupplierItem:(nullable id)sender;
- (IBAction)removeSupplierItem:(nullable id)sender;
- (IBAction)addItemCode:(nullable id)sender;
- (IBAction)removeItemCode:(nullable id)sender;
- (IBAction)addReorderRule:(nullable id)sender;
- (IBAction)removeReorderRule:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
