#import "LBStockOrderWindowController.h"
#import "LBStore.h"
#import "LBStockDisplay.h"

@interface LBStockOrderWindowController ()
@property (nonatomic, readwrite, copy) NSArray *lines;
@property (nonatomic, readwrite, copy) NSArray *documents;
@property (nonatomic, readwrite, copy) NSArray *returns;
@property (nonatomic, readwrite, copy) NSArray *parties;
@property (nonatomic, readwrite, copy) NSArray<StockItem *> *catalogItems;
@property (nonatomic, readwrite, copy) NSArray<Location *> *locations;
@end

@implementation LBStockOrderWindowController

- (instancetype)initWithStore:(LBStore *)store order:(NSManagedObject *)order {
    BOOL sale = [order isKindOfClass:[SaleOrder class]];
    if ((self = [super initWithStore:store windowNibName:sale ? @"StockSale" : @"StockPurchase"])) {
        _sale = sale;
        _order = [self own:order];
        self.catalog = [_order valueForKey:@"catalog"];
        _lines = @[];
        _documents = @[];
        _returns = @[];
        _returnReasons = @[ @"Damaged", @"Wrong item", @"Not wanted", @"Not used", @"Other" ];
        _returnReason = sale ? @"Not wanted" : @"Damaged";
        _parties = @[];
        _catalogItems = @[];
        _locations = @[];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self.window bind:NSTitleBinding toObject:self withKeyPath:@"order.lb_number" options:nil];
}

- (NSArray<NSArrayController *> *)editedControllers {
    return @[ _lineList ];
}

#pragma mark Reading

- (void)readAgain {
    NSPredicate *ofOrder = [NSPredicate predicateWithFormat:@"%K == %@", _sale ? @"saleOrder" : @"purchaseOrder", _order];
    NSPredicate *ofCatalog = [NSPredicate predicateWithFormat:@"catalog == %@", self.catalog];
    [self fetch:[_order class] where:[NSPredicate predicateWithFormat:@"id == %@", [_order valueForKey:@"id"]] sortedBy:nil];
    NSSortDescriptor *inOrder = [NSSortDescriptor sortDescriptorWithKey:@"lbLineOrder" ascending:YES
                                                               selector:@selector(localizedCaseInsensitiveCompare:)];
    self.lines = [self fetch:_sale ? [SaleLine class] : [PurchaseLine class] where:ofOrder sortedBy:@[ inOrder ]];
    self.documents = [self fetch:_sale ? [Shipment class] : [Receipt class] where:ofOrder
                        sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"runningNumber" ascending:NO] ]];
    self.returns = [self fetch:_sale ? [CustomerReturn class] : [SupplierReturn class] where:ofOrder
                      sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"runningNumber" ascending:NO] ]];
    self.parties = [self fetch:_sale ? [Customer class] : [Supplier class] where:ofCatalog sortedBy:self.byTitle];
    self.catalogItems = [self fetch:[StockItem class] where:ofCatalog sortedBy:self.byTitle];
    self.locations = [self fetch:[Location class] where:[NSPredicate predicateWithFormat:@"warehouse.catalog == %@", self.catalog]
                        sortedBy:self.byTitle];
    if (![_locations containsObject:_moveAt]) self.moveAt = _locations.firstObject;
    /* Its fields, bound through the order, read it again. */
    [self willChangeValueForKey:@"order"];
    [self didChangeValueForKey:@"order"];
}

#pragma mark Its state

- (void)act:(NSString *)name {
    [self performAction:name on:_order parameters:nil];
}

- (IBAction)confirmOrder:(id)sender {
    [self act:@"Confirm"];
}

- (IBAction)closeOrder:(id)sender {
    [self act:@"Close"];
}

- (IBAction)cancelOrder:(id)sender {
    [self act:@"Cancel"];
}

- (IBAction)reopenOrder:(id)sender {
    [self act:@"Reopen"];
}

#pragma mark Its lines

- (IBAction)addLine:(id)sender {
    if (![self commitEdits]) return;
    StockItem *item = _catalogItems.firstObject;
    NSManagedObject *line = [NSEntityDescription insertNewObjectForEntityForName:_sale ? @"SaleLine" : @"PurchaseLine"
                                                          inManagedObjectContext:self.context];
    [line setValue:[NSUUID UUID] forKey:@"id"];
    [line setValue:[NSDecimalNumber one] forKey:@"quantity"];
    [line setValue:item forKey:@"stockItem"];
    [line setValue:_order forKey:_sale ? @"saleOrder" : @"purchaseOrder"];
    if (_sale) {
        ((SaleLine *)line).linePriceAmount = item.priceAmount;
        ((SaleLine *)line).linePriceCurrency = item.priceCurrency;
    } else {
        ((PurchaseLine *)line).lineUnitCostAmount = item.unitCostAmount;
        ((PurchaseLine *)line).lineUnitCostCurrency = item.unitCostCurrency;
    }
    self.lines = [_lines arrayByAddingObject:line];
    [_lineList setSelectedObjects:@[ line ]];
}

- (IBAction)removeLine:(id)sender {
    NSArray *chosen = _lineList.selectedObjects;
    for (NSManagedObject *line in chosen) {
        if (_sale) {
            NSError *error = nil;
            if (![(SaleLine *)line lb_delete:&error]) return [self reportError:error];
        } else {
            if (((PurchaseLine *)line).moves.count) return [self refuse:@"Some of it has been received: it stays."];
            [self.context deleteObject:line];
        }
    }
    NSMutableArray *left = [_lines mutableCopy];
    [left removeObjectsInArray:chosen];
    self.lines = left;
}

/* Lines as Ship and Receive take them: {"<line id>": quantity}. */
static NSDictionary *LBLinesParameter(NSArray *lines, NSArray<NSDecimalNumber *> *quantities) {
    NSMutableDictionary *parameter = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < lines.count; i++) parameter[[[lines[i] valueForKey:@"id"] UUIDString]] = quantities[i];
    return parameter;
}

- (void)move:(NSArray *)lines quantities:(NSArray<NSDecimalNumber *> *)quantities {
    if (!_moveAt) return [self refuse:_sale ? @"Choose where from." : @"Choose where."];
    [self performAction:_sale ? @"Ship" : @"Receive" on:_order
             parameters:@{ @"Lines": LBLinesParameter(lines, quantities), (_sale ? @"From" : @"At"): _moveAt }];
}

- (IBAction)moveLine:(id)sender {
    NSManagedObject *line = _lineList.selectedObjects.count == 1 ? _lineList.selectedObjects[0] : nil;
    if (!line) return [self refuse:@"Choose a line."];
    NSDecimalNumber *quantity = [self typed:_moveQuantity];
    if (quantity) [self move:@[ line ] quantities:@[ quantity ]];
}

/* What is held of the items at moveAt, by item, from the server's rows. */
- (NSDictionary<NSManagedObjectID *, NSDecimalNumber *> *)heldAtMoveAt {
    NSMutableDictionary *held = [NSMutableDictionary dictionary];
    for (Holding *holding in [self fetch:[Holding class] where:[NSPredicate predicateWithFormat:@"location == %@", _moveAt] sortedBy:nil]) {
        if (holding.stockItem && holding.quantity) held[holding.stockItem.objectID] = holding.quantity;
    }
    return held;
}

- (IBAction)moveOutstanding:(id)sender {
    if (!_moveAt) return [self refuse:_sale ? @"Choose where from." : @"Choose where."];
    NSDictionary *held = _sale ? [self heldAtMoveAt] : nil;
    NSMutableArray *chosen = [NSMutableArray array], *quantities = [NSMutableArray array];
    for (NSManagedObject *line in _lines) {
        NSDecimalNumber *left = [line valueForKey:_sale ? @"backorderedQuantity" : @"outstandingQuantity"];
        if (!left || [left compare:[NSDecimalNumber zero]] != NSOrderedDescending) continue;
        if (_sale) {
            SaleLine *sold = (SaleLine *)line;
            if (sold.stockItem.isAPhantomKit) continue;
            NSDecimalNumber *there = held[sold.stockItem.objectID] ?: [NSDecimalNumber zero];
            if ([there compare:left] == NSOrderedAscending) left = there;
            if ([left compare:[NSDecimalNumber zero]] != NSOrderedDescending) continue;
        }
        [chosen addObject:line];
        [quantities addObject:left];
    }
    if (!chosen.count) return [self refuse:_sale ? @"Nothing outstanding is held there." : @"Nothing is outstanding."];
    [self move:chosen quantities:quantities];
}

- (IBAction)returnLine:(id)sender {
    NSManagedObject *line = _lineList.selectedObjects.count == 1 ? _lineList.selectedObjects[0] : nil;
    if (!line) return [self refuse:@"Choose a line."];
    if (!_moveAt) return [self refuse:_sale ? @"Choose where to." : @"Choose where from."];
    NSDecimalNumber *quantity = [self typed:_moveQuantity];
    if (!quantity) return;
    [self performAction:@"Return" on:_order
             parameters:@{ @"Lines": LBLinesParameter(@[ line ], @[ quantity ]), (_sale ? @"At" : @"From"): _moveAt,
                           @"Reason": _returnReason ?: @"Other" }];
}

@end
