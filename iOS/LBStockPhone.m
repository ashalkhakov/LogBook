#import "LBStockPhone.h"
#import "User+CoreDataClass.h"

NSString * const LBCatalogDefaultsKey = @"LBCatalog";

@implementation LBStockPhone
@synthesize catalog = _catalog;

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithStore:(LBLocalStore *)store {
    if ((self = [super init])) _store = store;
    return self;
}

#pragma mark Reading

static NSArray<NSSortDescriptor *> *LBByTitle(void) {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"lbTitle" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

static NSArray<NSSortDescriptor *> *LBLatestNumberFirst(void) {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"runningNumber" ascending:NO] ];
}

/* The objects of the class the predicate takes, those deleted here left
   out, sorted so. */
- (NSArray *)fetch:(Class)cls where:(NSPredicate *)predicate sortedBy:(NSArray<NSSortDescriptor *> *)order {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    request.predicate = predicate;
    NSArray *found = [_store.context executeFetchRequest:request error:NULL] ?: @[];
    found = [found filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDeleted == NO"]];
    return order ? [found sortedArrayUsingDescriptors:order] : found;
}

- (NSPredicate *)ofCatalog {
    return [NSPredicate predicateWithFormat:@"catalog == %@", _catalog];
}

- (NSArray<Catalog *> *)catalogs {
    return [self fetch:[Catalog class] where:nil sortedBy:LBByTitle()];
}

- (Catalog *)catalog {
    if (_catalog && !_catalog.isDeleted && _catalog.managedObjectContext) return _catalog;
    NSArray *catalogs = [self catalogs];
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:LBCatalogDefaultsKey];
    for (Catalog *catalog in catalogs) {
        if ([catalog.id.UUIDString isEqualToString:chosen]) _catalog = catalog;
    }
    if (!_catalog) _catalog = catalogs.firstObject;
    return _catalog;
}

- (void)setCatalog:(Catalog *)catalog {
    _catalog = catalog;
    [[NSUserDefaults standardUserDefaults] setObject:catalog.id.UUIDString forKey:LBCatalogDefaultsKey];
}

- (NSArray<StockItem *> *)itemsMatching:(NSString *)text {
    if (!self.catalog) return @[];
    NSPredicate *predicate = self.ofCatalog;
    if (text.length) {
        NSPredicate *matching = [NSPredicate predicateWithFormat:@"itemName CONTAINS[cd] %@ OR sku CONTAINS[cd] %@ OR descriptionValue CONTAINS[cd] %@",
                                                                 text, text, text];
        predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[ predicate, matching ]];
    }
    return [self fetch:[StockItem class] where:predicate
              sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"itemName" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ]];
}

- (NSArray<Location *> *)locations {
    if (!self.catalog) return @[];
    return [self fetch:[Location class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@", _catalog] sortedBy:LBByTitle()];
}

- (NSArray<Warehouse *> *)warehouses {
    if (!self.catalog) return @[];
    return [self fetch:[Warehouse class] where:self.ofCatalog sortedBy:LBByTitle()];
}

- (NSArray<SaleOrder *> *)saleOrders {
    if (!self.catalog) return @[];
    return [self fetch:[SaleOrder class] where:self.ofCatalog sortedBy:LBLatestNumberFirst()];
}

- (NSArray<PurchaseOrder *> *)purchaseOrders {
    if (!self.catalog) return @[];
    return [self fetch:[PurchaseOrder class] where:self.ofCatalog sortedBy:LBLatestNumberFirst()];
}

- (NSArray<LBCountPlace *> *)countPlaces {
    return [LBCountPlace placesOf:[self warehouses] locations:[self locations]];
}

- (NSArray<Holding *> *)holdingsOf:(StockItem *)item {
    return [self fetch:[Holding class] where:[NSPredicate predicateWithFormat:@"stockItem == %@", item]
              sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"lbLocationTitle" ascending:YES] ]];
}

- (NSArray<Move *> *)movesOf:(StockItem *)item {
    return [self fetch:[Move class] where:[NSPredicate predicateWithFormat:@"stockItem == %@", item]
              sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"moment" ascending:NO] ]];
}

- (LBStockFigures *)figures {
    Catalog *catalog = self.catalog;
    return [LBStockFigures figuresOf:[self itemsMatching:nil] currency:catalog.currency weightIn:catalog.weightUnit sizeIn:catalog.sizeUnit];
}

- (NSArray<ReorderRule *> *)rulesDue {
    if (!self.catalog) return @[];
    return [self fetch:[ReorderRule class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@ AND isDue == YES", _catalog]
              sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"stockItem.itemName" ascending:YES] ]];
}

- (NSArray<NSManagedObject *> *)ordersOpen {
    return [LBStockFigures openOf:[self saleOrders] purchases:[self purchaseOrders]];
}

#pragma mark Changing

- (StockItem *)newItem {
    StockItem *item = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([StockItem class]) inManagedObjectContext:_store.context];
    item.id = [NSUUID UUID];
    item.created = LBNow();
    item.itemName = @"New Item";
    item.catalog = self.catalog;
    item.sku = [self.catalog lb_nextSKU];
    return item;
}

/* An amount typed with no currency: the catalog's, else the user's. */
- (void)completeMoney {
    NSMutableSet *changed = [NSMutableSet setWithSet:_store.context.insertedObjects];
    [changed unionSet:_store.context.updatedObjects];
    for (StockItem *item in changed) {
        if (![item isKindOfClass:[StockItem class]]) continue;
        NSString *currency = item.catalog.currency ?: _store.user.currency;
        if (item.priceAmount && !item.priceCurrency) item.priceCurrency = currency;
        if (item.unitCostAmount && !item.unitCostCurrency) item.unitCostCurrency = currency;
    }
}

- (BOOL)saveProblems:(NSArray<NSString *> **)problems {
    [self completeMoney];
    NSError *error = nil;
    if ([_store save:&error]) return YES;
    if (problems) *problems = [LBLocalStore sentencesOfError:error];
    return NO;
}

/* What a procedure made saved; nothing kept of it when it, or the save,
   refused. */
- (BOOL)did:(id)made error:(NSError *)error problems:(NSArray<NSString *> **)problems {
    if (made && [self saveProblems:problems]) return YES;
    if (!made && problems) *problems = error ? [LBLocalStore sentencesOfError:error] : @[ @"Refused." ];
    [_store.context rollback];
    return NO;
}

- (BOOL)adjust:(StockItem *)item by:(NSDecimalNumber *)quantity at:(Location *)location reason:(NSString *)reason
      problems:(NSArray<NSString *> **)problems {
    NSError *error = nil;
    Move *move = [item lb_adjust:quantity at:location reason:reason note:nil by:_store.user at:LBNow() error:&error];
    return [self did:move error:error problems:problems];
}

- (BOOL)transfer:(StockItem *)item quantity:(NSDecimalNumber *)quantity from:(Location *)from to:(Location *)to
        problems:(NSArray<NSString *> **)problems {
    NSError *error = nil;
    Move *move = [item lb_transfer:quantity from:from to:to by:_store.user at:LBNow() error:&error];
    return [self did:move error:error problems:problems];
}

- (BOOL)ship:(SaleOrder *)order lines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)lines from:(Location *)location
    problems:(NSArray<NSString *> **)problems {
    NSError *error = nil;
    Shipment *shipment = [order lb_shipLines:lines from:location on:LBNow() by:_store.user at:LBNow() error:&error];
    return [self did:shipment error:error problems:problems];
}

- (BOOL)receive:(PurchaseOrder *)order lines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)lines at:(Location *)location
       problems:(NSArray<NSString *> **)problems {
    NSError *error = nil;
    Receipt *receipt = [order lb_receiveLines:lines at:location on:LBNow() by:_store.user at:LBNow() error:&error];
    return [self did:receipt error:error problems:problems];
}

- (StockCount *)count:(LBCountPlace *)place found:(NSArray<LBCounted *> *)found problems:(NSArray<NSString *> **)problems {
    NSError *error = nil;
    StockCount *count = [place.warehouse lb_countLocation:place.location found:found on:LBNow() by:_store.user at:LBNow() error:&error];
    return [self did:count error:error problems:problems] ? count : nil;
}

@end
