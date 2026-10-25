#import "LBStockItemWindowController.h"
#import "LBStore.h"
#import "LBStockDisplay.h"

@interface LBStockItemWindowController ()
@property (nonatomic, readwrite, copy) NSArray<Holding *> *holdings;
@property (nonatomic, readwrite, copy) NSArray<Move *> *moves;
@property (nonatomic, readwrite, copy) NSArray<KitLine *> *kitLines;
@property (nonatomic, readwrite, copy) NSArray<SupplierItem *> *supplierItems;
@property (nonatomic, readwrite, copy) NSArray<ItemCode *> *itemCodes;
@property (nonatomic, readwrite, copy) NSArray<ReorderRule *> *reorderRules;
@property (nonatomic, readwrite, copy) NSArray<Category *> *categories;
@property (nonatomic, readwrite, copy) NSArray<Supplier *> *suppliers;
@property (nonatomic, readwrite, copy) NSArray<Location *> *locations;
@property (nonatomic, readwrite, copy) NSArray<StockItem *> *components;
@property (nonatomic, readwrite, copy) NSArray<Warehouse *> *catalogWarehouses;
@property (nonatomic, readwrite, copy) NSArray<WeightUnit *> *weightUnits;
@property (nonatomic, readwrite, copy) NSArray<SizeUnit *> *sizeUnits;
@end

@implementation LBStockItemWindowController

- (instancetype)initWithStore:(LBStore *)store item:(StockItem *)item catalog:(Catalog *)catalog {
    if ((self = [super initWithStore:store windowNibName:@"StockItem"])) {
        self.catalog = [self own:catalog];
        _item = [self own:item];
        if (!_item) {
            _item = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([StockItem class])
                                                  inManagedObjectContext:self.context];
            _item.id = [NSUUID UUID];
            _item.created = [NSDate date];
            _item.itemName = @"New Item";
            _item.catalog = self.catalog;
            _item.sku = [self.catalog lb_nextSKU];
        }
        _holdings = @[];
        _moves = @[];
        _kitLines = @[];
        _supplierItems = @[];
        _itemCodes = @[];
        _reorderRules = @[];
        _categories = @[];
        _suppliers = @[];
        _locations = @[];
        _components = @[];
        _catalogWarehouses = @[];
        _weightUnits = @[];
        _sizeUnits = @[];
        _reasons = @[ @"Opening", @"Found", @"Damaged", @"Lost", @"Expired", @"Other" ];
        _stockReason = @"Opening";
        _codeKinds = @[ @"GTIN", @"Code 128", @"QR", @"EPC", @"Other" ];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self.window bind:NSTitleBinding toObject:self withKeyPath:@"item.itemName" options:nil];
}

#pragma mark Reading

static NSPredicate *LBOf(NSString *key, id object) {
    return [NSPredicate predicateWithFormat:@"%K == %@", key, object];
}

- (void)readAgain {
    if (_item.isInserted) {
        /* Not on the server yet: nothing is of it but what is here. */
        self.supplierItems = _item.supplierItems.allObjects;
        self.kitLines = _item.kitLinesAsKit.allObjects;
        self.itemCodes = _item.itemCodes.allObjects;
        self.reorderRules = _item.reorderRules.allObjects;
    } else {
        [self readOwn];
    }
    [self readChoices];
    /* Its fields, bound through the item, read it again. */
    [self willChangeValueForKey:@"item"];
    [self didChangeValueForKey:@"item"];
}

/* What is of the item, as the server has it. */
- (void)readOwn {
    [self fetch:[StockItem class] where:LBOf(@"id", _item.id) sortedBy:nil];
    NSSortDescriptor *latest = [NSSortDescriptor sortDescriptorWithKey:@"moment" ascending:NO];
    self.holdings = [self fetch:[Holding class] where:LBOf(@"stockItem", _item)
                       sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"lbLocationTitle" ascending:YES] ]];
    self.moves = [self fetch:[Move class] where:LBOf(@"stockItem", _item) sortedBy:@[ latest ]];
    self.kitLines = [self fetch:[KitLine class] where:LBOf(@"kit", _item)
                       sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"component.itemName" ascending:YES] ]];
    [self listSupplierItems];
    self.itemCodes = [self fetch:[ItemCode class] where:LBOf(@"stockItem", _item)
                        sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"codeText" ascending:YES] ]];
    self.reorderRules = [self fetch:[ReorderRule class] where:LBOf(@"stockItem", _item)
                           sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"warehouse.lbTitle" ascending:YES] ]];
}

/* What its forms choose from. */
- (void)readChoices {
    Catalog *catalog = self.catalog;
    NSPredicate *ofCatalog = LBOf(@"catalog", catalog);
    self.categories = [self fetch:[Category class] where:ofCatalog sortedBy:self.byTitle];
    self.suppliers = [self fetch:[Supplier class] where:ofCatalog sortedBy:self.byTitle];
    self.catalogWarehouses = [self fetch:[Warehouse class] where:ofCatalog sortedBy:self.byTitle];
    self.locations = [self fetch:[Location class] where:LBOf(@"warehouse.catalog", catalog) sortedBy:self.byTitle];
    NSMutableArray *others = [[self fetch:[StockItem class] where:ofCatalog sortedBy:self.byTitle] mutableCopy];
    [others removeObject:_item];
    self.components = others;
    if (!_weightUnits.count) self.weightUnits = [self units:[WeightUnit class]];
    if (!_sizeUnits.count) self.sizeUnits = [self units:[SizeUnit class]];
    if (![_locations containsObject:_stockAt]) self.stockAt = _locations.firstObject;
    if (![_locations containsObject:_stockTo]) self.stockTo = _locations.count > 1 ? _locations[1] : _locations.firstObject;
    [self willChangeValueForKey:@"preferredSupplier"];
    [self didChangeValueForKey:@"preferredSupplier"];
}

/* The units of the class, the largest first. */
- (NSArray *)units:(Class)cls {
    return [self fetch:cls where:nil sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"factor" ascending:NO] ]];
}

- (void)listSupplierItems {
    if (_item.isInserted) {
        self.supplierItems = _item.supplierItems.allObjects;
        return;
    }
    self.supplierItems = [self fetch:[SupplierItem class] where:LBOf(@"stockItem", _item)
                            sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"supplier.lbTitle" ascending:YES] ]];
}

- (Supplier *)preferredSupplier {
    return _item.lb_preferredSupplier;
}

- (void)setPreferredSupplier:(Supplier *)supplier {
    _item.lb_preferredSupplier = supplier;
    [self listSupplierItems];
}

- (NSArray<NSArrayController *> *)editedControllers {
    return @[ _kitLineList, _supplierItemList, _itemCodeList, _reorderRuleList ];
}

#pragma mark Stock

- (IBAction)adjust:(id)sender {
    NSDecimalNumber *quantity = [self typed:_stockQuantity];
    if (!quantity) return;
    if (!_stockAt) return [self refuse:@"Choose where."];
    [self performAction:@"Adjust" on:_item parameters:@{ @"Quantity": quantity, @"At": _stockAt, @"Reason": _stockReason ?: @"Other" }];
}

- (IBAction)transfer:(id)sender {
    NSDecimalNumber *quantity = [self typed:_stockQuantity];
    if (!quantity) return;
    if (!_stockAt || !_stockTo) return [self refuse:@"Choose where from, and where to."];
    [self performAction:@"Transfer" on:_item parameters:@{ @"Quantity": quantity, @"From": _stockAt, @"To": _stockTo }];
}

- (void)assembling:(BOOL)apart {
    NSDecimalNumber *quantity = [self typed:_stockQuantity];
    if (!quantity) return;
    if (!_stockAt) return [self refuse:@"Choose where."];
    [self performAction:@"Assemble" on:_item parameters:@{ @"Batches": quantity, @"At": _stockAt, @"Disassemble": @(apart) }];
}

- (IBAction)assemble:(id)sender {
    [self assembling:NO];
}

- (IBAction)disassemble:(id)sender {
    [self assembling:YES];
}

#pragma mark Its tables

/* A new row of the item's: listed, chosen, the column's cell ready to be
   typed. */
- (void)add:(NSManagedObject *)row list:(NSString *)key to:(NSArrayController *)controller editing:(NSInteger)column of:(NSTableView *)table {
    [self setValue:[[self valueForKey:key] arrayByAddingObject:row] forKey:key];
    [controller setSelectedObjects:@[ row ]];
    NSUInteger index = [controller.arrangedObjects indexOfObjectIdenticalTo:row];
    if (table && index != NSNotFound) [table editColumn:column row:(NSInteger)index withEvent:nil select:YES];
}

/* A new object of the class, of the item, its key given. */
- (id)newOf:(Class)cls {
    NSManagedObject *made = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass(cls) inManagedObjectContext:self.context];
    [made setValue:[NSUUID UUID] forKey:@"id"];
    return made;
}

/* The chosen ones of the controller deleted, and no longer listed. */
- (void)remove:(NSArrayController *)controller list:(NSString *)key {
    NSArray *chosen = controller.selectedObjects;
    for (NSManagedObject *row in chosen) [self.context deleteObject:row];
    NSMutableArray *left = [[self valueForKey:key] mutableCopy];
    [left removeObjectsInArray:chosen];
    [self setValue:left forKey:key];
}

- (IBAction)addKitLine:(id)sender {
    if (![self commitEdits]) return;
    KitLine *line = [self newOf:[KitLine class]];
    line.kit = _item;
    line.component = _components.firstObject;
    line.perBatch = [NSDecimalNumber one];
    [self add:line list:@"kitLines" to:_kitLineList editing:1 of:nil];
}

- (IBAction)removeKitLine:(id)sender {
    [self remove:_kitLineList list:@"kitLines"];
}

- (IBAction)addSupplierItem:(id)sender {
    if (![self commitEdits]) return;
    NSArray *taken = [_supplierItems valueForKey:@"supplier"];
    Supplier *supplier = nil;
    for (Supplier *each in _suppliers) {
        if (!supplier && ![taken containsObject:each]) supplier = each;
    }
    if (!supplier) return [self refuse:@"Each supplier has one already: make another contact a supplier in the catalog's settings."];
    SupplierItem *bought = [self newOf:[SupplierItem class]];
    bought.stockItem = _item;
    bought.supplier = supplier;
    [self add:bought list:@"supplierItems" to:_supplierItemList editing:1 of:_supplierItemsTable];
}

- (IBAction)removeSupplierItem:(id)sender {
    for (SupplierItem *bought in _supplierItemList.selectedObjects) bought.lb_isPreferred = NO;
    [self remove:_supplierItemList list:@"supplierItems"];
}

- (IBAction)addItemCode:(id)sender {
    if (![self commitEdits]) return;
    ItemCode *code = [self newOf:[ItemCode class]];
    code.stockItem = _item;
    code.codeText = @"New Code";
    code.codeKind = _codeKinds.firstObject;
    [self add:code list:@"itemCodes" to:_itemCodeList editing:0 of:_itemCodesTable];
}

- (IBAction)removeItemCode:(id)sender {
    [self remove:_itemCodeList list:@"itemCodes"];
}

- (IBAction)addReorderRule:(id)sender {
    if (![self commitEdits]) return;
    NSArray *taken = [_reorderRules valueForKey:@"warehouse"];
    Warehouse *warehouse = nil;
    for (Warehouse *each in _catalogWarehouses) {
        if (!warehouse && ![taken containsObject:each]) warehouse = each;
    }
    if (!warehouse) return [self refuse:@"It has a rule at each warehouse already."];
    ReorderRule *rule = [self newOf:[ReorderRule class]];
    rule.stockItem = _item;
    rule.warehouse = warehouse;
    rule.reorderPoint = [NSDecimalNumber zero];
    rule.reorderLevel = [NSDecimalNumber zero];
    [self add:rule list:@"reorderRules" to:_reorderRuleList editing:1 of:_reorderRulesTable];
}

- (IBAction)removeReorderRule:(id)sender {
    [self remove:_reorderRuleList list:@"reorderRules"];
}

@end
