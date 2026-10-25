#import "LBStockWindowController.h"
#import "LBStore.h"
#import "LBStockDisplay.h"
#import <ODataIncrementalStore/ODataOperationCall.h>

static void *LBCatalogChosen = &LBCatalogChosen;
static void *LBItemChosen = &LBItemChosen;

@implementation LBStockWindowController

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
    for (NSArrayController *controller in @[ _holdings, _moves, _saleLines, _shipments, _purchaseLines, _receipts ]) {
        [controller rearrangeObjects];
    }
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
                                            _saleOrders, _saleLines, _purchaseOrders, _purchaseLines ]) {
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
