// An item's window (StockItem.xib; docs/STOCK.md, Items): its card, and
// in its tabs its stock (holdings and moves, and the stock adjusted, moved
// and assembled from it), its recipe, its supplier items, its codes, its
// size and its reorder rules. It reads the item and what is of it.

#import "LBStockEditor.h"

@class StockItem, Holding, Move, KitLine, SupplierItem, ItemCode, StockUnit, ReorderRule, PlanTask, Checklist, DistanceUnit, Category, Supplier, Location, Warehouse,
    WeightUnit, SizeUnit, StockTransfer, ORMFlowSession;

NS_ASSUME_NONNULL_BEGIN

@interface LBStockItemWindowController : LBStockEditor <NSTabViewDelegate>

// The item's window; a new item of the catalog's (its SKU the next, named
// "New Item" to be typed over) for none.
- (instancetype)initWithStore:(LBStore *)store item:(nullable StockItem *)item catalog:(Catalog *)catalog;
// Its moves, and what made the one chosen opened (Open, a double click):
// its order, its count, the record it was fitted by.
@property (nonatomic, strong) IBOutlet NSArrayController *moveList;
@property (nonatomic, strong) IBOutlet NSTableView *movesTable;
- (IBAction)openMove:(nullable id)sender;
@property (nonatomic, readonly, strong) StockItem *item;
// A transfer asked for, of its item: its Move the stock task's
// (LBStockEditor's task), its MoveStock sheet shown as the window is.
- (instancetype)initWithStore:(LBStore *)store transfer:(StockTransfer *)transfer;
@property (nonatomic, readonly, strong, nullable) StockTransfer *transfer;
// Its transfers' forms (Model/Transferring.flow, ORMRuntime's
// ORMFlowSession), as their sheets bind them (LBFormValues.h):
// RequestTransfer, MoveStock while its sheet is shown.
@property (nonatomic, readonly, strong, nullable) ORMFlowSession *flow;
@property (nonatomic, readonly, strong, nullable) LBFormValues *requestForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *moveForm;
@property (nonatomic, strong) IBOutlet NSWindow *requestPanel;
@property (nonatomic, strong) IBOutlet NSWindow *movePanel;
@property (nonatomic, strong) IBOutlet NSTabView *cardTabs;

// What is of it: its holdings, its moves newest first, its recipe, its
// supplier items, codes and reorder rules.
@property (nonatomic, readonly, copy) NSArray<Holding *> *holdings;
@property (nonatomic, readonly, copy) NSArray<Move *> *moves;
@property (nonatomic, readonly, copy) NSArray<KitLine *> *kitLines;
@property (nonatomic, readonly, copy) NSArray<SupplierItem *> *supplierItems;
@property (nonatomic, readonly, copy) NSArray<ItemCode *> *itemCodes;
// Its units, each one of it by its serial number (the code on it: a
// barcode or the maker's serial), where it is and a note.
@property (nonatomic, readonly, copy) NSArray<StockUnit *> *stockUnits;
@property (nonatomic, readonly, copy) NSArray<ReorderRule *> *reorderRules;
// Its maintenance plan, the maker's (docs/CSDP.md, A maintenance plan):
// each plan task a task or a checklist, every so much usage or so many
// months; every asset of it follows it. What a plan task chooses from: the
// catalog owner's checklists, the units usage is counted in.
@property (nonatomic, readonly, copy) NSArray<PlanTask *> *planTasks;
@property (nonatomic, readonly, copy) NSArray<Checklist *> *checklists;
@property (nonatomic, readonly, copy) NSArray<DistanceUnit *> *usageUnits;
@property (nonatomic, strong) IBOutlet NSArrayController *planTaskList;
@property (nonatomic, strong) IBOutlet NSTableView *planTasksTable;
@property (nonatomic, strong) IBOutlet NSArrayController *kitLineList;
@property (nonatomic, strong) IBOutlet NSArrayController *supplierItemList;
@property (nonatomic, strong) IBOutlet NSArrayController *itemCodeList;
@property (nonatomic, strong) IBOutlet NSArrayController *stockUnitList;
@property (nonatomic, strong) IBOutlet NSArrayController *reorderRuleList;
@property (nonatomic, strong) IBOutlet NSTableView *supplierItemsTable;
@property (nonatomic, strong) IBOutlet NSTableView *itemCodesTable;
@property (nonatomic, strong) IBOutlet NSTableView *stockUnitsTable;
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

// Its stock adjusted at stockAt by stockQuantity for stockReason; so many
// batches assembled, or taken apart, at stockAt: each the server's action.
// Transfer: a transfer of stockQuantity from stockAt to stockTo asked
// for, in RequestTransfer's sheet; its Submit saves it, requested (nothing
// moved yet: a keeper of where it goes from moves it, Model/TransferStock.bpmn).
// MoveStock's Submit: its form saved (moved, or cancelled), submitted to
// its task. Cancel (and Escape): nothing of it kept.
- (IBAction)adjust:(nullable id)sender;
- (IBAction)transfer:(nullable id)sender;
- (IBAction)submitRequest:(nullable id)sender;
- (IBAction)submitMove:(nullable id)sender;
- (IBAction)dismissForm:(nullable id)sender;
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
// A plan task, a task to be named, every 12 months; the chosen ones
// removed (their assets' schedules ended).
- (IBAction)addPlanTask:(nullable id)sender;
- (IBAction)removePlanTask:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
