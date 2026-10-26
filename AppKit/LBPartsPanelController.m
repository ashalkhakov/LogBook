#import "LBPartsPanelController.h"
#import "LBStockProcedures.h"
#import "LBStockDisplay.h"
#import "LBDisplay.h"

/* Defaults: where parts were last taken from (a location's id). */
static NSString * const LBPartsLocationDefaultsKey = @"LBPartsLocation";

@interface LBPartsPanelController ()
@property (nonatomic, readwrite, copy) NSArray<SaleLine *> *parts;
@end

@implementation LBPartsPanelController

- (instancetype)initWithEvent:(Event *)event {
    if ((self = [super initWithWindowNibName:@"Parts"])) {
        _event = event;
        _parts = @[];
        _quantityText = @"1";
        NSManagedObjectContext *context = event.managedObjectContext;
        _locations = [self all:[Location class] in:context sortedBy:@"lbTitle"];
        _items = [self all:[StockItem class] in:context sortedBy:@"lbTitle"];
        _chosenItem = _items.firstObject;
        [self listParts];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.title = [NSString stringWithFormat:@"Parts of %@", _event.lbTitle ?: @"the record"];
}

- (NSArray *)all:(Class)cls in:(NSManagedObjectContext *)context sortedBy:(NSString *)key {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    NSArray *found = [context executeFetchRequest:fetch error:NULL] ?: @[];
    return [found sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:key ascending:YES
                                                                                selector:@selector(localizedCaseInsensitiveCompare:)] ]];
}

- (void)listParts {
    NSMutableArray *lines = [NSMutableArray array];
    for (SaleLine *line in _event.lb_partsSale.saleLines) {
        if (!line.isDeleted) [lines addObject:line];
    }
    self.parts = [lines sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"lbLineOrder" ascending:YES
                                                                                       selector:@selector(localizedCaseInsensitiveCompare:)] ]];
}

- (Location *)partsLocation {
    Location *from = _event.lb_partsSale.shipsFrom;
    if (from) return from;
    NSString *kept = [[NSUserDefaults standardUserDefaults] stringForKey:LBPartsLocationDefaultsKey];
    for (Location *location in _locations) {
        if ([location.id.UUIDString isEqualToString:kept]) return location;
    }
    return _locations.firstObject;
}

- (void)setPartsLocation:(Location *)location {
    [self willChangeValueForKey:@"partsLocation"];
    [[NSUserDefaults standardUserDefaults] setObject:location.id.UUIDString forKey:LBPartsLocationDefaultsKey];
    SaleOrder *sale = _event.lb_partsSale;
    if (sale && location.warehouse.catalog == sale.catalog) sale.shipsFrom = location;
    [self didChangeValueForKey:@"partsLocation"];
}

- (void)refuse:(NSString *)why {
    _lastError = [NSError errorWithDomain:LBProceduresErrorDomain code:LBProceduresErrorRefused userInfo:@{ NSLocalizedDescriptionKey: why }];
    if (!_quiet) [self presentError:_lastError];
}

- (IBAction)usePart:(id)sender {
    if (self.isWindowLoaded && ![self.window makeFirstResponder:nil]) return;
    StockItem *item = _chosenItem;
    NSDecimalNumber *quantity = _quantityText.length ? [NSDecimalNumber decimalNumberWithString:_quantityText locale:[NSLocale currentLocale]] : nil;
    if (!item) return [self refuse:@"Choose what was used."];
    if (!quantity || quantity == [NSDecimalNumber notANumber]) return [self refuse:@"Say how many: a number."];
    Location *from = self.partsLocation;
    if (from.warehouse.catalog != item.catalog) {
        from = nil;
        for (Location *location in _locations) {
            if (!from && location.warehouse.catalog == item.catalog) from = location;
        }
    }
    if (!from) return [self refuse:@"Its catalog has no location to take it from."];
    NSError *error = nil;
    if (![_event lb_usePart:item quantity:quantity from:from error:&error]) return [self refuse:error.localizedDescription];
    _lastError = nil;
    [self willChangeValueForKey:@"partsLocation"];
    [self didChangeValueForKey:@"partsLocation"];
    [self listParts];
}

- (IBAction)removePart:(id)sender {
    for (SaleLine *line in _partList.selectedObjects) {
        NSError *error = nil;
        if (![line lb_delete:&error]) return [self refuse:error.localizedDescription];
    }
    _lastError = nil;
    [self listParts];
}

- (IBAction)done:(id)sender {
    [self close];
}

@end
