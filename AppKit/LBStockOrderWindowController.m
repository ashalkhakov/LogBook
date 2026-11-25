#import "LBStockOrderWindowController.h"
#import "LBTasks.h"
#import "LBLocalStore.h"
#import "LBConflicts.h"
#import "LBStore.h"
#import "LBStockDisplay.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>
#import <ORMRuntime/ORMFlowSession.h>
#import "LBFormValues.h"

@interface LBStockOrderWindowController ()
@property (nonatomic, readwrite, copy) NSArray *lines;
@property (nonatomic, readwrite, copy) NSArray *documents;
@property (nonatomic, readwrite, copy) NSArray *returns;
@property (nonatomic, readwrite, copy) NSArray *parties;
@property (nonatomic, readwrite, copy) NSArray<StockItem *> *catalogItems;
@property (nonatomic, readwrite, copy) NSArray<Location *> *locations;
@property (nonatomic, readwrite, strong) LBFormValues *orderForm;
@property (nonatomic, readwrite, strong) LBFormValues *confirmForm;
@property (nonatomic, readwrite, strong) LBFormValues *receiveForm;
@property (nonatomic, readwrite, strong) LBFormValues *shipForm;
@property (nonatomic, readwrite, strong) LBFormValues *returnAskForm;
@property (nonatomic, readwrite, strong) LBFormValues *returnDoForm;
@end

@implementation LBStockOrderWindowController {
    /* An order's way through its forms (Model/Purchasing.flow, Selling.flow):
       the order, its Confirm the order and Receive (Ship) the goods over it. */
    ORMFlowSession *_flow;
    NSError *_flowError;
    /* The state the Confirm sheet opens with: Confirm's, Cancel's. */
    NSString *_confirmState;
    /* The lines a Receive or a Ship is of, so many of each: those chosen. */
    NSArray *_moving;
    NSArray<NSDecimalNumber *> *_movingQuantities;
    /* The line a return is asked for, how many. */
    NSManagedObject *_returnAskedLine;
    NSDecimalNumber *_returnAskedQuantity;
}

- (instancetype)initWithStore:(LBStore *)store order:(NSManagedObject *)order {
    BOOL sale = [order isKindOfClass:[SaleOrder class]];
    if ((self = [super initWithStore:store nibName:sale ? @"StockSale" : @"StockPurchase"])) {
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
        NSError *error = nil;
        _flow = [ORMFlowSession flowNamed:self.flowName error:&error];
        if (![_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:&error]) _flowError = error;
    }
    return self;
}

- (instancetype)initWithStore:(LBStore *)store returning:(NSManagedObject *)back {
    NSManagedObject *order = [back valueForKey:[back isKindOfClass:[CustomerReturn class]] ? @"saleOrder" : @"purchaseOrder"];
    if ((self = [self initWithStore:store order:order])) {
        _returning = [self own:back];
    }
    return self;
}

- (ORMFlowSession *)flow {
    return _flow;
}

/* Its flow's, and its order's form's (the window's own). */
- (NSString *)flowName {
    return _sale ? @"Selling" : @"Purchasing";
}

- (NSString *)businessKey {
    /* Its return's task's, while it is done here; else its order's. */
    return [[(_returning ?: _order) valueForKey:@"id"] UUIDString];
}

- (NSString *)orderFormName {
    return _sale ? @"EditSaleOrder" : @"EditPurchaseOrder";
}

/* Opened for a task done with a flow's entry: the window, and its step's
   screen over it at once (Confirm the order's sheet). */
- (void)screenDidShow {
    [super screenDidShow];
    if (!self.task.entryName || ![self.task.flowName isEqualToString:self.flowName] || self.window.attachedSheet) return;
    NSError *error = nil;
    ORMFlowStep *step = [_flow beginAt:self.task.entryName key:[[(_returning ?: _order) valueForKey:@"id"] UUIDString] error:&error];
    if (!step) return [self reportError:error ?: _flowError];
    _confirmState = nil;
    [self show:step];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    /* Its lines, its form's rows: in the order the window lists them. */
    _lineList.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"lbLineOrder" ascending:YES
                                                                  selector:@selector(localizedCaseInsensitiveCompare:)] ];
    [self bind:@"title" toObject:self withKeyPath:@"windowTitle" options:nil];
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
    /* The window, its form opened on the order as it is (its catalog
       given). */
    if (!self.window.attachedSheet) {
        self.orderForm = [self valuesOfForm:self.orderFormName given:@{ @"catalog" : self.catalog.id.UUIDString ?: @"" } object:_order];
    }
    [self willChangeValueForKey:@"order"];
    [self didChangeValueForKey:@"order"];
}

#pragma mark Its state

- (void)act:(NSString *)name {
    /* An order confirmed or cancelled: its Confirm the order's step, in its
       form's sheet. */
    if ([@[ @"Confirm", @"Cancel" ] containsObject:name]) {
        _confirmState = [name isEqualToString:@"Confirm"] ? @"Confirmed" : @"Cancelled";
        [self trigger:[name isEqualToString:@"Confirm"] ? @"confirmOrder" : @"cancelOrder"];
        return;
    }
    [self performAction:name on:_order parameters:nil];
}

#pragma mark Its forms

/* An order's changes saved by its form (EditPurchaseOrder, EditSaleOrder),
   opened on it as it is now; what else changed, with it. */
- (BOOL)saveChanges {
    if (!_orderForm || !self.context.hasChanges) return [super saveChanges];
    if (![self commitEdits]) return NO;
    [self completeMoney];
    LBFormValues *now = [self valuesOfForm:self.orderFormName given:_orderForm.session.given object:_order];
    NSError *error = nil;
    if (!now || ![now.session save:&error]) {
        if (now) [self refuseForm:now error:error under:self.view];
        return NO;
    }
    return [super saveChanges];
}

/* The sheet shown gone, and its form, the flow's way on its outcome
   taken (SubmitDone, Cancel: closed back to the order); read again. A flow
   begun at a task's step, done with it: begun again at the order. */
- (void)endForm:(NSString *)on {
    NSWindow *sheet = self.window.attachedSheet;
    if (sheet) [self.window endSheet:sheet];
    [sheet orderOut:nil];
    LBFormValues *shown = _confirmForm ?: _receiveForm ?: _shipForm ?: _returnAskForm ?: _returnDoForm;
    ORMFlowWay *way = [_flow wayOn:on control:nil];
    if (way) [_flow take:way row:nil result:shown.session.savedKey values:shown.session.values];
    if (_flow.ended || ![_flow.step.formName isEqualToString:self.orderFormName]) {
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
    }
    self.confirmForm = nil;
    self.receiveForm = nil;
    self.shipForm = nil;
    self.returnAskForm = nil;
    self.returnDoForm = nil;
    [self readAgain];
}

- (IBAction)dismissForm:(id)sender {
    [self.context rollback];
    [self endForm:@"Cancel"];
}

/* The flow's way on the control (a trigger: Confirm, Cancel, Receive)
   taken from the order, the order saved first; its screen shown. Refused,
   and said, where the flow has no such way from here. */
- (void)trigger:(NSString *)control {
    ORMFlowWay *way = [_flow wayOn:@"Trigger" control:control];
    if (!way) {
        return [self refuse:_flowError.localizedDescription
                                ?: [NSString stringWithFormat:@"%@ leads nowhere from %@ (Model/Purchasing.flow).", control, _flow.step.name ?: @"here"]];
    }
    if (![self saveChanges]) return;
    NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:_orderForm.session.values ?: @{}];
    values[@"id"] = [[_order valueForKey:@"id"] UUIDString];
    [self show:[_flow take:way row:nil result:nil values:values]];
}

/* A step of the flow shown: its form's sheet over the order. */
- (void)show:(ORMFlowStep *)step {
    if ([@[ @"ConfirmPurchaseOrder", @"ConfirmSaleOrder" ] containsObject:step.formName ?: @""]) return [self openConfirm:step];
    if ([step.formName isEqualToString:@"ReceiveGoods"]) return [self openReceive:step];
    if ([step.formName isEqualToString:@"ShipGoods"]) return [self openShip:step];
    if ([@[ @"RequestCustomerReturn", @"RequestSupplierReturn" ] containsObject:step.formName ?: @""]) return [self openReturnAsk:step];
    if ([@[ @"ReceiveCustomerReturn", @"SendSupplierReturn" ] containsObject:step.formName ?: @""]) return [self openReturnDo:step];
    if (step.formName && ![step.formName isEqualToString:self.orderFormName]) {
        [self refuse:[NSString stringWithFormat:@"%@ has no view in the order's window.", step.formName]];
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
    }
}

- (void)cancelOperation:(id)sender {
    if (self.window.attachedSheet) [self dismissForm:sender];
}

/* Confirm the order's sheet (ConfirmPurchaseOrder): the order as it is,
   its state chosen (Confirm's, Cancel's; from a task, the user's). */
- (void)openConfirm:(ORMFlowStep *)step {
    self.confirmForm = [self valuesOfForm:step.formName given:step.given object:_order];
    if (!_confirmForm) {
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
        return;
    }
    if (_confirmState) [_confirmForm setValue:_confirmState forKey:@"orderState"];
    [self.window beginSheet:_confirmPanel completionHandler:nil];
}

- (IBAction)submitConfirm:(id)sender {
    if ([self submitForm:_confirmForm sheet:_confirmPanel]) [self endForm:@"SubmitDone"];
}

/* Its title: the order's number, and the task it was opened for. */
- (NSString *)windowTitle {
    NSString *number = [_order valueForKey:@"lb_number"] ?: @"";
    return self.task ? [NSString stringWithFormat:@"%@ — %@", number, self.task.name] : number;
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingWindowTitle {
    return [NSSet setWithObjects:@"order.lb_number", @"task", nil];
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


/* So many of each line shipped (a sale's Ship the goods, from moveAt) or
   received: the flow's way on the control taken, its sheet of them. */
- (void)move:(NSArray *)lines quantities:(NSArray<NSDecimalNumber *> *)quantities control:(NSString *)control {
    if (!_moveAt) return [self refuse:_sale ? @"Choose where from." : @"Choose where."];
    if (!_sale) return [self receive:lines quantities:quantities];
    _moving = lines;
    _movingQuantities = quantities;
    [self trigger:control];
}

/* Ship the goods' sheet (ShipGoods): a shipment of the order, its next,
   recorded by the user now, shipped today from moveAt, a move of each line
   chosen so many; changed there, and submitted. Each move's item, place,
   moment and maker are worked out as it saves (lb_completeShippedMoves). */
- (void)openShip:(ORMFlowStep *)step {
    NSArray *lines = _moving, *quantities = _movingQuantities;
    _moving = nil;
    _movingQuantities = nil;
    if (!lines.count) {
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
        return [self refuse:@"Nothing of it is to be shipped."];
    }
    int32_t number = 0;
    for (NSManagedObject *each in [_order valueForKey:@"shipments"]) number = MAX(number, [[each valueForKey:@"runningNumber"] intValue]);
    NSDate *now = [NSDate date];
    Shipment *shipment = [NSEntityDescription insertNewObjectForEntityForName:@"Shipment" inManagedObjectContext:self.context];
    shipment.id = [NSUUID UUID];
    shipment.saleOrder = (SaleOrder *)_order;
    shipment.runningNumber = number + 1;
    shipment.shippedBy = self.user;
    shipment.shipmentRecorded = now;
    shipment.shippedFrom = _moveAt;
    for (NSUInteger i = 0; i < lines.count; i++) {
        Move *move = [NSEntityDescription insertNewObjectForEntityForName:@"Move" inManagedObjectContext:self.context];
        move.id = [NSUUID UUID];
        move.shipment = shipment;
        move.saleLine = lines[i];
        move.moved = quantities[i];
    }
    NSISO8601DateFormatter *moments = [[NSISO8601DateFormatter alloc] init];
    NSMutableDictionary *given = [@{ @"saleOrder" : [[_order valueForKey:@"id"] UUIDString],
                                     @"runningNumber" : [NSString stringWithFormat:@"%d", number + 1],
                                     @"shippedBy" : self.user.email ?: @"",
                                     @"shipmentRecorded" : [moments stringFromDate:now] } mutableCopy];
    [given addEntriesFromDictionary:step.given];
    self.shipForm = [self valuesOfForm:step.formName given:given object:shipment];
    if (!_shipForm) {
        [self.context rollback];
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
        return;
    }
    [_shipForm setValue:now forKey:@"shipped"];
    [self.window beginSheet:_shipPanel completionHandler:nil];
}

- (IBAction)submitShip:(id)sender {
    if ([self submitForm:_shipForm sheet:_shipPanel]) [self endForm:@"SubmitDone"];
}

/* Receive the goods' sheet (ReceiveGoods): a receipt of the order, its
   next, recorded by the user now, received today at moveAt (else its
   catalog's first place), a move of each line so many; changed there, and
   submitted. Each move's item, place, moment and maker are the model's. */
- (void)receive:(NSArray *)lines quantities:(NSArray<NSDecimalNumber *> *)quantities {
    if (!lines.count) return [self refuse:@"Nothing of it is outstanding."];
    _moving = lines;
    _movingQuantities = quantities;
    [self trigger:@"receiveGoods"];
}

/* The flow's Receive the goods: the lines chosen (else each outstanding),
   so many of each, a receipt of them. */
- (void)openReceive:(ORMFlowStep *)step {
    NSArray *lines = _moving, *quantities = _movingQuantities;
    _moving = nil;
    _movingQuantities = nil;
    if (!lines) {
        NSMutableArray *chosen = [NSMutableArray array], *left = [NSMutableArray array];
        for (PurchaseLine *line in _lines) {
            NSDecimalNumber *outstanding = line.outstandingQuantity;
            if (!outstanding || [outstanding compare:[NSDecimalNumber zero]] != NSOrderedDescending) continue;
            [chosen addObject:line];
            [left addObject:outstanding];
        }
        lines = chosen;
        quantities = left;
    }
    if (!lines.count) {
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
        return [self refuse:@"Nothing of it is outstanding."];
    }
    int32_t number = 0;
    for (NSManagedObject *each in [_order valueForKey:@"receipts"]) number = MAX(number, [[each valueForKey:@"runningNumber"] intValue]);
    NSDate *now = [NSDate date];
    Receipt *receipt = [NSEntityDescription insertNewObjectForEntityForName:@"Receipt" inManagedObjectContext:self.context];
    receipt.id = [NSUUID UUID];
    receipt.purchaseOrder = (PurchaseOrder *)_order;
    receipt.runningNumber = number + 1;
    receipt.recordedBy = self.user;
    receipt.recorded = now;
    receipt.receivedAt = _moveAt ?: _locations.firstObject;
    for (NSUInteger i = 0; i < lines.count; i++) {
        Move *move = [NSEntityDescription insertNewObjectForEntityForName:@"Move" inManagedObjectContext:self.context];
        move.id = [NSUUID UUID];
        move.receipt = receipt;
        move.purchaseLine = lines[i];
        move.moved = quantities[i];
    }
    NSISO8601DateFormatter *moments = [[NSISO8601DateFormatter alloc] init];
    /* What the flow gives (the order), and the rest the app's: its next
       number, who records it, now. */
    NSMutableDictionary *given = [@{ @"purchaseOrder" : [[_order valueForKey:@"id"] UUIDString],
                                     @"runningNumber" : [NSString stringWithFormat:@"%d", number + 1],
                                     @"recordedBy" : self.user.email ?: @"",
                                     @"recorded" : [moments stringFromDate:now] } mutableCopy];
    [given addEntriesFromDictionary:step.given];
    self.receiveForm = [self valuesOfForm:step.formName given:given object:receipt];
    if (!_receiveForm) {
        [self.context rollback];
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
        return;
    }
    [_receiveForm setValue:now forKey:@"received"];
    [self.window beginSheet:_receivePanel completionHandler:nil];
}

- (IBAction)receiveGoods:(id)sender {
    [self trigger:@"receiveGoods"];
}

- (IBAction)submitReceive:(id)sender {
    if ([self submitForm:_receiveForm sheet:_receivePanel]) [self endForm:@"SubmitDone"];
}

- (IBAction)moveLine:(id)sender {
    /* What is still being typed (the quantity), taken first. */
    if (![self commitEdits]) return;
    NSManagedObject *line = _lineList.selectedObjects.count == 1 ? _lineList.selectedObjects[0] : nil;
    if (!line) return [self refuse:@"Choose a line."];
    NSDecimalNumber *quantity = [self typed:_moveQuantity];
    if (quantity) [self move:@[ line ] quantities:@[ quantity ] control:@"moveLine"];
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
    if (![self commitEdits]) return;
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
    [self move:chosen quantities:quantities control:@"moveOutstanding"];
}

- (IBAction)returnLine:(id)sender {
    if (![self commitEdits]) return;
    NSManagedObject *line = _lineList.selectedObjects.count == 1 ? _lineList.selectedObjects[0] : nil;
    if (!line) return [self refuse:@"Choose a line."];
    NSDecimalNumber *quantity = [self typed:_moveQuantity];
    if (!quantity) return;
    _returnAskedLine = line;
    _returnAskedQuantity = quantity;
    [self trigger:@"returnLine"];
}

/* Return Line's sheet (RequestCustomerReturn, RequestSupplierReturn): a
   return of the order asked for, its next, by the user, of the line
   chosen so many, for the reason chosen; changed there, and saved. */
- (void)openReturnAsk:(ORMFlowStep *)step {
    NSManagedObject *line = _returnAskedLine;
    NSDecimalNumber *quantity = _returnAskedQuantity;
    _returnAskedLine = nil;
    _returnAskedQuantity = nil;
    NSString *kind = _sale ? @"CustomerReturn" : @"SupplierReturn";
    int32_t number = 0;
    for (NSManagedObject *each in [_order valueForKey:_sale ? @"customerReturns" : @"supplierReturns"]) {
        number = MAX(number, [[each valueForKey:@"runningNumber"] intValue]);
    }
    NSManagedObject *back = [NSEntityDescription insertNewObjectForEntityForName:kind inManagedObjectContext:self.context];
    [back setValue:[NSUUID UUID] forKey:@"id"];
    [back setValue:_order forKey:_sale ? @"saleOrder" : @"purchaseOrder"];
    [back setValue:@(number + 1) forKey:@"runningNumber"];
    [back setValue:self.user forKey:@"returnAskedBy"];
    [back setValue:@"Requested" forKey:@"returnState"];
    [back setValue:_returnReason ?: @"Other" forKey:@"returnReason"];
    NSManagedObject *asked = [NSEntityDescription insertNewObjectForEntityForName:[kind stringByAppendingString:@"Line"]
                                                           inManagedObjectContext:self.context];
    [asked setValue:[NSUUID UUID] forKey:@"id"];
    [asked setValue:back forKey:_sale ? @"customerReturn" : @"supplierReturn"];
    [asked setValue:line forKey:_sale ? @"saleLine" : @"purchaseLine"];
    [asked setValue:quantity forKey:@"askedQuantity"];
    NSMutableDictionary *given = [@{ _sale ? @"saleOrder" : @"purchaseOrder" : [[_order valueForKey:@"id"] UUIDString],
                                     @"runningNumber" : [NSString stringWithFormat:@"%d", number + 1],
                                     @"returnAskedBy" : self.user.email ?: @"", @"returnState" : @"Requested" } mutableCopy];
    [given addEntriesFromDictionary:step.given];
    self.returnAskForm = [self valuesOfForm:step.formName given:given object:back];
    if (!_returnAskForm) {
        [self.context rollback];
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
        return;
    }
    [self.window beginSheet:_returnAskPanel completionHandler:nil];
}

/* Asked for: saved by its form, requested; nothing moved yet. */
- (IBAction)submitReturnAsk:(id)sender {
    [_returnAskPanel makeFirstResponder:nil];
    LBFormValues *now = [self valuesOfForm:_returnAskForm.session.form.name given:_returnAskForm.session.given object:_returnAskForm.object];
    NSError *error = nil;
    if (!now || ![now.session save:&error]) {
        if (now) [self refuseForm:now error:error under:_returnAskPanel.contentView];
        return;
    }
    [self endForm:@"SubmitDone"];
}

/* The return's task's sheet (ReceiveCustomerReturn, SendSupplierReturn):
   the return as asked for, received back (sent back) today at moveAt,
   recorded by the user now, its state chosen. */
- (void)openReturnDo:(ORMFlowStep *)step {
    if (!_returning) return;
    NSISO8601DateFormatter *moments = [[NSISO8601DateFormatter alloc] init];
    NSMutableDictionary *given = [@{ @"returnRecordedBy" : self.user.email ?: @"",
                                     @"returnRecorded" : [moments stringFromDate:[NSDate date]] } mutableCopy];
    [given addEntriesFromDictionary:step.given];
    self.returnDoForm = [self valuesOfForm:step.formName given:given object:_returning];
    if (!_returnDoForm) return;
    [_returnDoForm setValue:[NSDate date] forKey:_sale ? @"returnReceived" : @"returnShipped"];
    if (_moveAt) [_returnDoForm setValue:_moveAt forKey:_sale ? @"returnedTo" : @"returnedFrom"];
    [self.window beginSheet:_returnDoPanel completionHandler:nil];
}

- (IBAction)submitReturnDone:(id)sender {
    if (![self submitForm:_returnDoForm sheet:_returnDoPanel]) return;
    [self endForm:@"SubmitDone"];
    _returning = nil;
}
@end
