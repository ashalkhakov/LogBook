#import "LBStockWindowController.h"
#import "LBStore.h"
#import "LBStockDisplay.h"
#import "LBStockItemWindowController.h"
#import "LBStockOrderWindowController.h"
#import "LBStockCountWindowController.h"
#import "LBCatalogSettingsWindowController.h"

@interface LBStockWindowController () <NSTabViewDelegate>
@property (nonatomic, readwrite, copy) NSArray<Catalog *> *catalogs;
@property (nonatomic, readwrite, copy) NSArray<StockItem *> *items;
@property (nonatomic, readwrite, copy) NSArray *saleOrders;
@property (nonatomic, readwrite, copy) NSArray *purchaseOrders;
@property (nonatomic, readwrite, copy) NSArray<Move *> *catalogMoves;
@property (nonatomic, readwrite, copy) NSArray<LBChange *> *catalogChanges;
@property (nonatomic, readwrite, copy) NSArray<Location *> *locations;
@property (nonatomic, readwrite, copy) NSArray<StockCount *> *catalogCounts;
@property (nonatomic, readwrite, strong) NSNumber *overviewItems;
@property (nonatomic, readwrite, strong) NSDecimalNumber *overviewQuantity;
@property (nonatomic, readwrite, copy) NSString *overviewValueAtPrice;
@property (nonatomic, readwrite, copy) NSString *overviewValueAtCost;
@property (nonatomic, readwrite, strong) NSNumber *overviewCategories;
@property (nonatomic, readwrite, strong) NSNumber *overviewLocations;
@property (nonatomic, readwrite, strong) NSNumber *overviewSuppliers;
@property (nonatomic, readwrite, strong) NSNumber *overviewCustomers;
@property (nonatomic, readwrite, strong, nullable) LBStockTotals *overviewTotals;
@property (nonatomic, readwrite, copy) NSString *overviewWeight;
@property (nonatomic, readwrite, copy) NSString *overviewVolume;
@property (nonatomic, readwrite, copy) NSArray<ReorderRule *> *rulesDue;
@property (nonatomic, readwrite, copy) NSArray<NSManagedObject *> *ordersOpen;
@property (nonatomic, readwrite, copy) NSArray<Warehouse *> *warehouses;
@end

@implementation LBStockWindowController {
    /* What has been read since stock last changed: each tab's lists. */
    NSMutableSet<NSString *> *_read;
    /* The windows it opened that are open. */
    NSMutableArray<LBStockEditor *> *_opened;
}

- (instancetype)initWithStore:(LBStore *)store {
    if ((self = [super initWithStore:store windowNibName:@"StockWindow"])) {
        _read = [NSMutableSet set];
        _opened = [NSMutableArray array];
        _catalogs = @[];
        _items = @[];
        _saleOrders = @[];
        _purchaseOrders = @[];
        _catalogMoves = @[];
        _catalogChanges = @[];
        _locations = @[];
        _catalogCounts = @[];
        _rulesDue = @[];
        _ordersOpen = @[];
        _warehouses = @[];
        _changeKinds = [@[ @"All" ] arrayByAddingObjectsFromArray:[Move lbKinds]];
        _changeKind = @"All";
    }
    return self;
}

- (void)windowDidLoad {
    self.window.title = [NSString stringWithFormat:@"Stock — %@", self.store.serviceRoot.host ?: @""];
    _itemsTable.doubleAction = @selector(openItem:);
    _itemsTable.target = self;
    _salesTable.doubleAction = @selector(openSale:);
    _salesTable.target = self;
    _purchasesTable.doubleAction = @selector(openPurchase:);
    _purchasesTable.target = self;
    _openOrdersTable.doubleAction = @selector(showOrder:);
    _openOrdersTable.target = self;
    [super windowDidLoad];
}

- (NSArray<NSSortDescriptor *> *)byItem {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"stockItem.itemName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

static NSArray<NSSortDescriptor *> *LBLatestNumberFirst(void) {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"runningNumber" ascending:NO] ];
}

#pragma mark Reading

/* The catalogs, and the shown tab's lists: the others' as they are shown. */
- (void)readAgain {
    [_read removeAllObjects];
    self.catalogs = [self fetch:[Catalog class] where:nil sortedBy:self.byTitle];
    if (![_catalogs containsObject:self.catalog]) self.catalog = _catalogs.firstObject;
    [self readShown];
}

- (void)setCatalog:(Catalog *)catalog {
    BOOL other = catalog != self.catalog;
    [super setCatalog:catalog];
    if (!other) return;
    [_read removeAllObjects];
    self.changeItem = nil;
    self.changeLocation = nil;
    if (self.isWindowLoaded) [self readShown];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)item {
    [self readShown];
}

- (void)readShown {
    NSString *shown = _tabs.selectedTabViewItem.identifier;
    if ([shown isEqual:@"items"]) [self need:@"items"];
    else if ([shown isEqual:@"saleOrders"]) [self need:@"sales"];
    else if ([shown isEqual:@"purchaseOrders"]) [self need:@"purchases"];
    else if ([shown isEqual:@"changes"]) {
        [self need:@"items"];
        [self need:@"locations"];
        [self need:@"moves"];
    } else if ([shown isEqual:@"counts"]) [self need:@"counts"];
    else if ([shown isEqual:@"overview"]) {
        [self need:@"items"];
        [self need:@"sales"];
        [self need:@"purchases"];
        [self need:@"locations"];
        [self need:@"overview"];
    }
}

/* One of the lists read, unless it has been since stock changed. */
- (void)need:(NSString *)list {
    if ([_read containsObject:list]) return;
    [_read addObject:list];
    Catalog *catalog = self.catalog;
    NSPredicate *ofCatalog = [NSPredicate predicateWithFormat:@"catalog == %@", catalog];
    if (!catalog) {
        if ([list isEqual:@"items"]) self.items = @[];
        return;
    }
    if ([list isEqual:@"items"]) {
        NSSortDescriptor *byName = [NSSortDescriptor sortDescriptorWithKey:@"itemName" ascending:YES
                                                                  selector:@selector(localizedCaseInsensitiveCompare:)];
        self.items = [self fetch:[StockItem class] where:ofCatalog sortedBy:@[ byName ]];
    } else if ([list isEqual:@"sales"]) {
        self.saleOrders = [self fetch:[SaleOrder class] where:ofCatalog sortedBy:LBLatestNumberFirst()];
    } else if ([list isEqual:@"purchases"]) {
        self.purchaseOrders = [self fetch:[PurchaseOrder class] where:ofCatalog sortedBy:LBLatestNumberFirst()];
    } else if ([list isEqual:@"locations"]) {
        self.locations = [self fetch:[Location class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@", catalog]
                            sortedBy:self.byTitle];
    } else if ([list isEqual:@"moves"]) {
        NSSortDescriptor *latest = [NSSortDescriptor sortDescriptorWithKey:@"moment" ascending:NO];
        self.catalogMoves = [self fetch:[Move class] where:[NSPredicate predicateWithFormat:@"stockItem.catalog == %@", catalog]
                               sortedBy:@[ latest ]];
        self.catalogChanges = [LBChange changesOf:_catalogMoves];
        [self applyChangeFilters];
    } else if ([list isEqual:@"counts"]) {
        NSSortDescriptor *latest = [NSSortDescriptor sortDescriptorWithKey:@"countedOn" ascending:NO];
        self.catalogCounts = [self fetch:[StockCount class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@", catalog]
                                sortedBy:[@[ latest ] arrayByAddingObjectsFromArray:LBLatestNumberFirst()]];
    } else if ([list isEqual:@"overview"]) {
        [self overviewOf:catalog];
    }
}

- (void)overviewOf:(Catalog *)catalog {
    NSPredicate *ofCatalog = [NSPredicate predicateWithFormat:@"catalog == %@", catalog];
    LBStockFigures *figures = [LBStockFigures figuresOf:_items currency:catalog.currency weightIn:catalog.weightUnit sizeIn:catalog.sizeUnit];
    self.overviewItems = @(_items.count);
    self.overviewQuantity = figures.quantity;
    self.overviewValueAtPrice = figures.valueAtPrice;
    self.overviewValueAtCost = figures.valueAtCost;
    self.overviewCategories = @([self fetch:[Category class] where:ofCatalog sortedBy:nil].count);
    self.overviewLocations = @(_locations.count);
    self.overviewSuppliers = @([self fetch:[Supplier class] where:ofCatalog sortedBy:nil].count);
    self.overviewCustomers = @([self fetch:[Customer class] where:ofCatalog sortedBy:nil].count);
    self.overviewTotals = figures.totals;
    self.overviewWeight = _overviewTotals.weightText;
    self.overviewVolume = _overviewTotals.volumeText;
    NSArray *rules = [self fetch:[ReorderRule class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@", catalog]
                        sortedBy:self.byItem];
    self.rulesDue = [rules filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDue == YES"]];
    self.warehouses = [self fetch:[Warehouse class] where:ofCatalog sortedBy:self.byTitle];
    self.ordersOpen = [LBStockFigures openOf:_saleOrders purchases:_purchaseOrders];
}

#pragma mark The changelog

- (void)setChangeItem:(StockItem *)item {
    _changeItem = item;
    [self applyChangeFilters];
}

- (void)setChangeLocation:(Location *)location {
    _changeLocation = location;
    [self applyChangeFilters];
}

- (void)setChangeKind:(NSString *)kind {
    _changeKind = [kind copy] ?: @"All";
    [self applyChangeFilters];
}

- (void)setChangeSince:(NSDate *)day {
    _changeSince = [day copy];
    [self applyChangeFilters];
}

- (void)applyChangeFilters {
    NSMutableArray *each = [NSMutableArray array];
    if (_changeItem) [each addObject:[NSPredicate predicateWithFormat:@"move.stockItem == %@", _changeItem]];
    if (_changeLocation) {
        [each addObject:[NSPredicate predicateWithFormat:@"move.source == %@ OR move.destination == %@", _changeLocation, _changeLocation]];
    }
    if (![_changeKind isEqualToString:@"All"]) [each addObject:[NSPredicate predicateWithFormat:@"move.lbKind == %@", _changeKind]];
    if (_changeSince) {
        NSDate *start = [[NSCalendar currentCalendar] startOfDayForDate:_changeSince];
        [each addObject:[NSPredicate predicateWithFormat:@"move.moment >= %@", start]];
    }
    _changeList.filterPredicate = each.count ? [NSCompoundPredicate andPredicateWithSubpredicates:each] : nil;
}

#pragma mark Windows

- (LBStockEditor *)windowOf:(NSManagedObject *)object {
    for (LBStockEditor *editor in _opened) {
        NSManagedObject *of = [editor isKindOfClass:[LBStockItemWindowController class]] ? ((LBStockItemWindowController *)editor).item
                              : [editor isKindOfClass:[LBStockOrderWindowController class]] ? ((LBStockOrderWindowController *)editor).order
                                                                                             : nil;
        if (object && [of.objectID isEqual:object.objectID]) return editor;
    }
    return nil;
}

- (LBStockEditor *)windowOfClass:(Class)cls {
    for (LBStockEditor *editor in _opened) {
        if ([editor isKindOfClass:cls] && editor.catalog.objectID && [editor.catalog.objectID isEqual:self.catalog.objectID]) return editor;
    }
    return nil;
}

/* Shown, and kept while it is open. */
- (void)show:(LBStockEditor *)editor {
    editor.quiet = self.quiet;
    if (![_opened containsObject:editor]) {
        [_opened addObject:editor];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openedWillClose:) name:NSWindowWillCloseNotification
                                                   object:editor.window];
    }
    [editor showWindow:self];
}

- (void)openedWillClose:(NSNotification *)note {
    for (LBStockEditor *editor in [_opened copy]) {
        if (editor.window == note.object) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:editor.window];
            [_opened removeObject:editor];
        }
    }
}

- (void)openOrder:(NSManagedObject *)order {
    if (!order) return;
    LBStockEditor *editor = [self windowOf:order] ?: [[LBStockOrderWindowController alloc] initWithStore:self.store order:order];
    [self show:editor];
}

#pragma mark Catalogs

- (IBAction)newCatalog:(id)sender {
    if (![self commitEdits]) return;
    Catalog *catalog = [Catalog lb_newCatalogNamed:@"New Catalog" owner:self.user inContext:self.context];
    if (![self saveChanges]) {
        [self.context rollback];
        return;
    }
    self.catalog = catalog;
    [self readAgain];
    [self showSettings:sender];
}

- (IBAction)showSettings:(id)sender {
    if (!self.catalog) return;
    LBStockEditor *editor = [self windowOfClass:[LBCatalogSettingsWindowController class]]
                            ?: [[LBCatalogSettingsWindowController alloc] initWithStore:self.store catalog:self.catalog];
    [self show:editor];
}

#pragma mark Items

- (IBAction)addItem:(id)sender {
    if (!self.catalog) return;
    [self show:[[LBStockItemWindowController alloc] initWithStore:self.store item:nil catalog:self.catalog]];
}

- (IBAction)openItem:(id)sender {
    StockItem *item = _itemList.selectedObjects.firstObject;
    if (!item) return;
    [self show:[self windowOf:item] ?: [[LBStockItemWindowController alloc] initWithStore:self.store item:item catalog:self.catalog]];
}

- (IBAction)removeItem:(id)sender {
    for (StockItem *item in _itemList.selectedObjects) [self.context deleteObject:item];
    if (![self saveChanges]) [self.context rollback];
    [self readAgain];
}

- (IBAction)search:(id)sender {
    NSString *text = _itemSearch.stringValue;
    _itemList.filterPredicate = text.length ? [NSPredicate predicateWithFormat:@"itemName CONTAINS[cd] %@ OR sku CONTAINS[cd] %@ "
                                                                               @"OR descriptionValue CONTAINS[cd] %@",
                                                                               text, text, text]
                                            : nil;
}

#pragma mark Orders

- (IBAction)newSale:(id)sender {
    Catalog *catalog = self.catalog;
    if (!catalog) return;
    Customer *customer = [[self fetch:[Customer class] where:[NSPredicate predicateWithFormat:@"catalog == %@", catalog] sortedBy:self.byTitle]
                          firstObject];
    if (!customer) return [self refuse:@"No customer to sell to: make a contact a customer in the catalog's settings."];
    SaleOrder *sale = [catalog lb_newSaleOrderTo:customer on:[NSDate date]];
    if (![self saveChanges]) return [self.context rollback];
    [self openOrder:sale];
}

- (IBAction)newPurchase:(id)sender {
    Catalog *catalog = self.catalog;
    if (!catalog) return;
    Supplier *supplier = [[self fetch:[Supplier class] where:[NSPredicate predicateWithFormat:@"catalog == %@", catalog] sortedBy:self.byTitle]
                          firstObject];
    if (!supplier) return [self refuse:@"No supplier to buy from: make a contact a supplier in the catalog's settings."];
    PurchaseOrder *purchase = [catalog lb_newPurchaseOrderFrom:supplier on:[NSDate date]];
    if (![self saveChanges]) return [self.context rollback];
    [self openOrder:purchase];
}

- (IBAction)openSale:(id)sender {
    [self openOrder:_saleList.selectedObjects.firstObject];
}

- (IBAction)openPurchase:(id)sender {
    [self openOrder:_purchaseList.selectedObjects.firstObject];
}

#pragma mark Counts and the overview

- (IBAction)newCount:(id)sender {
    if (!self.catalog) return;
    LBStockEditor *editor = [self windowOfClass:[LBStockCountWindowController class]]
                            ?: [[LBStockCountWindowController alloc] initWithStore:self.store catalog:self.catalog];
    [self show:editor];
}

- (IBAction)reorder:(id)sender {
    NSMutableOrderedSet *due = [NSMutableOrderedSet orderedSet];
    for (ReorderRule *rule in _rulesDue) {
        if (rule.warehouse) [due addObject:rule.warehouse];
    }
    NSMutableArray *drafts = [NSMutableArray array];
    for (Warehouse *warehouse in due) {
        id made = [self performAction:@"Reorder" on:warehouse parameters:nil];
        if (!made) return;
        if ([made isKindOfClass:[NSArray class]]) [drafts addObjectsFromArray:made];
    }
    [_tabs selectTabViewItemWithIdentifier:@"purchaseOrders"];
    NSMutableArray *chosen = [NSMutableArray array];
    for (NSManagedObject *draft in drafts) {
        NSManagedObject *own = [self own:draft];
        if (own) [chosen addObject:own];
    }
    [_purchaseList setSelectedObjects:chosen];
}

- (IBAction)showOrder:(id)sender {
    [self openOrder:_openList.selectedObjects.firstObject];
}

@end
