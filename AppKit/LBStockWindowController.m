#import "LBStockWindowController.h"
#import "LBStore.h"
#import "LBStockDisplay.h"
#import <ODataIncrementalStore/ODataOperationCall.h>

static void *LBCatalogChosen = &LBCatalogChosen;
static void *LBItemChosen = &LBItemChosen;

@implementation LBCountPlace

- (instancetype)initWithWarehouse:(Warehouse *)warehouse location:(Location *)location {
    if ((self = [super init])) {
        _warehouse = warehouse;
        _location = location;
    }
    return self;
}

- (NSString *)lbTitle {
    return _location ? _location.lbTitle : [NSString stringWithFormat:@"%@ (all of it)", _warehouse.lbTitle];
}

- (NSArray<Location *> *)locations {
    if (_location) return @[ _location ];
    NSSortDescriptor *byTitle = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbTitle)) ascending:YES
                                                               selector:@selector(localizedCaseInsensitiveCompare:)];
    return [_warehouse.locations.allObjects sortedArrayUsingDescriptors:@[ byTitle ]];
}

/* The same place however often the list is made: a pop-up keeps it. */
- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[LBCountPlace class]] && ((LBCountPlace *)other).warehouse == _warehouse
           && ((LBCountPlace *)other).location == _location;
}

- (NSUInteger)hash {
    return _warehouse.hash ^ _location.hash;
}

@end

@implementation LBCountRow

+ (NSSet<NSString *> *)keyPathsForValuesAffectingExpectedShown {
    return [NSSet setWithObjects:@"item", @"location", @"showsExpected", nil];
}

- (id)expectedShown {
    if (!_showsExpected || !_item || !_location) return nil;
    return [_location lb_heldOf:_item];
}

@end

@interface LBStockWindowController ()
@property (nonatomic, readwrite, strong) NSNumber *overviewItems;
@property (nonatomic, readwrite, strong) NSDecimalNumber *overviewQuantity;
@property (nonatomic, readwrite, copy) NSString *overviewValueAtPrice;
@property (nonatomic, readwrite, copy) NSString *overviewValueAtCost;
@property (nonatomic, readwrite, strong) NSNumber *overviewCategories;
@property (nonatomic, readwrite, strong) NSNumber *overviewLocations;
@property (nonatomic, readwrite, strong) NSNumber *overviewSuppliers;
@property (nonatomic, readwrite, strong) NSNumber *overviewCustomers;
@property (nonatomic, readwrite, copy) NSArray<ReorderRule *> *rulesDue;
@property (nonatomic, readwrite, copy) NSArray<NSManagedObject *> *ordersOpen;
@property (nonatomic, readwrite, copy) NSArray<Warehouse *> *warehousesToCount;
@property (nonatomic, readwrite, copy) NSArray<Move *> *catalogMoves;
@property (nonatomic, readwrite, copy) NSArray<StockCount *> *catalogCounts;
@property (nonatomic, readwrite, copy) NSArray<LBCountPlace *> *countPlaces;
@property (nonatomic, readwrite, copy) NSArray<LBCountRow *> *rowsCounted;
@property (nonatomic, readwrite, copy) NSArray<Location *> *countLocations;
@end

@implementation LBStockWindowController {
    /* The catalog whose moves catalogMoves has; none, to be read again. */
    Catalog *_movesOf;
    /* What the count being taken is of; none, none is. */
    LBCountPlace *_counting;
}

- (instancetype)initWithStore:(LBStore *)store {
    if ((self = [super initWithWindowNibName:@"StockWindow"])) {
        _store = store;
        _categories = @[];
        _suppliers = @[];
        _customers = @[];
        _catalogItems = @[];
        _locations = @[];
        _components = @[];
        _reasons = @[ @"Opening", @"Found", @"Damaged", @"Lost", @"Expired", @"Other" ];
        _stockReason = @"Opening";
        _codeKinds = @[ @"GTIN", @"Code 128", @"QR", @"EPC", @"Other" ];
        _changeKinds = [@[ @"All" ] arrayByAddingObjectsFromArray:[Move lbKinds]];
        _changeKind = @"All";
        _catalogMoves = @[];
        _catalogCounts = @[];
        _countPlaces = @[];
        _rowsCounted = @[];
        _countLocations = @[];
        _rulesDue = @[];
        _ordersOpen = @[];
        _warehousesToCount = @[];
    }
    return self;
}

- (void)dealloc {
    if (!self.isWindowLoaded) return;
    NSString *selection = NSStringFromSelector(@selector(selectionIndexes));
    [_catalogs removeObserver:self forKeyPath:selection context:LBCatalogChosen];
    [_items removeObserver:self forKeyPath:selection context:LBItemChosen];
}

- (NSManagedObjectContext *)context {
    return _store.context;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.title = [NSString stringWithFormat:@"Stock — %@", _store.serviceRoot.host ?: @""];
    NSString *selection = NSStringFromSelector(@selector(selectionIndexes));
    [_catalogs addObserver:self forKeyPath:selection options:NSKeyValueObservingOptionInitial context:LBCatalogChosen];
    [_items addObserver:self forKeyPath:selection options:NSKeyValueObservingOptionInitial context:LBItemChosen];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == LBCatalogChosen) [self catalogChosen];
    else if (context == LBItemChosen) [self itemChosen];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (NSArray<NSSortDescriptor *> *)byTitle {
    return @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbTitle)) ascending:YES
                                             selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

- (NSArray<NSSortDescriptor *> *)byName {
    return @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(itemName)) ascending:YES
                                             selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

- (NSArray<NSSortDescriptor *> *)latestFirst {
    return @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(moment)) ascending:NO] ];
}

- (Catalog *)chosenCatalog {
    NSArray *chosen = _catalogs.selectedObjects;
    return chosen.count == 1 ? chosen[0] : nil;
}

- (StockItem *)chosenItem {
    NSArray *chosen = _items.selectedObjects;
    return chosen.count == 1 ? chosen[0] : nil;
}

/* What the chosen catalog's forms choose from, read again. */
- (void)catalogChosen {
    Catalog *catalog = [self chosenCatalog];
    NSArray *byTitle = self.byTitle;
    [self willChangeValueForKey:@"categories"];
    _categories = [catalog.categories.allObjects sortedArrayUsingDescriptors:byTitle] ?: @[];
    [self didChangeValueForKey:@"categories"];
    [self willChangeValueForKey:@"suppliers"];
    _suppliers = [catalog.suppliers.allObjects sortedArrayUsingDescriptors:byTitle] ?: @[];
    [self didChangeValueForKey:@"suppliers"];
    [self willChangeValueForKey:@"customers"];
    _customers = [catalog.customers.allObjects sortedArrayUsingDescriptors:byTitle] ?: @[];
    [self didChangeValueForKey:@"customers"];
    [self willChangeValueForKey:@"catalogItems"];
    _catalogItems = [catalog.stockItems.allObjects sortedArrayUsingDescriptors:byTitle] ?: @[];
    [self didChangeValueForKey:@"catalogItems"];
    NSMutableArray *places = [NSMutableArray array];
    for (Warehouse *warehouse in catalog.warehouses) [places addObjectsFromArray:warehouse.locations.allObjects];
    [self willChangeValueForKey:@"locations"];
    _locations = [places sortedArrayUsingDescriptors:byTitle];
    [self didChangeValueForKey:@"locations"];
    if (![_locations containsObject:_stockAt]) self.stockAt = _locations.firstObject;
    if (![_locations containsObject:_stockTo]) self.stockTo = _locations.count > 1 ? _locations[1] : _locations.firstObject;
    if (![_locations containsObject:_orderAt]) self.orderAt = _locations.firstObject;
    if (![_locations containsObject:_changeLocation]) self.changeLocation = nil;
    if (![_catalogItems containsObject:_changeItem]) self.changeItem = nil;
    [self listCatalog:catalog];
    [self itemChosen];
}

/* What a kit may take: the catalog's other items. */
- (void)itemChosen {
    NSMutableArray *others = [[[self chosenCatalog].stockItems.allObjects sortedArrayUsingDescriptors:self.byTitle] mutableCopy] ?: [NSMutableArray array];
    StockItem *item = [self chosenItem];
    if (item) [others removeObject:item];
    [self willChangeValueForKey:@"components"];
    _components = others;
    [self didChangeValueForKey:@"components"];
}

- (NSArray<NSSortDescriptor *> *)bySupplier {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"supplier.lbTitle" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

- (NSArray<NSSortDescriptor *> *)byCode {
    return @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(codeText)) ascending:YES] ];
}

- (NSArray<NSSortDescriptor *> *)byWarehouse {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"warehouse.lbTitle" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

- (NSArray<NSSortDescriptor *> *)byItem {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"stockItem.itemName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

/* What the Changelog, Counts and Overview tabs list of the catalog: its
   moves read where they are not yet, the rest from what is in memory. */
- (void)listCatalog:(Catalog *)catalog {
    if (catalog != _movesOf) {
        _movesOf = catalog;
        self.catalogMoves = [self movesOf:catalog];
        [self applyChangeFilters];
    }
    NSMutableArray *counts = [NSMutableArray array];
    NSMutableArray *places = [NSMutableArray array];
    NSMutableArray *due = [NSMutableArray array];
    NSArray *warehouses = [catalog.warehouses.allObjects sortedArrayUsingDescriptors:self.byTitle] ?: @[];
    for (Warehouse *warehouse in warehouses) {
        [counts addObjectsFromArray:warehouse.stockCounts.allObjects];
        [places addObject:[[LBCountPlace alloc] initWithWarehouse:warehouse location:nil]];
        for (Location *place in [warehouse.locations.allObjects sortedArrayUsingDescriptors:self.byTitle]) {
            [places addObject:[[LBCountPlace alloc] initWithWarehouse:warehouse location:place]];
        }
        for (ReorderRule *rule in warehouse.reorderRules) {
            if (rule.isDue) [due addObject:rule];
        }
    }
    NSSortDescriptor *latest = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(countedOn)) ascending:NO];
    self.catalogCounts = [counts sortedArrayUsingDescriptors:@[ latest, self.latestNumberFirst[0] ]];
    self.countPlaces = places;
    NSUInteger kept = _countPlace ? [places indexOfObject:_countPlace] : NSNotFound;
    self.countPlace = kept != NSNotFound ? places[kept] : places.firstObject;
    self.rulesDue = [due sortedArrayUsingDescriptors:self.byItem];
    self.warehousesToCount = warehouses;
    [self overviewOf:catalog];
}

/* Every move of the catalog's items, newest first. */
- (NSArray<Move *> *)movesOf:(Catalog *)catalog {
    if (!catalog) return @[];
    NSFetchRequest<Move *> *request = [Move fetchRequest];
    request.predicate = [NSPredicate predicateWithFormat:@"stockItem.catalog == %@", catalog];
    request.sortDescriptors = self.latestFirst;
    NSError *error = nil;
    NSArray *moves = [self.context executeFetchRequest:request error:&error];
    if (!moves) [self reportError:error];
    return moves ?: @[];
}

- (void)overviewOf:(Catalog *)catalog {
    NSDecimalNumber *quantity = [NSDecimalNumber zero], *atPrice = [NSDecimalNumber zero], *atCost = [NSDecimalNumber zero];
    for (StockItem *item in _catalogItems) {
        NSDecimalNumber *held = item.totalQuantity ?: [NSDecimalNumber zero];
        quantity = [quantity decimalNumberByAdding:held];
        if (item.priceAmount) atPrice = [atPrice decimalNumberByAdding:[held decimalNumberByMultiplyingBy:item.priceAmount]];
        if (item.unitCostAmount) atCost = [atCost decimalNumberByAdding:[held decimalNumberByMultiplyingBy:item.unitCostAmount]];
    }
    NSString *currency = catalog.currency ?: @"";
    self.overviewItems = @(_catalogItems.count);
    self.overviewQuantity = quantity;
    self.overviewValueAtPrice = [NSString stringWithFormat:@"%@ %@", atPrice, currency];
    self.overviewValueAtCost = [NSString stringWithFormat:@"%@ %@", atCost, currency];
    self.overviewCategories = @(_categories.count);
    self.overviewLocations = @(_locations.count);
    self.overviewSuppliers = @(_suppliers.count);
    self.overviewCustomers = @(_customers.count);
    NSMutableArray *open = [NSMutableArray array];
    NSArray *states = @[ @"Draft", @"Confirmed" ];
    for (SaleOrder *order in catalog.saleOrders) {
        if ([states containsObject:order.orderState ?: @""]) [open addObject:order];
    }
    for (PurchaseOrder *order in catalog.purchaseOrders) {
        if ([states containsObject:order.orderState ?: @""]) [open addObject:order];
    }
    NSSortDescriptor *byKind = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(lbKind)) ascending:NO];
    self.ordersOpen = [open sortedArrayUsingDescriptors:@[ byKind, self.latestNumberFirst[0] ]];
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
    if (_changeItem) [each addObject:[NSPredicate predicateWithFormat:@"stockItem == %@", _changeItem]];
    if (_changeLocation) [each addObject:[NSPredicate predicateWithFormat:@"source == %@ OR destination == %@", _changeLocation, _changeLocation]];
    if (![_changeKind isEqualToString:@"All"]) [each addObject:[NSPredicate predicateWithFormat:@"lbKind == %@", _changeKind]];
    if (_changeSince) {
        NSDate *start = [[NSCalendar currentCalendar] startOfDayForDate:_changeSince];
        [each addObject:[NSPredicate predicateWithFormat:@"moment >= %@", start]];
    }
    _changes.filterPredicate = each.count ? [NSCompoundPredicate andPredicateWithSubpredicates:each] : nil;
}

#pragma mark Catalogs and items

- (IBAction)newCatalog:(id)sender {
    if (![self commitEdits]) return;
    Catalog *catalog = [Catalog lb_newCatalogNamed:@"New Catalog" owner:_store.user inContext:self.context];
    /* Listed now: the controller fetches only when asked. */
    [_catalogs addObject:catalog];
    [_catalogs setSelectedObjects:@[ catalog ]];
    [self catalogChosen];
}

- (IBAction)addItem:(id)sender {
    if (![self chosenCatalog] || ![self commitEdits]) return;
    [self addTo:_items named:@"New Item" key:NSStringFromSelector(@selector(itemName)) table:_itemsTable];
    [self itemChosen];
}

- (IBAction)removeItem:(id)sender {
    for (StockItem *item in _items.selectedObjects) [self.context deleteObject:item];
    [self itemChosen];
}

- (IBAction)search:(id)sender {
    NSString *text = _itemSearch.stringValue;
    _items.filterPredicate = text.length ? [NSPredicate predicateWithFormat:@"%K CONTAINS[cd] %@ OR %K CONTAINS[cd] %@ OR %K CONTAINS[cd] %@",
                                                                            NSStringFromSelector(@selector(itemName)), text,
                                                                            NSStringFromSelector(@selector(sku)), text,
                                                                            NSStringFromSelector(@selector(descriptionValue)), text]
                                         : nil;
}

#pragma mark Setup

/* A new row of the controller's, named so under the key, added through it
   (which says what it is of), chosen, its name ready to be typed over in
   the table. */
- (id)addTo:(NSArrayController *)controller named:(NSString *)name key:(NSString *)key table:(NSTableView *)table {
    if (![self commitEdits]) return nil;
    id row = [controller newObject];
    [row setValue:[NSUUID UUID] forKey:@"id"];
    [row setValue:name forKey:key];
    [controller addObject:row];
    [controller setSelectedObjects:@[ row ]];
    NSUInteger index = [controller.arrangedObjects indexOfObjectIdenticalTo:row];
    if (index != NSNotFound) [table editColumn:0 row:(NSInteger)index withEvent:nil select:YES];
    return row;
}

- (void)removeFrom:(NSArrayController *)controller {
    for (NSManagedObject *row in controller.selectedObjects) [self.context deleteObject:row];
    [self catalogChosen];
}

- (IBAction)addWarehouse:(id)sender {
    if ([self chosenCatalog]) [self addTo:_warehouses named:@"New Warehouse" key:NSStringFromSelector(@selector(warehouseName)) table:_warehousesTable];
    [self catalogChosen];
}

- (IBAction)removeWarehouse:(id)sender {
    [self removeFrom:_warehouses];
}

- (IBAction)addLocation:(id)sender {
    if (_warehouses.selectedObjects.count == 1) {
        [self addTo:_warehouseLocations named:@"New Location" key:NSStringFromSelector(@selector(locationName)) table:_locationsTable];
    }
    [self catalogChosen];
}

- (IBAction)removeLocation:(id)sender {
    [self removeFrom:_warehouseLocations];
}

- (IBAction)addCategory:(id)sender {
    if ([self chosenCatalog]) [self addTo:_catalogCategories named:@"New Category" key:NSStringFromSelector(@selector(categoryName)) table:_categoriesTable];
    [self catalogChosen];
}

- (IBAction)removeCategory:(id)sender {
    [self removeFrom:_catalogCategories];
}

- (IBAction)addContact:(id)sender {
    if ([self chosenCatalog]) [self addTo:_contacts named:@"New Contact" key:NSStringFromSelector(@selector(contactName)) table:_contactsTable];
}

- (IBAction)removeContact:(id)sender {
    for (Contact *contact in _contacts.selectedObjects) {
        contact.lb_isCustomer = NO;
        contact.lb_isSupplier = NO;
    }
    [self removeFrom:_contacts];
}

- (IBAction)addKitLine:(id)sender {
    if (![self chosenItem]) return;
    KitLine *line = [_kitLines newObject];
    line.component = _components.firstObject;
    [_kitLines addObject:line];
}

- (IBAction)removeKitLine:(id)sender {
    for (KitLine *line in _kitLines.selectedObjects) [self.context deleteObject:line];
}

/* A new row of the item's, added through the controller, chosen, the
   column's cell ready to be typed. */
- (void)add:(NSManagedObject *)row to:(NSArrayController *)controller editing:(NSInteger)column of:(NSTableView *)table {
    [row setValue:[NSUUID UUID] forKey:@"id"];
    [controller addObject:row];
    [controller setSelectedObjects:@[ row ]];
    NSUInteger index = [controller.arrangedObjects indexOfObjectIdenticalTo:row];
    if (index != NSNotFound) [table editColumn:column row:(NSInteger)index withEvent:nil select:YES];
}

- (IBAction)addSupplierItem:(id)sender {
    StockItem *item = [self chosenItem];
    if (!item || ![self commitEdits]) return;
    NSSet *taken = [item.supplierItems valueForKey:NSStringFromSelector(@selector(supplier))];
    Supplier *supplier = nil;
    for (Supplier *each in _suppliers) {
        if (!supplier && ![taken containsObject:each]) supplier = each;
    }
    if (!supplier) return [self refuse:@"Each supplier has one already: make another contact a supplier in Setup."];
    SupplierItem *bought = [_supplierItems newObject];
    bought.supplier = supplier;
    [self add:bought to:_supplierItems editing:1 of:_supplierItemsTable];
}

- (IBAction)removeSupplierItem:(id)sender {
    for (SupplierItem *bought in _supplierItems.selectedObjects) {
        bought.lb_isPreferred = NO;
        [self.context deleteObject:bought];
    }
}

- (IBAction)addItemCode:(id)sender {
    if (![self chosenItem] || ![self commitEdits]) return;
    ItemCode *code = [_itemCodes newObject];
    code.codeText = @"New Code";
    code.codeKind = _codeKinds.firstObject;
    [self add:code to:_itemCodes editing:0 of:_itemCodesTable];
}

- (IBAction)removeItemCode:(id)sender {
    for (ItemCode *code in _itemCodes.selectedObjects) [self.context deleteObject:code];
}

- (IBAction)addReorderRule:(id)sender {
    StockItem *item = [self chosenItem];
    if (!item || ![self commitEdits]) return;
    NSSet *taken = [item.reorderRules valueForKey:NSStringFromSelector(@selector(warehouse))];
    Warehouse *warehouse = nil;
    for (Warehouse *each in _warehouses.arrangedObjects) {
        if (!warehouse && ![taken containsObject:each]) warehouse = each;
    }
    if (!warehouse) return [self refuse:@"It has a rule at each warehouse already."];
    ReorderRule *rule = [_reorderRules newObject];
    rule.warehouse = warehouse;
    rule.reorderPoint = [NSDecimalNumber zero];
    rule.reorderLevel = [NSDecimalNumber zero];
    [self add:rule to:_reorderRules editing:1 of:_reorderRulesTable];
}

- (IBAction)removeReorderRule:(id)sender {
    for (ReorderRule *rule in _reorderRules.selectedObjects) [self.context deleteObject:rule];
}

#pragma mark Stock

/* What was typed as a quantity: a decimal number; nil, said, otherwise. */
- (NSDecimalNumber *)typedQuantity {
    return [self typed:_stockQuantity];
}

- (NSDecimalNumber *)typed:(NSString *)text {
    NSDecimalNumber *quantity = text.length ? [NSDecimalNumber decimalNumberWithString:text locale:[NSLocale currentLocale]] : nil;
    if (!quantity || quantity == [NSDecimalNumber notANumber]) {
        [self refuse:@"Say how many: a number."];
        return nil;
    }
    return quantity;
}

- (void)refuse:(NSString *)why {
    [self reportError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationErrorMinimum
                                      userInfo:@{ NSLocalizedDescriptionKey: why }]];
}

- (IBAction)adjust:(id)sender {
    StockItem *item = [self chosenItem];
    NSDecimalNumber *quantity = [self typedQuantity];
    if (!item || !quantity) return;
    if (!_stockAt) return [self refuse:@"Choose where."];
    NSMutableDictionary *parameters = [@{ @"Quantity": quantity, @"At": _stockAt, @"Reason": _stockReason ?: @"Other" } mutableCopy];
    [self performAction:@"Adjust" on:item parameters:parameters];
}

- (IBAction)transfer:(id)sender {
    StockItem *item = [self chosenItem];
    NSDecimalNumber *quantity = [self typedQuantity];
    if (!item || !quantity) return;
    if (!_stockAt || !_stockTo) return [self refuse:@"Choose where from, and where to."];
    [self performAction:@"Transfer" on:item parameters:@{ @"Quantity": quantity, @"From": _stockAt, @"To": _stockTo }];
}

- (void)assembling:(BOOL)apart {
    StockItem *item = [self chosenItem];
    NSDecimalNumber *quantity = [self typedQuantity];
    if (!item || !quantity) return;
    if (!_stockAt) return [self refuse:@"Choose where."];
    [self performAction:@"Assemble" on:item parameters:@{ @"Batches": quantity, @"At": _stockAt, @"Disassemble": @(apart) }];
}

- (IBAction)assemble:(id)sender {
    [self assembling:NO];
}

- (IBAction)disassemble:(id)sender {
    [self assembling:YES];
}

#pragma mark Counts

- (void)setShowsExpected:(BOOL)shows {
    _showsExpected = shows;
    for (LBCountRow *row in _rowsCounted) row.showsExpected = shows;
}

- (LBCountRow *)rowOf:(StockItem *)item at:(Location *)place {
    LBCountRow *row = [[LBCountRow alloc] init];
    row.item = item;
    row.location = place;
    row.showsExpected = _showsExpected;
    return row;
}

- (IBAction)startCount:(id)sender {
    if (!_countPlace || ![self commitEdits]) return;
    _counting = _countPlace;
    NSMutableArray *rows = [NSMutableArray array];
    for (Location *place in _counting.locations) {
        NSArray *holdings = [place.holdings.allObjects sortedArrayUsingDescriptors:self.byItem];
        for (Holding *holding in holdings) {
            if (holding.stockItem) [rows addObject:[self rowOf:holding.stockItem at:place]];
        }
    }
    self.countLocations = _counting.locations;
    self.rowsCounted = rows;
}

- (IBAction)addCountRow:(id)sender {
    if (!_counting) return [self refuse:@"Start a count first."];
    if (![self commitEdits]) return;
    LBCountRow *row = [self rowOf:_catalogItems.firstObject at:_countLocations.firstObject];
    self.rowsCounted = [_rowsCounted arrayByAddingObject:row];
    [_countRows setSelectedObjects:@[ row ]];
}

- (IBAction)removeCountRow:(id)sender {
    NSMutableArray *rows = [_rowsCounted mutableCopy];
    [rows removeObjectsInArray:_countRows.selectedObjects];
    self.rowsCounted = rows;
}

- (IBAction)postCount:(id)sender {
    if (!_counting || ![self commitEdits]) return;
    NSMutableArray *found = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (LBCountRow *row in _rowsCounted) {
        if (!row.item || !row.location || !row.found) return [self refuse:@"Type what was found of each (0 for none)."];
        NSString *key = [NSString stringWithFormat:@"%@ %@", row.item.id, row.location.id];
        if ([seen containsObject:key]) {
            return [self refuse:[NSString stringWithFormat:@"%@ at %@ is counted twice.", row.item.lbTitle, row.location.lbTitle]];
        }
        [seen addObject:key];
        [found addObject:@{ @"Item": row.item.id.UUIDString, @"Location": row.location.id.UUIDString, @"Quantity": row.found }];
    }
    NSMutableDictionary *parameters = [@{ @"Found": found } mutableCopy];
    if (_counting.location) parameters[@"Location"] = _counting.location;
    id count = [self performAction:@"Count" on:_counting.warehouse parameters:parameters];
    if (!count) return;
    _counting = nil;
    self.rowsCounted = @[];
    if ([count isKindOfClass:[StockCount class]]) [_stockCounts setSelectedObjects:@[ count ]];
}

#pragma mark The overview

- (IBAction)reorder:(id)sender {
    NSMutableOrderedSet *warehouses = [NSMutableOrderedSet orderedSet];
    for (ReorderRule *rule in _rulesDue) {
        if (rule.warehouse) [warehouses addObject:rule.warehouse];
    }
    NSMutableArray *drafts = [NSMutableArray array];
    for (Warehouse *warehouse in warehouses) {
        id made = [self performAction:@"Reorder" on:warehouse parameters:nil];
        if (!made) return;
        if ([made isKindOfClass:[NSArray class]]) [drafts addObjectsFromArray:made];
    }
    [_tabs selectTabViewItemWithIdentifier:@"purchaseOrders"];
    if (drafts.count) [_purchaseOrders setSelectedObjects:@[ drafts.firstObject ]];
}

- (IBAction)showOrder:(id)sender {
    NSManagedObject *order = _openOrders.selectedObjects.firstObject;
    BOOL sale = [order isKindOfClass:[SaleOrder class]];
    if (!order) return;
    [_tabs selectTabViewItemWithIdentifier:sale ? @"saleOrders" : @"purchaseOrders"];
    [sale ? _saleOrders : _purchaseOrders setSelectedObjects:@[ order ]];
}

#pragma mark Orders

- (NSArray<NSSortDescriptor *> *)latestNumberFirst {
    return @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(runningNumber)) ascending:NO] ];
}

- (NSArray<NSSortDescriptor *> *)linesInOrder {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"lbLineOrder" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

/* A new order of the catalog's, made by the procedure (numbered, a draft),
   listed by the content set it joined, chosen. */
- (void)choose:(NSManagedObject *)order in:(NSArrayController *)controller {
    [self.context processPendingChanges];
    [controller rearrangeObjects];
    [controller setSelectedObjects:@[ order ]];
}

- (IBAction)newSale:(id)sender {
    Catalog *catalog = [self chosenCatalog];
    if (!catalog || ![self commitEdits]) return;
    if (!_customers.count) return [self refuse:@"No customer to sell to: make a contact a customer in Setup."];
    [self choose:[catalog lb_newSaleOrderTo:_customers.firstObject on:[NSDate date]] in:_saleOrders];
}

- (IBAction)newPurchase:(id)sender {
    Catalog *catalog = [self chosenCatalog];
    if (!catalog || ![self commitEdits]) return;
    if (!_suppliers.count) return [self refuse:@"No supplier to buy from: make a contact a supplier in Setup."];
    [self choose:[catalog lb_newPurchaseOrderFrom:_suppliers.firstObject on:[NSDate date]] in:_purchaseOrders];
}

/* Only a draft not saved yet is removed; others are cancelled. */
- (void)removeOrdersOf:(NSArrayController *)controller {
    for (NSManagedObject *order in controller.selectedObjects) {
        if (!order.isInserted) return [self refuse:@"This order is saved: cancel it instead."];
    }
    for (NSManagedObject *order in controller.selectedObjects) [self.context deleteObject:order];
}

- (IBAction)removeSale:(id)sender {
    [self removeOrdersOf:_saleOrders];
}

- (IBAction)removePurchase:(id)sender {
    [self removeOrdersOf:_purchaseOrders];
}

- (IBAction)addSaleLine:(id)sender {
    if (_saleOrders.selectedObjects.count != 1 || ![self commitEdits]) return;
    StockItem *item = _catalogItems.firstObject;
    SaleLine *line = [_saleLines newObject];
    line.id = [NSUUID UUID];
    line.quantity = [NSDecimalNumber one];
    line.stockItem = item;
    line.linePriceAmount = item.priceAmount;
    line.linePriceCurrency = item.priceCurrency;
    [_saleLines addObject:line];
    [_saleLines setSelectedObjects:@[ line ]];
}

- (IBAction)addPurchaseLine:(id)sender {
    if (_purchaseOrders.selectedObjects.count != 1 || ![self commitEdits]) return;
    StockItem *item = _catalogItems.firstObject;
    PurchaseLine *line = [_purchaseLines newObject];
    line.id = [NSUUID UUID];
    line.quantity = [NSDecimalNumber one];
    line.stockItem = item;
    line.lineUnitCostAmount = item.unitCostAmount;
    line.lineUnitCostCurrency = item.unitCostCurrency;
    [_purchaseLines addObject:line];
    [_purchaseLines setSelectedObjects:@[ line ]];
}

- (IBAction)removeSaleLine:(id)sender {
    for (SaleLine *line in _saleLines.selectedObjects) {
        NSError *error = nil;
        if (![line lb_delete:&error]) return [self reportError:error];
    }
}

- (IBAction)removePurchaseLine:(id)sender {
    for (PurchaseLine *line in _purchaseLines.selectedObjects) {
        if (line.moves.count) return [self refuse:@"Some of it has been received: it stays."];
        [self.context deleteObject:line];
    }
}

/* The chosen order's action of the name. */
- (void)act:(NSString *)name on:(NSArrayController *)controller {
    NSManagedObject *order = controller.selectedObjects.count == 1 ? controller.selectedObjects[0] : nil;
    if (order) [self performAction:name on:order parameters:nil];
}

- (IBAction)confirmSale:(id)sender { [self act:@"Confirm" on:_saleOrders]; }
- (IBAction)closeSale:(id)sender { [self act:@"Close" on:_saleOrders]; }
- (IBAction)cancelSale:(id)sender { [self act:@"Cancel" on:_saleOrders]; }
- (IBAction)reopenSale:(id)sender { [self act:@"Reopen" on:_saleOrders]; }
- (IBAction)confirmPurchase:(id)sender { [self act:@"Confirm" on:_purchaseOrders]; }
- (IBAction)closePurchase:(id)sender { [self act:@"Close" on:_purchaseOrders]; }
- (IBAction)cancelPurchase:(id)sender { [self act:@"Cancel" on:_purchaseOrders]; }
- (IBAction)reopenPurchase:(id)sender { [self act:@"Reopen" on:_purchaseOrders]; }

/* Lines as Ship and Receive take them: by id, how many. */
- (NSDictionary *)linesParameter:(NSDictionary<NSManagedObjectID *, NSArray *> *)chosen {
    NSMutableDictionary *lines = [NSMutableDictionary dictionary];
    for (NSArray *each in chosen.allValues) lines[[[each[0] valueForKey:@"id"] UUIDString]] = each[1];
    return lines;
}

/* The chosen line, so many of it (as typed), shipped from or received at
   the location chosen. */
- (void)moveLineOf:(NSArrayController *)orders lines:(NSArrayController *)lines action:(NSString *)name place:(NSString *)place {
    NSManagedObject *order = orders.selectedObjects.count == 1 ? orders.selectedObjects[0] : nil;
    NSManagedObject *line = lines.selectedObjects.count == 1 ? lines.selectedObjects[0] : nil;
    if (!order || !line) return [self refuse:@"Choose a line."];
    NSDecimalNumber *quantity = [self typed:_orderQuantity];
    if (!quantity) return;
    if (!_orderAt) return [self refuse:@"Choose where."];
    [self performAction:name on:order parameters:@{ @"Lines": [self linesParameter:@{ line.objectID: @[ line, quantity ] }], place: _orderAt }];
}

- (IBAction)shipLine:(id)sender {
    [self moveLineOf:_saleOrders lines:_saleLines action:@"Ship" place:@"From"];
}

- (IBAction)receiveLine:(id)sender {
    [self moveLineOf:_purchaseOrders lines:_purchaseLines action:@"Receive" place:@"At"];
}

/* Every line's outstanding shipped: as much as the location holds of each
   (a phantom kit's line goes as its components'). */
- (IBAction)shipOutstanding:(id)sender {
    SaleOrder *order = _saleOrders.selectedObjects.count == 1 ? _saleOrders.selectedObjects[0] : nil;
    if (!order) return;
    if (!_orderAt) return [self refuse:@"Choose where from."];
    NSMutableDictionary *chosen = [NSMutableDictionary dictionary];
    for (SaleLine *line in order.saleLines) {
        if (line.stockItem.isAPhantomKit || !line.backorderedQuantity) continue;
        NSDecimalNumber *held = [_orderAt lb_heldOf:line.stockItem];
        NSDecimalNumber *quantity = [held compare:line.backorderedQuantity] == NSOrderedAscending ? held : line.backorderedQuantity;
        if ([quantity compare:[NSDecimalNumber zero]] == NSOrderedDescending) chosen[line.objectID] = @[ line, quantity ];
    }
    if (!chosen.count) return [self refuse:@"Nothing outstanding is held there."];
    [self performAction:@"Ship" on:order parameters:@{ @"Lines": [self linesParameter:chosen], @"From": _orderAt }];
}

/* Every line's outstanding received at the location. */
- (IBAction)receiveOutstanding:(id)sender {
    PurchaseOrder *order = _purchaseOrders.selectedObjects.count == 1 ? _purchaseOrders.selectedObjects[0] : nil;
    if (!order) return;
    if (!_orderAt) return [self refuse:@"Choose where."];
    NSMutableDictionary *chosen = [NSMutableDictionary dictionary];
    for (PurchaseLine *line in order.purchaseLines) {
        if (line.outstandingQuantity) chosen[line.objectID] = @[ line, line.outstandingQuantity ];
    }
    if (!chosen.count) return [self refuse:@"Nothing is outstanding."];
    [self performAction:@"Receive" on:order parameters:@{ @"Lines": [self linesParameter:chosen], @"At": _orderAt }];
}

#pragma mark The server

- (id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(NSDictionary *)parameters {
    if (![self commitEdits]) return nil;
    if (self.context.hasChanges && ![self saveChanges]) return nil;
    NSError *error = nil;
    ODataOperationCall *call = [ODataOperationCall callOfOperation:name onObject:object];
    call.parameters = parameters;
    id result = [call invoke:&error];
    [self readAgain];
    if (result) _lastError = nil;
    else [self reportError:error];
    return result;
}

- (void)readAgain {
    NSArray *chosen = _items.selectedObjects;
    for (NSManagedObject *object in self.context.registeredObjects.allObjects) {
        if (!object.hasChanges) [self.context refreshObject:object mergeChanges:NO];
    }
    /* What shows the chosen catalog and item asks for them again. */
    NSString *selection = NSStringFromSelector(@selector(selection));
    [_catalogs willChangeValueForKey:selection];
    [_catalogs didChangeValueForKey:selection];
    [_items willChangeValueForKey:selection];
    [_items didChangeValueForKey:selection];
    for (NSArrayController *controller in @[ _saleOrders, _purchaseOrders ]) {
        [controller willChangeValueForKey:selection];
        [controller didChangeValueForKey:selection];
    }
    for (NSArrayController *controller in @[ _holdings, _moves, _saleLines, _shipments, _purchaseLines, _receipts, _supplierItems, _itemCodes,
                                            _reorderRules, _countMoves ]) {
        [controller rearrangeObjects];
    }
    /* The moves read again too: an action made some. */
    _movesOf = nil;
    [self catalogChosen];
    NSMutableArray *still = [NSMutableArray array];
    for (StockItem *item in chosen) {
        if (!item.isDeleted && item.managedObjectContext) [still addObject:item];
    }
    if (still.count) [_items setSelectedObjects:still];
}

- (BOOL)commitEdits {
    if (![self.window makeFirstResponder:nil]) return NO;
    for (NSArrayController *controller in @[ _catalogs, _items, _kitLines, _warehouses, _warehouseLocations, _catalogCategories, _contacts,
                                            _saleOrders, _saleLines, _purchaseOrders, _purchaseLines, _supplierItems, _itemCodes, _reorderRules,
                                            _countRows ]) {
        if (![controller commitEditing]) return NO;
    }
    return YES;
}

/* An amount typed with no currency (an item's, a line's): the catalog's. */
- (void)completeMoney {
    NSMutableSet *changed = [NSMutableSet setWithSet:self.context.insertedObjects];
    [changed unionSet:self.context.updatedObjects];
    for (NSManagedObject *object in changed) {
        if ([object isKindOfClass:[SaleLine class]]) {
            SaleLine *line = (SaleLine *)object;
            if (line.linePriceAmount && !line.linePriceCurrency) line.linePriceCurrency = line.saleOrder.catalog.currency ?: _store.user.currency;
            continue;
        }
        if ([object isKindOfClass:[PurchaseLine class]]) {
            PurchaseLine *line = (PurchaseLine *)object;
            if (line.lineUnitCostAmount && !line.lineUnitCostCurrency) {
                line.lineUnitCostCurrency = line.purchaseOrder.catalog.currency ?: _store.user.currency;
            }
            continue;
        }
        if ([object isKindOfClass:[SupplierItem class]]) {
            SupplierItem *bought = (SupplierItem *)object;
            if (bought.supplierCostAmount && !bought.supplierCostCurrency) {
                bought.supplierCostCurrency = bought.stockItem.catalog.currency ?: _store.user.currency;
            }
            continue;
        }
        if (![object isKindOfClass:[StockItem class]]) continue;
        StockItem *item = (StockItem *)object;
        NSString *currency = item.catalog.currency ?: _store.user.currency;
        if (item.priceAmount && !item.priceCurrency) item.priceCurrency = currency;
        if (item.unitCostAmount && !item.unitCostCurrency) item.unitCostCurrency = currency;
    }
}

- (BOOL)saveChanges {
    [self completeMoney];
    NSError *error = nil;
    if ([_store save:&error]) {
        _lastError = nil;
        return YES;
    }
    NSArray *each = error.userInfo[NSDetailedErrorsKey];
    if (each.count) {
        NSString *said = [[each valueForKey:NSStringFromSelector(@selector(localizedDescription))] componentsJoinedByString:@"\n"];
        error = [NSError errorWithDomain:error.domain code:error.code
                                userInfo:@{ NSLocalizedDescriptionKey: @"The changes break the stock's rules",
                                            NSLocalizedRecoverySuggestionErrorKey: said }];
    }
    [self reportError:error];
    return NO;
}

- (void)reportError:(NSError *)error {
    _lastError = error;
    if (error && !_quiet) [self presentError:error];
}

- (IBAction)save:(id)sender {
    if (![self commitEdits]) return;
    if ([self saveChanges]) [self readAgain];
    [self catalogChosen];
}

- (IBAction)revertChanges:(id)sender {
    [self.window makeFirstResponder:nil];
    [self.context rollback];
    [self catalogChosen];
}

- (BOOL)shouldClose {
    if (![self commitEdits]) return NO;
    if (!self.context.hasChanges) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save the changes before closing?";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Don't Save"];
    NSModalResponse answer = [alert runModal];
    if (answer == NSAlertSecondButtonReturn) return NO;
    if (answer == NSAlertThirdButtonReturn) return YES;
    return [self saveChanges];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    return [self shouldClose];
}

@end

@implementation LBStockItemController

- (id)newObject {
    StockItem *item = [super newObject];
    item.id = [NSUUID UUID];
    item.created = [NSDate date];
    item.itemName = @"New Item";
    /* Its SKU before it is shown: the next of the catalog's. Its catalog
       is the content set's: adding it to the controller adds it there. */
    item.sku = [[_windowController chosenCatalog] lb_nextSKU];
    return item;
}

@end

@implementation LBKitLineController

- (id)newObject {
    KitLine *line = [super newObject];
    line.id = [NSUUID UUID];
    line.perBatch = [NSDecimalNumber one];
    return line;
}

@end
