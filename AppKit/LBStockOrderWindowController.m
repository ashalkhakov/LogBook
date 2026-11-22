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
@end

@implementation LBStockOrderWindowController {
    /* A purchase's way through its forms (Model/Purchasing.flow): the order,
       its Confirm the order and Receive the goods over it. */
    ORMFlowSession *_flow;
    NSError *_flowError;
    /* The state the Confirm sheet opens with: Confirm's, Cancel's. */
    NSString *_confirmState;
    /* The lines a Receive is of, so many of each: those chosen. */
    NSArray *_receiving;
    NSArray<NSDecimalNumber *> *_receivingQuantities;
}

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
        if (!sale) {
            NSError *error = nil;
            _flow = [ORMFlowSession flowNamed:@"Purchasing" error:&error];
            if (![_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:&error]) _flowError = error;
        }
    }
    return self;
}

- (ORMFlowSession *)flow {
    return _flow;
}

/* Opened for a task done with a flow's entry: the window, and its step's
   screen over it at once (Confirm the order's sheet). */
- (void)showWindow:(id)sender {
    [super showWindow:sender];
    if (_sale || !_task.entryName || ![_task.flowName isEqualToString:@"Purchasing"] || self.window.attachedSheet) return;
    NSError *error = nil;
    ORMFlowStep *step = [_flow beginAt:_task.entryName key:[[_order valueForKey:@"id"] UUIDString] error:&error];
    if (!step) return [self reportError:error ?: _flowError];
    _confirmState = nil;
    [self show:step];
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
        _confirmState = [name isEqualToString:@"Confirm"] ? @"Confirmed" : @"Cancelled";
        [self trigger:[name isEqualToString:@"Confirm"] ? @"confirmOrder" : @"cancelOrder"];
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
    NSString *about = [[_order valueForKey:@"id"] UUIDString];
    NSString *instance = [LBTasks instanceOf:now.session];
    /* What the form saved, at the server before its task is told: the
       process goes on with the facts. Offline first, where the server
       cannot be reached, the step waits, saved (Window > Tasks), and is
       submitted after a sync. */
    if (![self.store syncAndWait:&error]) {
        if (self.store.local) return [self wait:formName about:about instance:instance task:_task.name];
        [self reportError:error];
        return NO;
    }
    error = nil;
    LBTask *task = [_task.formName isEqualToString:formName] ? _task : [_tasks openTaskOfForm:formName about:about error:&error];
    if (!task && self.store.local && [LBTasks isUnreachable:error]) return [self wait:formName about:about instance:instance task:_task.name];
    if (error) [self reportError:error];
    if (task && ![_tasks submitInstance:instance toTask:task error:&error]) {
        if (self.store.local && [LBTasks isUnreachable:error]) return [self wait:formName about:about instance:instance task:task.name];
        [self reportError:error];
        return NO;
    }
    /* Submitted: one of it that waited is done with. */
    for (LBPendingSubmission *waiting in [self.store.local.appState pendingSubmissions]) {
        if (task && [waiting.formName isEqualToString:formName] && [waiting.businessKey isEqualToString:about]) [self.store.local.appState removeSubmission:waiting];
    }
    _waiting = nil;
    [self stepDone:formName];
    return YES;
}

/* The step saved here, waiting to be submitted (LBAppState): said, unless
   quiet. */
- (BOOL)wait:(NSString *)formName about:(NSString *)about instance:(NSString *)instance task:(NSString *)taskName {
    _waiting = [self.store.local.appState keepSubmissionOfForm:formName about:about taskName:taskName instance:instance];
    if (!self.quiet) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = @"Saved here, not submitted yet";
        alert.informativeText = [NSString stringWithFormat:@"The server cannot be reached. %@ waits in Window > Tasks, and is submitted "
                                                           @"after the next sync.", taskName.length ? taskName : @"The step"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
    return YES;
}

/* The sheet shown gone, and its form, the flow's way on its outcome
   taken (SubmitDone, Cancel: closed back to the order); read again. A flow
   begun at a task's step, done with it: begun again at the order. */
- (void)endForm:(NSString *)on {
    NSWindow *sheet = self.window.attachedSheet;
    if (sheet) [self.window endSheet:sheet];
    [sheet orderOut:nil];
    LBFormValues *shown = _confirmForm ?: _receiveForm;
    ORMFlowWay *way = [_flow wayOn:on control:nil];
    if (way) [_flow take:way row:nil result:shown.session.savedKey values:shown.session.values];
    if (_flow.ended || ![_flow.step.formName isEqualToString:@"EditPurchaseOrder"]) {
        [_flow beginAt:@"Order" key:[[_order valueForKey:@"id"] UUIDString] error:NULL];
    }
    self.confirmForm = nil;
    self.receiveForm = nil;
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
    if ([step.formName isEqualToString:@"ConfirmPurchaseOrder"]) return [self openConfirm:step];
    if ([step.formName isEqualToString:@"ReceiveGoods"]) return [self openReceive:step];
    if (step.formName && ![step.formName isEqualToString:@"EditPurchaseOrder"]) {
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
    if (!lines.count) return [self refuse:@"Nothing of it is outstanding."];
    _receiving = lines;
    _receivingQuantities = quantities;
    [self trigger:@"receiveGoods"];
}

/* The flow's Receive the goods: the lines chosen (else each outstanding),
   so many of each, a receipt of them. */
- (void)openReceive:(ORMFlowStep *)step {
    NSArray *lines = _receiving, *quantities = _receivingQuantities;
    _receiving = nil;
    _receivingQuantities = nil;
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
