#import "LBStockOrderWindowController.h"
#import "LBTasks.h"
#import "LBStore.h"
#import "LBStockDisplay.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>
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
    /* A purchase's lines, its form's rows: in the order the window lists
       them. */
    if (!_sale) {
        _lineList.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"lbLineOrder" ascending:YES
                                                                      selector:@selector(localizedCaseInsensitiveCompare:)] ];
    }
    [self.window bind:NSTitleBinding toObject:self withKeyPath:@"windowTitle" options:nil];
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
    /* A purchase's window, its form opened on it as it is (its catalog
       given); a sale's fields, bound through the order, read it again. */
    if (!_sale && !self.window.attachedSheet) {
        self.orderForm = [self valuesOfForm:@"EditPurchaseOrder" given:@{ @"catalog" : self.catalog.id.UUIDString ?: @"" } object:_order];
    }
    [self willChangeValueForKey:@"order"];
    [self didChangeValueForKey:@"order"];
}

#pragma mark Its state

- (void)act:(NSString *)name {
    /* A purchase confirmed or cancelled: its Confirm the order's step, in
       its form's sheet. */
    if (!_sale && [@[ @"Confirm", @"Cancel" ] containsObject:name]) {
        [self openConfirm:[name isEqualToString:@"Confirm"] ? @"Confirmed" : @"Cancelled"];
        return;
    }
    [self performAction:name on:_order parameters:nil];
}

#pragma mark Its forms

/* The model's form opened on the object as the context has it now, given
   what it comes with, saved as the store saves; its values as a view binds
   them (LBFormValues.h). nil, and why said, where it does not open. */
- (LBFormValues *)valuesOfForm:(NSString *)name given:(NSDictionary *)given object:(NSManagedObject *)object {
    NSError *error = nil;
    ORMForm *form = [ORMForm formNamed:name error:&error];
    ORMFormSession *session = form ? [[ORMFormSession alloc] initWithForm:form given:given] : nil;
    LBStore *store = self.store;
    [session useContext:self.context saving:^BOOL(NSManagedObjectContext *context, NSError **failure) {
        return [store saveContext:context error:failure];
    }];
    session.key = [[object valueForKey:@"id"] UUIDString];
    if (!session || ![session open:&error]) {
        [self reportError:error];
        return nil;
    }
    return [[LBFormValues alloc] initWithSession:session object:object];
}

/* A purchase's changes saved by its form (EditPurchaseOrder), opened on it
   as it is now; what else changed, with it. */
- (BOOL)saveChanges {
    if (_sale || !_orderForm || !self.context.hasChanges) return [super saveChanges];
    if (![self commitEdits]) return NO;
    [self completeMoney];
    LBFormValues *now = [self valuesOfForm:@"EditPurchaseOrder" given:_orderForm.session.given object:_order];
    NSError *error = nil;
    if (!now || ![now.session save:&error]) {
        if (now) [self refuseForm:now error:error under:self.window.contentView];
        return NO;
    }
    return [super saveChanges];
}

/* What a save refused, said: under its controls where the view has them,
   the rest in the form's words. */
- (void)refuseForm:(LBFormValues *)values error:(NSError *)error under:(NSView *)view {
    NSArray<NSString *> *rest = error ? @[ error.localizedDescription ?: @"" ] : [values showErrors:values.session.errors under:view];
    [self refuse:rest.count ? [rest componentsJoinedByString:@"\n"] : @"Not saved: see under its fields."];
}

/* A step's form saved, opened again on its object as it is now (what its
   sheet changed of it), then its instance submitted to the order's task
   of it where one is open: the process goes on with it. */
- (BOOL)submitForm:(LBFormValues *)values sheet:(NSWindow *)sheet {
    [sheet makeFirstResponder:nil];
    LBFormValues *now = [self valuesOfForm:values.session.form.name given:values.session.given object:values.object];
    NSError *error = nil;
    if (!now || ![now.session save:&error]) {
        if (now) [self refuseForm:now error:error under:sheet.contentView];
        return NO;
    }
    [self saveChanges];
    /* The server's tasks, where it has some: opened from Window > Tasks,
       those; from the stock's window, asked here. */
    if (!_tasks && self.store.serviceRoot) _tasks = [[LBTasks alloc] initWithServiceRoot:self.store.serviceRoot signIn:self.store.signIn];
    NSString *formName = now.session.form.name;
    LBTask *task = [_task.formName isEqualToString:formName] ? _task
        : [_tasks openTaskOfForm:formName about:[[_order valueForKey:@"id"] UUIDString] error:&error];
    if (error) [self reportError:error];
    if (task && ![_tasks submitForm:now.session toTask:task error:&error]) {
        [self reportError:error];
        return NO;
    }
    [self stepDone:formName];
    return YES;
}

/* The sheet shown gone, and its form; read again. */
- (void)endForm {
    NSWindow *sheet = self.window.attachedSheet;
    if (sheet) [self.window endSheet:sheet];
    [sheet orderOut:nil];
    self.confirmForm = nil;
    self.receiveForm = nil;
    [self readAgain];
}

- (IBAction)dismissForm:(id)sender {
    [self.context rollback];
    [self endForm];
}

- (void)cancelOperation:(id)sender {
    if (self.window.attachedSheet) [self dismissForm:sender];
}

/* Confirm the order's sheet (ConfirmPurchaseOrder): the order as it is,
   its state chosen. */
- (void)openConfirm:(NSString *)state {
    if (![self saveChanges]) return;
    self.confirmForm = [self valuesOfForm:@"ConfirmPurchaseOrder" given:@{} object:_order];
    if (!_confirmForm) return;
    [_confirmForm setValue:state forKey:@"orderState"];
    [self.window beginSheet:_confirmPanel completionHandler:nil];
}

- (IBAction)submitConfirm:(id)sender {
    if ([self submitForm:_confirmForm sheet:_confirmPanel]) [self endForm];
}

/* The step of the form's done here: the title says it no more, and the
   tasks are asked again. */
- (void)stepDone:(NSString *)form {
    if (![_task.formName isEqualToString:form]) return;
    self.task = nil;
    [_tasks noteChange];
}

/* Its title: the order's number, and the task it was opened for. */
- (NSString *)windowTitle {
    NSString *number = [_order valueForKey:@"lb_number"] ?: @"";
    return _task ? [NSString stringWithFormat:@"%@ — %@", number, _task.name] : number;
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

/* Lines as Ship and Receive take them: {"<line id>": quantity}. */
static NSDictionary *LBLinesParameter(NSArray *lines, NSArray<NSDecimalNumber *> *quantities) {
    NSMutableDictionary *parameter = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < lines.count; i++) parameter[[[lines[i] valueForKey:@"id"] UUIDString]] = quantities[i];
    return parameter;
}

- (void)move:(NSArray *)lines quantities:(NSArray<NSDecimalNumber *> *)quantities {
    if (!_moveAt) return [self refuse:_sale ? @"Choose where from." : @"Choose where."];
    if (_sale) {
        [self performAction:@"Ship" on:_order parameters:@{ @"Lines": LBLinesParameter(lines, quantities), @"From": _moveAt }];
        return;
    }
    [self receive:lines quantities:quantities];
}

/* Receive the goods' sheet (ReceiveGoods): a receipt of the order, its
   next, recorded by the user now, received today at moveAt (else its
   catalog's first place), a move of each line so many; changed there, and
   submitted. Each move's item, place, moment and maker are the model's. */
- (void)receive:(NSArray *)lines quantities:(NSArray<NSDecimalNumber *> *)quantities {
    if (![self saveChanges]) return;
    if (!lines.count) return [self refuse:@"Nothing of it is outstanding."];
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
    self.receiveForm = [self valuesOfForm:@"ReceiveGoods"
                                    given:@{ @"purchaseOrder" : [[_order valueForKey:@"id"] UUIDString],
                                             @"runningNumber" : [NSString stringWithFormat:@"%d", number + 1],
                                             @"recordedBy" : self.user.email ?: @"",
                                             @"recorded" : [moments stringFromDate:now] }
                                   object:receipt];
    if (!_receiveForm) {
        [self.context rollback];
        return;
    }
    [_receiveForm setValue:now forKey:@"received"];
    [self.window beginSheet:_receivePanel completionHandler:nil];
}

- (IBAction)receiveGoods:(id)sender {
    NSMutableArray *chosen = [NSMutableArray array], *quantities = [NSMutableArray array];
    for (PurchaseLine *line in _lines) {
        NSDecimalNumber *left = line.outstandingQuantity;
        if (!left || [left compare:[NSDecimalNumber zero]] != NSOrderedDescending) continue;
        [chosen addObject:line];
        [quantities addObject:left];
    }
    [self receive:chosen quantities:quantities];
}

- (IBAction)submitReceive:(id)sender {
    if ([self submitForm:_receiveForm sheet:_receivePanel]) [self endForm];
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
