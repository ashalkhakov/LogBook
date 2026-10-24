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
    NSMutableArray *places = [NSMutableArray array];
    for (Warehouse *warehouse in catalog.warehouses) [places addObjectsFromArray:warehouse.locations.allObjects];
    [self willChangeValueForKey:@"locations"];
    _locations = [places sortedArrayUsingDescriptors:byTitle];
    [self didChangeValueForKey:@"locations"];
    if (![_locations containsObject:_stockAt]) self.stockAt = _locations.firstObject;
    if (![_locations containsObject:_stockTo]) self.stockTo = _locations.count > 1 ? _locations[1] : _locations.firstObject;
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
    StockItem *item = [_items newObject];
    [_items addObject:item];
    [_items setSelectedObjects:@[ item ]];
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
                                                                            NSStringFromSelector(@selector(tag)), text,
                                                                            NSStringFromSelector(@selector(descriptionValue)), text]
                                         : nil;
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
    NSDecimalNumber *quantity = _stockQuantity.length
        ? [NSDecimalNumber decimalNumberWithString:_stockQuantity locale:[NSLocale currentLocale]]
        : nil;
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
    [_holdings rearrangeObjects];
    [_moves rearrangeObjects];
    [self catalogChosen];
    NSMutableArray *still = [NSMutableArray array];
    for (StockItem *item in chosen) {
        if (!item.isDeleted && item.managedObjectContext) [still addObject:item];
    }
    if (still.count) [_items setSelectedObjects:still];
}

- (BOOL)commitEdits {
    if (![self.window makeFirstResponder:nil]) return NO;
    for (NSArrayController *controller in @[ _catalogs, _items, _kitLines ]) {
        if (![controller commitEditing]) return NO;
    }
    return YES;
}

/* An amount typed with no currency: the catalog's. */
- (void)completeMoney {
    NSMutableSet *changed = [NSMutableSet setWithSet:self.context.insertedObjects];
    [changed unionSet:self.context.updatedObjects];
    for (NSManagedObject *object in changed) {
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
    /* Its catalog is the content set's: adding it to the controller adds
       it there. */
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
