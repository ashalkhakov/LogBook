#import "LBStockEditor.h"
#import "LBStore.h"
#import "LBStockProcedures.h"
#import <ODataIncrementalStore/ODataOperationCall.h>

NSNotificationName const LBStockDidChangeNotification = @"LBStockDidChangeNotification";
NSString *const LBStockCatalogKey = @"LBStockCatalog";

@implementation LBStockEditor

- (instancetype)initWithStore:(LBStore *)store windowNibName:(NSString *)name {
    if ((self = [super initWithWindowNibName:name])) {
        _store = store;
        _context = [store newContext];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stockDidChange:) name:LBStockDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.delegate = (id<NSWindowDelegate>)self;
    [self readAgain];
}

- (User *)user {
    return [self own:_store.user];
}

- (id)own:(NSManagedObject *)object {
    if (!object) return nil;
    if (object.managedObjectContext == _context) return object;
    return [_context existingObjectWithID:object.objectID error:NULL];
}

- (NSArray<NSSortDescriptor *> *)byTitle {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"lbTitle" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

#pragma mark Reading

- (void)readAgain {
}

- (NSArray *)fetch:(Class)cls where:(NSPredicate *)predicate sortedBy:(NSArray<NSSortDescriptor *> *)order {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    request.predicate = predicate;
    NSError *error = nil;
    NSArray *found = [_context executeFetchRequest:request error:&error];
    if (!found) {
        [self reportError:error];
        return @[];
    }
    /* The fetch brought the server's rows: those already here are read
       from them again, as they fault. */
    for (NSManagedObject *object in found) {
        if (!object.isInserted) [_context refreshObject:object mergeChanges:object.hasChanges];
    }
    return order.count ? [found sortedArrayUsingDescriptors:order] : found;
}

- (void)stockDidChange:(NSNotification *)note {
    if (!self.isWindowLoaded) return;
    NSManagedObjectID *changed = note.userInfo[LBStockCatalogKey];
    if (!changed || !_catalog || [changed isEqual:_catalog.objectID]) [self readAgain];
}

- (void)announce {
    NSDictionary *info = _catalog && !_catalog.objectID.isTemporaryID ? @{ LBStockCatalogKey: _catalog.objectID } : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:LBStockDidChangeNotification object:self userInfo:info];
}

#pragma mark Editing

- (NSArray<NSArrayController *> *)editedControllers {
    return @[];
}

- (BOOL)commitEdits {
    if (self.isWindowLoaded && ![self.window makeFirstResponder:nil]) return NO;
    for (NSArrayController *controller in [self editedControllers]) {
        if (![controller commitEditing]) return NO;
    }
    return YES;
}

/* An amount typed with no currency (an item's, a line's, a supplier's):
   the catalog's, else the user's. */
- (void)completeMoney {
    NSMutableSet *changed = [NSMutableSet setWithSet:_context.insertedObjects];
    [changed unionSet:_context.updatedObjects];
    NSString *currency = _catalog.currency ?: self.user.currency;
    for (NSManagedObject *object in changed) {
        if ([object isKindOfClass:[SaleLine class]]) {
            SaleLine *line = (SaleLine *)object;
            if (line.linePriceAmount && !line.linePriceCurrency) line.linePriceCurrency = currency;
        } else if ([object isKindOfClass:[PurchaseLine class]]) {
            PurchaseLine *line = (PurchaseLine *)object;
            if (line.lineUnitCostAmount && !line.lineUnitCostCurrency) line.lineUnitCostCurrency = currency;
        } else if ([object isKindOfClass:[SupplierItem class]]) {
            SupplierItem *bought = (SupplierItem *)object;
            if (bought.supplierCostAmount && !bought.supplierCostCurrency) bought.supplierCostCurrency = currency;
        } else if ([object isKindOfClass:[StockItem class]]) {
            StockItem *item = (StockItem *)object;
            if (item.priceAmount && !item.priceCurrency) item.priceCurrency = currency;
            if (item.unitCostAmount && !item.unitCostCurrency) item.unitCostCurrency = currency;
        }
    }
}

/* Saved, not yet said to the others. */
- (BOOL)saveHere {
    if (!_context.hasChanges) return YES;
    [self completeMoney];
    NSError *error = nil;
    if ([_store saveContext:_context error:&error]) {
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

- (BOOL)saveChanges {
    if (![self commitEdits] || ![self saveHere]) return NO;
    [self announce];
    return YES;
}

- (id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(NSDictionary *)parameters {
    if (![self commitEdits] || ![self saveHere]) return nil;
    NSError *error = nil;
    ODataOperationCall *call = [ODataOperationCall callOfOperation:name onObject:object];
    call.parameters = parameters;
    id result = [call invoke:&error];
    if (result) _lastError = nil;
    else [self reportError:error];
    [self announce];
    return result;
}

- (void)reportError:(NSError *)error {
    _lastError = error;
    if (error && !_quiet) [self presentError:error];
}

- (void)refuse:(NSString *)why {
    [self reportError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationErrorMinimum userInfo:@{ NSLocalizedDescriptionKey: why }]];
}

- (NSDecimalNumber *)typed:(NSString *)text {
    NSDecimalNumber *quantity = text.length ? [NSDecimalNumber decimalNumberWithString:text locale:[NSLocale currentLocale]] : nil;
    if (!quantity || quantity == [NSDecimalNumber notANumber]) {
        [self refuse:@"Say how many: a number."];
        return nil;
    }
    return quantity;
}

- (IBAction)save:(id)sender {
    [self saveChanges];
}

- (IBAction)revertChanges:(id)sender {
    if (self.isWindowLoaded) [self.window makeFirstResponder:nil];
    [_context rollback];
    [self readAgain];
}

- (BOOL)shouldClose {
    if (![self commitEdits]) return NO;
    if (!_context.hasChanges) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save the changes before closing?";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Don't Save"];
    NSModalResponse answer = [alert runModal];
    if (answer == NSAlertSecondButtonReturn) return NO;
    if (answer == NSAlertThirdButtonReturn) {
        [_context rollback];
        return YES;
    }
    return [self saveChanges];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    return [self shouldClose];
}

@end
