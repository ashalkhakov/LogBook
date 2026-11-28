#import "LBStockProcedures.h"
#import "PlanTask+CoreDataClass.h"
#import "LogbookValidation.h"
#import "Income+CoreDataClass.h"
#import "Record+CoreDataClass.h"

NSString * const LBOrderDraft = @"Draft";
NSString * const LBOrderConfirmed = @"Confirmed";
NSString * const LBOrderClosed = @"Closed";
NSString * const LBOrderCancelled = @"Cancelled";

#pragma mark Helpers

static BOOL LBRefuse(NSError **error, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:LBProceduresErrorDomain code:LBProceduresErrorRefused
                                 userInfo:@{ NSLocalizedDescriptionKey: message }];
    }
    return NO;
}

/* An id as a name says it: lower case. */
static NSString *LBText(NSUUID *uuid) {
    return uuid.UUIDString.lowercaseString ?: @"";
}

static id LBNew(Class cls, NSManagedObjectContext *context, NSUUID *uuid) {
    id object = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass(cls) inManagedObjectContext:context];
    [object setValue:uuid ?: [NSUUID UUID] forKey:@"id"];
    return object;
}

/* The object of the entity named so in the context: one made already (this
   change, or saved), else nil. */
static id LBNamed(Class cls, NSManagedObjectContext *context, NSUUID *uuid) {
    for (NSManagedObject *object in context.insertedObjects) {
        if ([object isKindOfClass:cls] && [[object valueForKey:@"id"] isEqual:uuid]) return object;
    }
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    request.predicate = [NSPredicate predicateWithFormat:@"id == %@", uuid];
    request.fetchLimit = 1;
    return [[context executeFetchRequest:request error:NULL] firstObject];
}

static BOOL LBPositive(NSDecimalNumber *quantity) {
    return quantity && quantity != [NSDecimalNumber notANumber] && [quantity compare:[NSDecimalNumber zero]] == NSOrderedDescending;
}

static NSDecimalNumber *LBOr(NSDecimalNumber *quantity, NSDecimalNumber *otherwise) {
    return quantity ?: otherwise;
}

/* The whole number at or above. */
static NSDecimalNumber *LBCeil(NSDecimalNumber *quantity) {
    NSDecimalNumberHandler *up = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundUp scale:0 raiseOnExactness:NO
                                                                              raiseOnOverflow:NO raiseOnUnderflow:NO
                                                                           raiseOnDivideByZero:NO];
    return [quantity decimalNumberByRoundingAccordingToBehavior:up];
}

static NSString *LBQuantityText(NSDecimalNumber *quantity) {
    return [quantity descriptionWithLocale:nil];
}

/* Objects by id, the same in every store: never by the order fetched in. */
static NSInteger LBByID(id a, id b, void *context) {
    (void)context;
    return [LBText([a valueForKey:@"id"]) compare:LBText([b valueForKey:@"id"])];
}

static Move *LBMove(NSManagedObjectContext *context, NSUUID *uuid, StockItem *item, NSDecimalNumber *quantity,
                    Location *from, Location *to, User *user, NSDate *now) {
    Move *move = LBNew([Move class], context, uuid);
    move.stockItem = item;
    move.moved = quantity;
    move.source = from;
    move.destination = to;
    move.user = user;
    move.moment = now;
    if (from) [from lb_holdingOf:item];
    if (to) [to lb_holdingOf:item];
    return move;
}

/* Refused where the location holds less of the item than so much more
   would take. */
static BOOL LBHolds(Location *location, StockItem *item, NSDecimalNumber *quantity, NSError **error) {
    NSDecimalNumber *held = [location lb_heldOf:item];
    if ([held compare:quantity] == NSOrderedAscending) {
        return LBRefuse(error, [NSString stringWithFormat:@"%@ holds %@ of %@, not %@.", location.locationName, LBQuantityText(held),
                                                          item.itemName, LBQuantityText(quantity)]);
    }
    return YES;
}

@implementation LBCounted
+ (instancetype)countedItem:(StockItem *)item at:(Location *)location quantity:(NSDecimalNumber *)quantity {
    LBCounted *counted = [[self alloc] init];
    counted->_item = item;
    counted->_location = location;
    counted->_quantity = quantity;
    return counted;
}
@end

#pragma mark Numbers

static NSString *LBNumber(Catalog *catalog, NSString *kind, int32_t number) {
    NSMutableArray *parts = [NSMutableArray arrayWithObject:kind];
    if (catalog.documentPrefix.length) [parts addObject:catalog.documentPrefix];
    [parts addObject:[NSString stringWithFormat:@"%04d", number]];
    return [parts componentsJoinedByString:@"-"];
}

static int32_t LBNextOf(NSSet *documents) {
    int32_t highest = 0;
    for (id document in documents) highest = MAX(highest, [[document valueForKey:@"runningNumber"] intValue]);
    return highest + 1;
}

@implementation Catalog (LBStock)

+ (Catalog *)lb_newCatalogNamed:(NSString *)name owner:(User *)owner inContext:(NSManagedObjectContext *)context {
    Catalog *catalog = LBNew([Catalog class], context, nil);
    catalog.catalogName = name;
    catalog.catalogOwner = owner;
    catalog.currency = owner.currency;
    Warehouse *main = LBNew([Warehouse class], context, nil);
    main.warehouseName = @"Main";
    main.catalog = catalog;
    Location *place = LBNew([Location class], context, nil);
    place.locationName = @"Default";
    place.warehouse = main;
    return catalog;
}

- (SaleOrder *)lb_newSaleOrderTo:(Customer *)customer on:(NSDate *)day {
    SaleOrder *order = LBNew([SaleOrder class], self.managedObjectContext, nil);
    order.runningNumber = LBNextOf(self.saleOrders);
    order.catalog = self;
    order.customer = customer;
    order.saleOrdered = LBDay(day);
    order.orderState = LBOrderDraft;
    order.shipTo = customer.contact.shippingAddress;
    order.billTo = customer.contact.billingAddress;
    return order;
}

- (PurchaseOrder *)lb_newPurchaseOrderFrom:(Supplier *)supplier on:(NSDate *)day {
    PurchaseOrder *order = LBNew([PurchaseOrder class], self.managedObjectContext, nil);
    order.runningNumber = LBNextOf(self.purchaseOrders);
    order.catalog = self;
    order.supplier = supplier;
    order.ordered = LBDay(day);
    order.orderState = LBOrderDraft;
    return order;
}

- (NSString *)lb_nextSKU {
    NSString *prefix = [(self.documentPrefix.length ? self.documentPrefix : @"SKU") stringByAppendingString:@"-"];
    long highest = 0;
    for (StockItem *item in self.stockItems) {
        NSString *sku = item.sku;
        if (![sku hasPrefix:prefix]) continue;
        NSString *rest = [sku substringFromIndex:prefix.length];
        NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if (rest.length && [rest rangeOfCharacterFromSet:notDigits].location == NSNotFound) highest = MAX(highest, (long)rest.longLongValue);
    }
    return [NSString stringWithFormat:@"%@%05ld", prefix, highest + 1];
}

- (int32_t)lb_nextNumberOf:(NSSet *)documents {
    return LBNextOf(documents);
}

- (NSString *)lb_numberOfKind:(NSString *)kind running:(int32_t)number {
    return LBNumber(self, kind, number);
}

@end

#pragma mark Contacts

@implementation Contact (LBStock)

- (BOOL)lb_isCustomer {
    return self.customer != nil && !self.customer.isDeleted;
}

/* Both sides of the relationship set here: set through a binding (the
   settings' Customer box, KVO's will/did change of lb_isCustomer around
   it), Core Data leaves this contact's side as it was, and each click
   made another customer of no one. */
- (void)setLb_isCustomer:(BOOL)flag {
    if (flag == self.lb_isCustomer) return;
    if (flag) {
        Customer *customer = LBNew([Customer class], self.managedObjectContext, nil);
        customer.contact = self;
        customer.catalog = self.catalog;
        self.customer = customer;
    } else if (self.customer.saleOrders.count == 0) {
        Customer *customer = self.customer;
        self.customer = nil;
        [self.managedObjectContext deleteObject:customer];
    }
}

- (BOOL)lb_isSupplier {
    return self.supplier != nil && !self.supplier.isDeleted;
}

- (void)setLb_isSupplier:(BOOL)flag {
    if (flag == self.lb_isSupplier) return;
    if (flag) {
        Supplier *supplier = LBNew([Supplier class], self.managedObjectContext, nil);
        supplier.contact = self;
        supplier.catalog = self.catalog;
        self.supplier = supplier;
    } else if (self.supplier.purchaseOrders.count == 0 && self.supplier.supplierItems.count == 0) {
        Supplier *supplier = self.supplier;
        self.supplier = nil;
        [self.managedObjectContext deleteObject:supplier];
    }
}

- (NSString *)lb_shippingLines {
    return self.shippingAddress.addressLines;
}

- (void)setLb_shippingLines:(NSString *)lines {
    if (!self.shippingAddress) {
        if (!lines.length) return;
        Address *address = LBNew([Address class], self.managedObjectContext, nil);
        [self addAddressesObject:address];
        self.shippingAddress = address;
        if (!self.billingAddress) self.billingAddress = address;
    }
    self.shippingAddress.addressLines = lines;
}

@end

#pragma mark Holdings

@implementation Location (LBStock)

- (NSDecimalNumber *)lb_heldOf:(StockItem *)item {
    NSDecimalNumber *held = [NSDecimalNumber zero];
    for (Move *move in item.moves) {
        if (move.isDeleted || !move.moved) continue;
        if (move.destination == self) held = [held decimalNumberByAdding:move.moved];
        if (move.source == self) held = [held decimalNumberBySubtracting:move.moved];
    }
    return held;
}

- (Holding *)lb_holdingOf:(StockItem *)item {
    for (Holding *holding in item.holdings) {
        if (holding.location == self && !holding.isDeleted) return holding;
    }
    NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ at %@", LBText(item.id), LBText(self.id)]);
    Holding *holding = LBNamed([Holding class], self.managedObjectContext, uuid) ?: LBNew([Holding class], self.managedObjectContext, uuid);
    holding.stockItem = item;
    holding.location = self;
    return holding;
}

@end

#pragma mark Items: transfers, adjustments, assemblies

@implementation StockItem (LBStock)

- (Supplier *)lb_preferredSupplier {
    return self.preferredSupplierItem.supplier;
}

- (void)setLb_preferredSupplier:(Supplier *)supplier {
    if (supplier == self.lb_preferredSupplier) return;
    if (!supplier) {
        self.preferredSupplierItem = nil;
        return;
    }
    SupplierItem *bought = nil;
    for (SupplierItem *each in self.supplierItems) {
        if (each.supplier == supplier && !each.isDeleted) bought = each;
    }
    if (!bought) {
        bought = LBNew([SupplierItem class], self.managedObjectContext, nil);
        bought.supplier = supplier;
        [self addSupplierItemsObject:bought];
    }
    self.preferredSupplierItem = bought;
}

- (SupplierItem *)lb_reorderedAs {
    if (self.preferredSupplierItem && !self.preferredSupplierItem.isDeleted) return self.preferredSupplierItem;
    NSArray *live = [self.supplierItems.allObjects filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDeleted == NO"]];
    return live.count == 1 ? live[0] : nil;
}

- (Move *)lb_transfer:(NSDecimalNumber *)quantity from:(Location *)from to:(Location *)to by:(User *)user at:(NSDate *)now
                error:(NSError **)error {
    if (!LBPositive(quantity)) return LBRefuse(error, @"Say how many to move."), nil;
    if (from == to) return LBRefuse(error, @"Moved to where it is: choose another location."), nil;
    if (self.isAPhantomKit) return LBRefuse(error, @"A phantom kit is never kept: move its components."), nil;
    if (!LBHolds(from, self, quantity, error)) return nil;
    return LBMove(self.managedObjectContext, nil, self, quantity, from, to, user, now);
}

- (Move *)lb_adjust:(NSDecimalNumber *)quantity at:(Location *)location reason:(NSString *)reason note:(NSString *)note
                 by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (!quantity || [quantity compare:[NSDecimalNumber zero]] == NSOrderedSame) return LBRefuse(error, @"Say how many more, or fewer."), nil;
    if ([reason isEqualToString:@"Count"]) return LBRefuse(error, @"A count adjusts by counting: count the location."), nil;
    if (self.isAPhantomKit) return LBRefuse(error, @"A phantom kit is never kept: adjust its components."), nil;
    BOOL out = [quantity compare:[NSDecimalNumber zero]] == NSOrderedAscending;
    NSDecimalNumber *size = out ? [[NSDecimalNumber zero] decimalNumberBySubtracting:quantity] : quantity;
    if (out && !LBHolds(location, self, size, error)) return nil;
    Move *move = LBMove(self.managedObjectContext, nil, self, size, out ? location : nil, out ? nil : location, user, now);
    move.adjustmentReason = reason;
    move.note = note;
    return move;
}

- (Assembly *)lb_assemble:(NSDecimalNumber *)batches at:(Location *)location on:(NSDate *)day disassemble:(BOOL)disassemble
                       by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (self.kitLinesAsKit.count == 0) return LBRefuse(error, [NSString stringWithFormat:@"%@ is no kit: give it a recipe.", self.itemName]), nil;
    if (self.isAPhantomKit) return LBRefuse(error, @"A phantom kit is never assembled: it is sold as its components."), nil;
    if (!LBPositive(batches)) return LBRefuse(error, @"Say how many batches."), nil;
    NSDecimalNumber *made = [batches decimalNumberByMultiplyingBy:LBOr(self.yield, [NSDecimalNumber one])];
    NSArray *lines = [self.kitLinesAsKit.allObjects sortedArrayUsingFunction:LBByID context:NULL];
    /* What goes out must be there. */
    if (disassemble) {
        if (!LBHolds(location, self, made, error)) return nil;
    } else {
        for (KitLine *line in lines) {
            if (!LBHolds(location, line.component, [batches decimalNumberByMultiplyingBy:line.perBatch], error)) return nil;
        }
    }
    NSManagedObjectContext *context = self.managedObjectContext;
    Assembly *assembly = LBNew([Assembly class], context, nil);
    assembly.assembled = self;
    assembly.batches = batches;
    assembly.assembledAt = location;
    assembly.assembledOn = LBDay(day);
    assembly.isADisassembly = disassemble;
    for (KitLine *line in lines) {
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ uses %@", LBText(assembly.id), LBText(line.component.id)]);
        Move *move = LBMove(context, uuid, line.component, [batches decimalNumberByMultiplyingBy:line.perBatch],
                            disassemble ? nil : location, disassemble ? location : nil, user, now);
        move.assembly = assembly;
    }
    Move *kit = LBMove(context, LBNamedUUID([NSString stringWithFormat:@"%@ makes", LBText(assembly.id)]), self, made,
                       disassemble ? location : nil, disassemble ? nil : location, user, now);
    kit.assembly = assembly;
    return assembly;
}

@end

@implementation SupplierItem (LBStock)

- (BOOL)lb_isPreferred {
    return self.stockItem.preferredSupplierItem == self;
}

- (void)setLb_isPreferred:(BOOL)preferred {
    if (preferred) self.stockItem.preferredSupplierItem = self;
    else if (self.lb_isPreferred) self.stockItem.preferredSupplierItem = nil;
}

@end

#pragma mark Orders

/* An order's state changed from one of those given, or refused. */
static BOOL LBState(NSManagedObject *order, NSArray<NSString *> *from, NSString *to, NSString *what, NSError **error) {
    NSString *state = [order valueForKey:@"orderState"];
    if (![from containsObject:state ?: @""]) {
        return LBRefuse(error, [NSString stringWithFormat:@"A %@ order cannot be %@.", [state lowercaseString] ?: @"new", what]);
    }
    [order setValue:to forKey:@"orderState"];
    return YES;
}

/* Lines by id, those of the order given: refused for one of another, none
   of one, or none at all. */
static NSArray *LBLines(NSSet *lines, NSDictionary<NSUUID *, NSDecimalNumber *> *quantities, NSError **error) {
    if (quantities.count == 0) return LBRefuse(error, @"Say how many of which lines."), nil;
    NSMutableArray *chosen = [NSMutableArray array];
    for (NSUUID *uuid in quantities) {
        id found = nil;
        for (id line in lines) {
            if ([[line valueForKey:@"id"] isEqual:uuid]) found = line;
        }
        if (!found) return LBRefuse(error, @"A line is not of this order."), nil;
        if (!LBPositive(quantities[uuid])) return LBRefuse(error, @"Say how many of each line, more than none."), nil;
        [chosen addObject:found];
    }
    return [chosen sortedArrayUsingFunction:LBByID context:NULL];
}

/* How many the moves moved, those deleted left out. */
static NSDecimalNumber *LBMovedBy(NSSet<Move *> *moves) {
    NSDecimalNumber *moved = [NSDecimalNumber zero];
    for (Move *move in moves) {
        if (!move.isDeleted && move.moved) moved = [moved decimalNumberByAdding:move.moved];
    }
    return moved;
}

@implementation SaleLine (LBStock)

- (NSDecimalNumber *)lb_kept {
    return [(self.quantity ?: [NSDecimalNumber zero]) decimalNumberBySubtracting:LBMovedBy(self.movesAsReturnedSaleLine)];
}

- (BOOL)lb_delete:(NSError **)error {
    NSArray *lines = [@[ self ] arrayByAddingObjectsFromArray:self.saleLinesAsExpandedFrom.allObjects];
    for (SaleLine *line in lines) {
        for (Move *move in line.moves) {
            if (!move.isDeleted) return LBRefuse(error, @"Some of it has been shipped: it stays.");
        }
    }
    for (SaleLine *line in lines) [self.managedObjectContext deleteObject:line];
    return YES;
}

@end

/* Refused unless the order is confirmed or closed: what went out or came
   in of it may come back. */
static BOOL LBReturnable(NSManagedObject *order, NSError **error) {
    NSString *state = [order valueForKey:@"orderState"];
    if (![@[ LBOrderConfirmed, LBOrderClosed ] containsObject:state ?: @""]) {
        return LBRefuse(error, [NSString stringWithFormat:@"Nothing of a %@ order comes back.", [state lowercaseString] ?: @"new"]);
    }
    return YES;
}

static NSArray *LBCustomerReturnLines(SaleOrder *order, NSDictionary<NSUUID *, NSDecimalNumber *> *quantities, NSError **error);
static NSArray *LBSupplierReturnLines(PurchaseOrder *order, NSDictionary<NSUUID *, NSDecimalNumber *> *quantities, Location *location,
                                      NSError **error);

@implementation SaleOrder (LBStock)

- (NSString *)lb_number {
    return LBNumber(self.catalog, @"SO", self.runningNumber);
}

- (BOOL)lb_confirm:(NSError **)error {
    if ([self.orderState isEqualToString:LBOrderDraft] && self.saleLines.count == 0) {
        return LBRefuse(error, @"An order of nothing: add its lines.");
    }
    if ([self.orderState isEqualToString:LBOrderDraft] && ![self lb_expandKits:error]) return NO;
    return LBState(self, @[ LBOrderDraft ], LBOrderConfirmed, @"confirmed", error);
}

- (BOOL)lb_close:(NSError **)error {
    return LBState(self, @[ LBOrderConfirmed ], LBOrderClosed, @"closed", error);
}

- (BOOL)lb_cancel:(NSError **)error {
    for (Shipment *shipment in self.shipments) {
        if (!shipment.isDeleted) return LBRefuse(error, @"Some of it has been shipped: close it instead.");
    }
    return LBState(self, @[ LBOrderDraft, LBOrderConfirmed ], LBOrderCancelled, @"cancelled", error);
}

- (BOOL)lb_reopen:(NSError **)error {
    return LBState(self, @[ LBOrderClosed ], LBOrderConfirmed, @"reopened", error);
}

- (BOOL)lb_expandKits:(NSError **)error {
    NSManagedObjectContext *context = self.managedObjectContext;
    NSArray *lines = [self.saleLines.allObjects sortedArrayUsingFunction:LBByID context:NULL];
    /* What each kit line's components should be, checked before anything
       is changed. */
    NSMutableArray *plans = [NSMutableArray array];
    for (SaleLine *kitLine in lines) {
        if (kitLine.isDeleted || kitLine.expandedFrom || !kitLine.stockItem.isAPhantomKit) continue;
        NSDecimalNumber *batches = LBCeil([kitLine.quantity decimalNumberByDividingBy:LBOr(kitLine.stockItem.yield, [NSDecimalNumber one])]);
        NSMutableDictionary *wanted = [NSMutableDictionary dictionary];
        for (KitLine *recipe in kitLine.stockItem.kitLinesAsKit) {
            wanted[recipe.component.objectID] = @[ recipe.component, [batches decimalNumberByMultiplyingBy:recipe.perBatch] ];
        }
        for (SaleLine *component in kitLine.saleLinesAsExpandedFrom) {
            NSDecimalNumber *quantity = wanted[component.stockItem.objectID][1] ?: [NSDecimalNumber zero];
            NSDecimalNumber *shipped = [NSDecimalNumber zero];
            for (Move *move in component.moves) {
                if (!move.isDeleted) shipped = [shipped decimalNumberByAdding:move.moved];
            }
            if ([shipped compare:quantity] == NSOrderedDescending) {
                return LBRefuse(error, [NSString stringWithFormat:@"%@ of %@ have been shipped for %@: more than it would then take.",
                                                                  LBQuantityText(shipped), component.stockItem.itemName,
                                                                  kitLine.stockItem.itemName]);
            }
        }
        [plans addObject:@[ kitLine, wanted ]];
    }
    for (NSArray *plan in plans) {
        SaleLine *kitLine = plan[0];
        NSMutableDictionary *wanted = [plan[1] mutableCopy];
        for (SaleLine *component in [kitLine.saleLinesAsExpandedFrom.allObjects sortedArrayUsingFunction:LBByID context:NULL]) {
            NSArray *want = wanted[component.stockItem.objectID];
            if (!want) {
                [context deleteObject:component];
                continue;
            }
            if ([component.quantity compare:want[1]] != NSOrderedSame) component.quantity = want[1];
            [wanted removeObjectForKey:component.stockItem.objectID];
        }
        for (NSArray *want in wanted.allValues) {
            StockItem *item = want[0];
            NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ component %@", LBText(kitLine.id), LBText(item.id)]);
            SaleLine *component = LBNamed([SaleLine class], context, uuid) ?: LBNew([SaleLine class], context, uuid);
            component.saleOrder = self;
            component.expandedFrom = kitLine;
            component.stockItem = item;
            component.quantity = want[1];
        }
    }
    return YES;
}

- (Shipment *)lb_shipLines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities from:(Location *)location on:(NSDate *)day
                        by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (![self.orderState isEqualToString:LBOrderConfirmed]) return LBRefuse(error, @"Only a confirmed order is shipped."), nil;
    NSArray *lines = LBLines(self.saleLines, quantities, error);
    if (!lines) return nil;
    for (SaleLine *line in lines) {
        if (line.stockItem.isAPhantomKit) {
            return LBRefuse(error, [NSString stringWithFormat:@"%@ is a phantom kit: ship its components' lines.", line.stockItem.itemName]), nil;
        }
        if (!LBHolds(location, line.stockItem, quantities[line.id], error)) return nil;
    }
    NSManagedObjectContext *context = self.managedObjectContext;
    int32_t number = LBNextOf(self.shipments);
    Shipment *shipment = LBNew([Shipment class], context,
                               LBNamedUUID([NSString stringWithFormat:@"%@ shipment %d", LBText(self.id), number]));
    shipment.saleOrder = self;
    shipment.runningNumber = number;
    shipment.shipped = LBDay(day);
    shipment.shippedFrom = location;
    shipment.shippedTo = self.shipTo;
    for (SaleLine *line in lines) {
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ for %@", LBText(shipment.id), LBText(line.id)]);
        Move *move = LBMove(context, uuid, line.stockItem, quantities[line.id], location, nil, user, now);
        move.shipment = shipment;
        move.saleLine = line;
    }
    return shipment;
}

- (CustomerReturn *)lb_returnLines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities at:(Location *)location on:(NSDate *)day
                            reason:(NSString *)reason note:(NSString *)note by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (!location) return LBRefuse(error, @"Say where it came back to."), nil;
    if (!LBCustomerReturnLines(self, quantities, error)) return nil;
    NSManagedObjectContext *context = self.managedObjectContext;
    int32_t number = LBNextOf(self.customerReturns);
    CustomerReturn *back = LBNew([CustomerReturn class], context, LBNamedUUID([NSString stringWithFormat:@"%@ return %d", LBText(self.id), number]));
    back.saleOrder = self;
    back.runningNumber = number;
    back.returnReceived = LBDay(day);
    back.returnedTo = location;
    back.returnReason = reason;
    back.note = note;
    back.returnState = @"Returned";
    if (![back lb_receive:quantities by:user at:now error:error]) {
        [context deleteObject:back];
        return nil;
    }
    return back;
}

@end

/* The order's lines so many of which come back: refused for an order not
   confirmed or closed, a line not of it, a phantom kit's, or more than
   went out and has not come back. */
static NSArray *LBCustomerReturnLines(SaleOrder *order, NSDictionary<NSUUID *, NSDecimalNumber *> *quantities, NSError **error) {
    if (!LBReturnable(order, error)) return nil;
    NSArray *lines = LBLines(order.saleLines, quantities, error);
    if (!lines) return nil;
    for (SaleLine *line in lines) {
        if (line.stockItem.isAPhantomKit) {
            return LBRefuse(error, [NSString stringWithFormat:@"%@ is a phantom kit: return its components' lines.", line.stockItem.itemName]), nil;
        }
        NSDecimalNumber *out = [LBMovedBy(line.moves) decimalNumberBySubtracting:LBMovedBy(line.movesAsReturnedSaleLine)];
        if ([quantities[line.id] compare:out] == NSOrderedDescending) {
            return LBRefuse(error, [NSString stringWithFormat:@"%@ of %@ went out and have not come back, not %@.", LBQuantityText(out),
                                                              line.stockItem.itemName, LBQuantityText(quantities[line.id])]), nil;
        }
    }
    return lines;
}

@implementation CustomerReturn (LBStock)

- (BOOL)lb_receive:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (!self.returnedTo || !self.returnReceived) return LBRefuse(error, @"Say where it came back to, and on what day.");
    NSArray *lines = LBCustomerReturnLines(self.saleOrder, quantities, error);
    if (!lines) return NO;
    for (SaleLine *line in lines) {
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ for %@", LBText(self.id), LBText(line.id)]);
        Move *move = LBMove(self.managedObjectContext, uuid, line.stockItem, quantities[line.id], nil, self.returnedTo, user, now);
        move.customerReturn = self;
        move.returnedSaleLine = line;
    }
    return YES;
}

- (BOOL)lb_receiveAsked:(NSError **)error {
    NSMutableDictionary *quantities = [NSMutableDictionary dictionary];
    for (CustomerReturnLine *line in self.customerReturnLines) {
        if (line.isDeleted || !line.saleLine.id || !line.askedQuantity) continue;
        quantities[line.saleLine.id] = [quantities[line.saleLine.id] ?: [NSDecimalNumber zero] decimalNumberByAdding:line.askedQuantity];
    }
    return [self lb_receive:quantities by:self.returnRecordedBy ?: self.returnAskedBy at:self.returnRecorded ?: [NSDate date] error:error];
}

@end

@implementation PurchaseOrder (LBStock)

- (NSString *)lb_number {
    return LBNumber(self.catalog, @"PO", self.runningNumber);
}

- (BOOL)lb_confirm:(NSError **)error {
    if ([self.orderState isEqualToString:LBOrderDraft] && self.purchaseLines.count == 0) {
        return LBRefuse(error, @"An order of nothing: add its lines.");
    }
    return LBState(self, @[ LBOrderDraft ], LBOrderConfirmed, @"confirmed", error);
}

- (BOOL)lb_close:(NSError **)error {
    return LBState(self, @[ LBOrderConfirmed ], LBOrderClosed, @"closed", error);
}

- (BOOL)lb_cancel:(NSError **)error {
    for (Receipt *receipt in self.receipts) {
        if (!receipt.isDeleted) return LBRefuse(error, @"Some of it has been received: close it instead.");
    }
    return LBState(self, @[ LBOrderDraft, LBOrderConfirmed ], LBOrderCancelled, @"cancelled", error);
}

- (BOOL)lb_reopen:(NSError **)error {
    return LBState(self, @[ LBOrderClosed ], LBOrderConfirmed, @"reopened", error);
}

- (Receipt *)lb_receiveLines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities at:(Location *)location on:(NSDate *)day
                          by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (![self.orderState isEqualToString:LBOrderConfirmed]) return LBRefuse(error, @"Only a confirmed order is received."), nil;
    NSArray *lines = LBLines(self.purchaseLines, quantities, error);
    if (!lines) return nil;
    NSManagedObjectContext *context = self.managedObjectContext;
    int32_t number = LBNextOf(self.receipts);
    Receipt *receipt = LBNew([Receipt class], context, LBNamedUUID([NSString stringWithFormat:@"%@ receipt %d", LBText(self.id), number]));
    receipt.purchaseOrder = self;
    receipt.runningNumber = number;
    receipt.received = LBDay(day);
    receipt.receivedAt = location;
    for (PurchaseLine *line in lines) {
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ for %@", LBText(receipt.id), LBText(line.id)]);
        Move *move = LBMove(context, uuid, line.stockItem, quantities[line.id], nil, location, user, now);
        move.receipt = receipt;
        move.purchaseLine = line;
    }
    return receipt;
}

- (SupplierReturn *)lb_returnLines:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities from:(Location *)location on:(NSDate *)day
                            reason:(NSString *)reason note:(NSString *)note by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (!location) return LBRefuse(error, @"Say where it went back from."), nil;
    if (!LBSupplierReturnLines(self, quantities, location, error)) return nil;
    NSManagedObjectContext *context = self.managedObjectContext;
    int32_t number = LBNextOf(self.supplierReturns);
    SupplierReturn *back = LBNew([SupplierReturn class], context, LBNamedUUID([NSString stringWithFormat:@"%@ return %d", LBText(self.id), number]));
    back.purchaseOrder = self;
    back.runningNumber = number;
    back.returnShipped = LBDay(day);
    back.returnedFrom = location;
    back.returnReason = reason;
    back.note = note;
    back.returnState = @"Returned";
    if (![back lb_send:quantities by:user at:now error:error]) {
        [context deleteObject:back];
        return nil;
    }
    return back;
}

@end

/* The order's lines so many of which go back from the location: refused
   as Return refuses it, or where less is held there. */
static NSArray *LBSupplierReturnLines(PurchaseOrder *order, NSDictionary<NSUUID *, NSDecimalNumber *> *quantities, Location *location,
                                      NSError **error) {
    if (!LBReturnable(order, error)) return nil;
    NSArray *lines = LBLines(order.purchaseLines, quantities, error);
    if (!lines) return nil;
    for (PurchaseLine *line in lines) {
        NSDecimalNumber *in = [LBMovedBy(line.moves) decimalNumberBySubtracting:LBMovedBy(line.movesAsReturnedPurchaseLine)];
        if ([quantities[line.id] compare:in] == NSOrderedDescending) {
            return LBRefuse(error, [NSString stringWithFormat:@"%@ of %@ came in and have not gone back, not %@.", LBQuantityText(in),
                                                              line.stockItem.itemName, LBQuantityText(quantities[line.id])]), nil;
        }
        if (!LBHolds(location, line.stockItem, quantities[line.id], error)) return nil;
    }
    return lines;
}

@implementation SupplierReturn (LBStock)

- (BOOL)lb_send:(NSDictionary<NSUUID *, NSDecimalNumber *> *)quantities by:(User *)user at:(NSDate *)now error:(NSError **)error {
    Location *location = self.returnedFrom;
    if (!location || !self.returnShipped) return LBRefuse(error, @"Say where it went back from, and on what day.");
    NSArray *lines = LBSupplierReturnLines(self.purchaseOrder, quantities, location, error);
    if (!lines) return NO;
    for (PurchaseLine *line in lines) {
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ for %@", LBText(self.id), LBText(line.id)]);
        Move *move = LBMove(self.managedObjectContext, uuid, line.stockItem, quantities[line.id], location, nil, user, now);
        move.supplierReturn = self;
        move.returnedPurchaseLine = line;
    }
    return YES;
}

- (BOOL)lb_sendAsked:(NSError **)error {
    NSMutableDictionary *quantities = [NSMutableDictionary dictionary];
    for (SupplierReturnLine *line in self.supplierReturnLines) {
        if (line.isDeleted || !line.purchaseLine.id || !line.askedQuantity) continue;
        quantities[line.purchaseLine.id] = [quantities[line.purchaseLine.id] ?: [NSDecimalNumber zero] decimalNumberByAdding:line.askedQuantity];
    }
    return [self lb_send:quantities by:self.returnRecordedBy ?: self.returnAskedBy at:self.returnRecorded ?: [NSDate date] error:error];
}

@end

#pragma mark Counts and reordering

/* What was counted, by its item's id, then its location's. */
static NSInteger LBByItemAndLocation(id a, id b, void *context) {
    (void)context;
    LBCounted *x = a, *y = b;
    NSComparisonResult byItem = [LBText(x.item.id) compare:LBText(y.item.id)];
    return byItem != NSOrderedSame ? byItem : [LBText(x.location.id) compare:LBText(y.location.id)];
}

/* Whether the location is the one counted, or within it. */
static BOOL LBWithin(Location *location, Location *counted) {
    for (Location *at = location; at; at = at.container) {
        if (at == counted) return YES;
    }
    return NO;
}

@implementation Warehouse (LBStock)

- (StockCount *)lb_countLocation:(Location *)location found:(NSArray<LBCounted *> *)found on:(NSDate *)day by:(User *)user
                              at:(NSDate *)now error:(NSError **)error {
    if (location && location.warehouse != self) return LBRefuse(error, @"That location is in another warehouse."), nil;
    NSManagedObjectContext *context = self.managedObjectContext;
    StockCount *count = LBNew([StockCount class], context, nil);
    count.warehouse = self;
    count.countedLocation = location;
    count.countedOn = LBDay(day);
    count.counter = user;
    count.runningNumber = LBNextOf(self.stockCounts);
    if (![count lb_postFound:found at:now error:error]) {
        [context deleteObject:count];
        return nil;
    }
    count.countState = @"Posted";
    return count;
}

- (NSArray<PurchaseOrder *> *)lb_reorderOn:(NSDate *)day skipped:(NSArray<StockItem *> **)skipped error:(NSError **)error {
    (void)error;
    NSManagedObjectContext *context = self.managedObjectContext;
    NSMutableArray *left = [NSMutableArray array];
    NSMutableArray *made = [NSMutableArray array];
    NSMutableDictionary *orders = [NSMutableDictionary dictionary];
    NSString *dayText = [NSString stringWithFormat:@"%.0f", [LBDay(day) timeIntervalSince1970]];
    for (ReorderRule *rule in [self.reorderRules.allObjects sortedArrayUsingFunction:LBByID context:NULL]) {
        if (!rule.isDue) continue;
        StockItem *item = rule.stockItem;
        SupplierItem *bought = item.lb_reorderedAs;
        NSDecimalNumber *cost = bought.supplierCostAmount ?: item.unitCostAmount;
        NSString *currency = bought.supplierCostAmount ? bought.supplierCostCurrency : item.unitCostCurrency;
        if (!bought || !cost) {
            [left addObject:item];
            continue;
        }
        NSDecimalNumber *has = [LBOr(item.available, [NSDecimalNumber zero]) decimalNumberByAdding:LBOr(item.incoming, [NSDecimalNumber zero])];
        NSDecimalNumber *wanted = [LBOr(rule.reorderLevel, rule.reorderPoint) decimalNumberBySubtracting:has];
        if (!LBPositive(wanted)) continue;
        /* At least its minimum, in whole packs. */
        if (bought.minimumOrder && [wanted compare:bought.minimumOrder] == NSOrderedAscending) wanted = bought.minimumOrder;
        if (LBPositive(bought.packSize)) {
            wanted = [LBCeil([wanted decimalNumberByDividingBy:bought.packSize]) decimalNumberByMultiplyingBy:bought.packSize];
        }
        Supplier *supplier = bought.supplier;
        PurchaseOrder *order = orders[supplier.objectID];
        if (!order) {
            NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"reorder at %@ on %@ from %@", LBText(self.id), dayText,
                                                                  LBText(supplier.id)]);
            order = LBNamed([PurchaseOrder class], context, uuid);
            if (!order) {
                order = [self.catalog lb_newPurchaseOrderFrom:supplier on:day];
                order.id = uuid;
            }
            orders[supplier.objectID] = order;
            [made addObject:order];
        }
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ for %@", LBText(order.id), LBText(item.id)]);
        PurchaseLine *line = LBNamed([PurchaseLine class], context, uuid) ?: LBNew([PurchaseLine class], context, uuid);
        line.purchaseOrder = order;
        line.stockItem = item;
        line.quantity = wanted;
        line.lineUnitCostAmount = cost;
        line.lineUnitCostCurrency = currency ?: self.catalog.currency;
    }
    if (skipped) *skipped = left;
    return made;
}

@end

#pragma mark Parts used by services and tyre changes

@implementation Catalog (LBParts)

- (Customer *)lb_customerFor:(User *)user {
    for (Contact *contact in self.contacts) {
        if (contact.user == user && !contact.isDeleted) {
            if (!contact.lb_isCustomer) contact.lb_isCustomer = YES;
            return contact.customer;
        }
    }
    NSManagedObjectContext *context = self.managedObjectContext;
    NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ contact of %@", LBText(self.id), user.email.lowercaseString ?: @""]);
    Contact *contact = LBNamed([Contact class], context, uuid);
    if (!contact) {
        contact = LBNew([Contact class], context, uuid);
        contact.catalog = self;
        contact.user = user;
        contact.contactName = user.personName.length ? user.personName : user.email;
        contact.emailAddress = user.email;
    }
    if (!contact.customer || contact.customer.isDeleted) {
        NSUUID *customerID = LBNamedUUID([NSString stringWithFormat:@"%@ customer", LBText(contact.id)]);
        Customer *customer = LBNamed([Customer class], context, customerID) ?: LBNew([Customer class], context, customerID);
        customer.contact = contact;
        customer.catalog = self;
    }
    return contact.customer;
}

@end

@implementation Event (LBParts)

- (BOOL)lb_usesParts {
    return [self isKindOfClass:[Service class]] || [self isKindOfClass:[TyreChange class]];
}

- (SaleOrder *)lb_partsSale {
    if (!self.lb_usesParts) return nil;
    SaleOrder *sale = [self valueForKey:@"partsSale"];
    return sale.isDeleted ? nil : sale;
}

- (SaleLine *)lb_usePart:(StockItem *)item quantity:(NSDecimalNumber *)quantity from:(Location *)location error:(NSError **)error {
    if (!self.lb_usesParts) return LBRefuse(error, @"Only a service or a tyre change uses parts."), nil;
    if (!LBPositive(quantity)) return LBRefuse(error, @"Say how many of it were used."), nil;
    /* At its unit cost; with none, at its price; with neither, what it is
       sold at is for someone to say first. */
    BOOL costed = LBPositive(item.unitCostAmount);
    if (!costed && !LBPositive(item.priceAmount)) {
        return LBRefuse(error, [NSString stringWithFormat:@"%@ has no unit cost or price: give it one first.", item.itemName]), nil;
    }
    Catalog *catalog = item.catalog;
    if (location.warehouse.catalog != catalog) return LBRefuse(error, @"That location keeps another catalog's stock."), nil;
    SaleOrder *sale = self.lb_partsSale;
    if (sale && sale.catalog != catalog) return LBRefuse(error, @"Its parts come from another catalog."), nil;
    NSManagedObjectContext *context = self.managedObjectContext;
    if (!sale) {
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"parts of %@", LBText(self.id)]);
        sale = LBNamed([SaleOrder class], context, uuid);
        if (!sale) {
            sale = [catalog lb_newSaleOrderTo:[catalog lb_customerFor:self.vehicle.owner] on:LBEventDay(self)];
            sale.id = uuid;
        }
        sale.shipsFrom = location;
        [self setValue:sale forKey:@"partsSale"];
    }
    SaleLine *line = LBNew([SaleLine class], context, nil);
    line.saleOrder = sale;
    line.stockItem = item;
    line.quantity = quantity;
    line.linePriceAmount = costed ? item.unitCostAmount : item.priceAmount;
    line.linePriceCurrency = (costed ? item.unitCostCurrency : item.priceCurrency) ?: catalog.currency;
    return line;
}

/* How many of the line have been shipped: its moves'. */
static NSDecimalNumber *LBShippedOf(SaleLine *line) {
    return LBMovedBy(line.moves);
}

- (BOOL)lb_setUsed:(NSDecimalNumber *)used ofPart:(SaleLine *)part by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (!used || used == [NSDecimalNumber notANumber] || [used compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
        return LBRefuse(error, @"Say how many were used: none, or more.");
    }
    NSDecimalNumber *was = part.lb_kept;
    NSComparisonResult change = [used compare:was];
    if (change == NSOrderedSame) return YES;
    if (change == NSOrderedDescending) {
        part.quantity = [part.quantity decimalNumberByAdding:[used decimalNumberBySubtracting:was]];
        return YES;
    }
    NSDecimalNumber *fewer = [was decimalNumberBySubtracting:used];
    NSDecimalNumber *unshipped = [part.quantity decimalNumberBySubtracting:LBShippedOf(part)];
    NSDecimalNumber *off = [fewer compare:unshipped] == NSOrderedDescending ? unshipped : fewer;
    NSDecimalNumber *back = [fewer decimalNumberBySubtracting:off];
    if (LBPositive(back)) {
        SaleOrder *sale = part.saleOrder;
        Location *from = sale.shipsFrom ?: [[sale.shipments anyObject] shippedFrom];
        if (![sale lb_returnLines:@{ part.id: back } at:from on:now reason:@"Not used" note:nil by:user at:now error:error]) return NO;
    }
    part.quantity = [part.quantity decimalNumberBySubtracting:off];
    if (!LBPositive(part.quantity)) return [part lb_delete:error];
    return YES;
}

- (BOOL)lb_shipParts:(NSError **)error {
    SaleOrder *sale = self.lb_partsSale;
    if (!sale || [sale.orderState isEqualToString:LBOrderCancelled]) return YES;
    for (SaleLine *line in sale.saleLines) {
        if (line.isDeleted) continue;
        NSDecimalNumber *shipped = LBShippedOf(line);
        if ([shipped compare:line.quantity ?: [NSDecimalNumber zero]] == NSOrderedDescending) {
            return LBRefuse(error, [NSString stringWithFormat:@"%@ of %@ have been shipped for it: say how many were used instead.",
                                                              LBQuantityText(shipped), line.stockItem.itemName]);
        }
    }
    if ([sale.orderState isEqualToString:LBOrderDraft] && ![sale lb_confirm:error]) return NO;
    NSMutableDictionary *left = [NSMutableDictionary dictionary];
    for (SaleLine *line in sale.saleLines) {
        if (line.isDeleted || line.stockItem.isAPhantomKit) continue;
        NSDecimalNumber *more = [line.quantity decimalNumberBySubtracting:LBShippedOf(line)];
        if (LBPositive(more)) left[line.id] = more;
    }
    if (!left.count) return YES;
    if (!sale.shipsFrom) return LBRefuse(error, @"Say where its parts come from.");
    NSDate *moment = [self valueForKey:@"timestamp"];
    return [sale lb_shipLines:left from:sale.shipsFrom on:LBEventDay(self) by:self.enteredBy at:moment error:error] != nil;
}

@end

@implementation StockCount (LBStock)

- (BOOL)lb_postFound:(NSArray<LBCounted *> *)found at:(NSDate *)now error:(NSError **)error {
    Warehouse *warehouse = self.warehouse;
    Location *location = self.countedLocation;
    /* What was found, by item and location; what is held there besides,
       found none. */
    NSMutableDictionary *counted = [NSMutableDictionary dictionary];
    for (LBCounted *each in found) {
        BOOL covered = each.location.warehouse == warehouse && (!location || LBWithin(each.location, location));
        if (!covered) return LBRefuse(error, [NSString stringWithFormat:@"%@ is not where this count counts.", each.location.locationName]);
        if (!each.quantity || [each.quantity compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
            return LBRefuse(error, @"Say how many were found: none, or more.");
        }
        counted[@[ each.item.objectID, each.location.objectID ]] = each;
    }
    for (Location *place in warehouse.locations) {
        if (location && !LBWithin(place, location)) continue;
        for (Holding *holding in place.holdings) {
            NSArray *key = @[ holding.stockItem.objectID, place.objectID ];
            if (!counted[key]) counted[key] = [LBCounted countedItem:holding.stockItem at:place quantity:[NSDecimalNumber zero]];
        }
    }
    NSManagedObjectContext *context = self.managedObjectContext;
    for (LBCounted *each in [counted.allValues sortedArrayUsingFunction:LBByItemAndLocation context:NULL]) {
        NSDecimalNumber *difference = [each.quantity decimalNumberBySubtracting:[each.location lb_heldOf:each.item]];
        NSComparisonResult sign = [difference compare:[NSDecimalNumber zero]];
        if (sign == NSOrderedSame) continue;
        BOOL out = sign == NSOrderedAscending;
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ for %@ at %@", LBText(self.id), LBText(each.item.id),
                                                              LBText(each.location.id)]);
        Move *move = LBMove(context, uuid, each.item, out ? [[NSDecimalNumber zero] decimalNumberBySubtracting:difference] : difference,
                            out ? each.location : nil, out ? nil : each.location, self.counter, now);
        move.adjustmentReason = @"Count";
        move.stockCount = self;
    }
    if (!location) warehouse.lastInventory = self.countedOn;
    return YES;
}

- (BOOL)lb_post:(NSError **)error {
    NSMutableArray *found = [NSMutableArray array];
    for (CountLine *line in [self.countLines.allObjects sortedArrayUsingFunction:LBByID context:NULL]) {
        if (line.isDeleted) continue;
        if (!line.stockItem || !line.location || !line.found) return LBRefuse(error, @"Each line of a count says what was found of an item where.");
        [found addObject:[LBCounted countedItem:line.stockItem at:line.location quantity:line.found]];
    }
    return [self lb_postFound:found at:[NSDate date] error:error];
}

@end

/* Whether the object is in the store: saved, not only in a context (a
   window's, the main one's). */
static BOOL LBStored(NSManagedObject *object) {
    NSPersistentStoreCoordinator *coordinator = object.managedObjectContext.persistentStoreCoordinator;
    if (!coordinator || object.objectID.isTemporaryID) return NO;
    NSManagedObjectContext *store = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    store.persistentStoreCoordinator = coordinator;
    __block BOOL there = NO;
    [store performBlockAndWait:^{
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:object.entity.name];
        request.predicate = [NSPredicate predicateWithFormat:@"self == %@", object.objectID];
        there = [store countForFetchRequest:request error:NULL] > 0;
    }];
    return there;
}

/* Whether any of them is not being deleted. */
static BOOL LBLive(NSSet<NSManagedObject *> *objects) {
    for (NSManagedObject *object in objects) {
        if (!object.isDeleted) return YES;
    }
    return NO;
}

@implementation NSManagedObjectContext (LBParts)

- (BOOL)lb_shipPartsOfChangedEvents:(NSError **)error {
    NSMutableSet *objects = [NSMutableSet setWithSet:self.insertedObjects];
    [objects unionSet:self.updatedObjects];
    NSMutableSet<Event *> *events = [NSMutableSet set];
    for (NSManagedObject *object in objects) {
        SaleOrder *sale = nil;
        if ([object isKindOfClass:[Event class]]) sale = ((Event *)object).lb_partsSale;
        else if ([object isKindOfClass:[SaleOrder class]]) sale = (SaleOrder *)object;
        else if ([object isKindOfClass:[SaleLine class]]) sale = ((SaleLine *)object).saleOrder;
        Event *event = sale.serviceAsPartsSale ?: (Event *)sale.tyreChangeAsPartsSale;
        if (event && !event.isDeleted && !sale.isDeleted) [events addObject:event];
    }
    for (Event *event in [events.allObjects sortedArrayUsingFunction:LBByID context:NULL]) {
        if (![event lb_shipParts:error]) return NO;
    }
    return YES;
}

- (BOOL)lb_confirmChangedOrders:(NSError **)error {
    NSMutableArray *confirmed = [NSMutableArray array];
    for (NSManagedObject *object in self.updatedObjects) {
        if (![object isKindOfClass:[SaleOrder class]] && ![object isKindOfClass:[PurchaseOrder class]]) continue;
        NSString *was = [object committedValuesForKeys:@[ @"orderState" ]][@"orderState"];
        if ([was isEqual:LBOrderDraft] && [[object valueForKey:@"orderState"] isEqual:LBOrderConfirmed]) [confirmed addObject:object];
    }
    for (NSManagedObject *order in [confirmed sortedArrayUsingFunction:LBByID context:NULL]) {
        /* Its Confirm, from the draft it was. */
        [order setValue:LBOrderDraft forKey:@"orderState"];
        BOOL done = [order isKindOfClass:[SaleOrder class]] ? [(SaleOrder *)order lb_confirm:error] : [(PurchaseOrder *)order lb_confirm:error];
        if (!done) return NO;
    }
    return YES;
}

- (BOOL)lb_postChangedCounts:(NSError **)error {
    NSMutableArray *posted = [NSMutableArray array];
    for (NSManagedObject *object in self.updatedObjects) {
        if (![object isKindOfClass:[StockCount class]]) continue;
        id was = [object committedValuesForKeys:@[ @"countState" ]][@"countState"];
        if (was == [NSNull null]) was = nil;
        NSString *now = ((StockCount *)object).countState;
        if (was == now || [was isEqual:now]) continue;
        /* Reviewed (posted or rejected), or taken before counts were
           reviewed (stored with no state, posted as it was taken): no more
           to change. One not stored yet is new, whatever this context
           thought of it before. */
        if (![was isEqual:@"Counted"] && (was || LBStored(object))) {
            return LBRefuse(error, [NSString stringWithFormat:@"A count reviewed stays as it was: count again (count %d was %@, now %@).",
                                                              ((StockCount *)object).runningNumber, was ?: @"taken before reviews", now ?: @"none"]);
        }
        if ([was isEqual:@"Counted"] && [now isEqual:@"Posted"]) [posted addObject:object];
    }
    for (StockCount *count in [posted sortedArrayUsingFunction:LBByID context:NULL]) {
        /* Posted where it was posted (a device's, its adjustments come with
           it). */
        if (LBLive(count.moves)) continue;
        if (![count lb_post:error]) return NO;
    }
    return YES;
}

- (BOOL)lb_moveChangedTransfers:(NSError **)error {
    NSMutableArray *moved = [NSMutableArray array];
    for (NSManagedObject *object in self.updatedObjects) {
        if (![object isKindOfClass:[StockTransfer class]]) continue;
        id was = [object committedValuesForKeys:@[ @"transferState" ]][@"transferState"];
        if (was == [NSNull null]) was = nil;
        NSString *now = ((StockTransfer *)object).transferState;
        if (was == now || [was isEqual:now]) continue;
        /* One not stored yet is new, whatever this context thought of it
           before (a window's, its save into the main one not yet kept):
           asked for, or moved at once. */
        if (!was && !LBStored(object)) {
            if ([now isEqual:@"Moved"]) [moved addObject:object];
            continue;
        }
        if (![was isEqual:@"Requested"]) {
            return LBRefuse(error, [NSString stringWithFormat:@"A transfer moved or cancelled stays as it was: ask for another (it was %@, now %@).",
                                                              was ?: @"stored with no state", now ?: @"none"]);
        }
        if ([now isEqual:@"Moved"]) [moved addObject:object];
    }
    for (StockTransfer *transfer in [moved sortedArrayUsingFunction:LBByID context:NULL]) {
        /* Moved where it was moved (a device's, its move come with it). */
        if (LBLive(transfer.moves)) continue;
        /* As Transfer moves it: refused where its place holds less. */
        Move *move = [transfer.stockItem lb_transfer:transfer.transferQuantity from:transfer.transferFrom to:transfer.transferTo
                                                  by:transfer.movedBy ?: transfer.askedBy at:transfer.movedAt ?: [NSDate date] error:error];
        if (!move) return NO;
        move.stockTransfer = transfer;
        move.id = LBNamedUUID([NSString stringWithFormat:@"%@ moved", LBText(transfer.id)]);
    }
    return YES;
}

- (BOOL)lb_returnChangedReturns:(NSError **)error {
    NSMutableArray *returned = [NSMutableArray array];
    for (NSManagedObject *object in self.updatedObjects) {
        if (![object isKindOfClass:[CustomerReturn class]] && ![object isKindOfClass:[SupplierReturn class]]) continue;
        id was = [object committedValuesForKeys:@[ @"returnState" ]][@"returnState"];
        if (was == [NSNull null]) was = nil;
        NSString *now = [object valueForKey:@"returnState"];
        if (was == now || [was isEqual:now]) continue;
        /* One not stored yet is new (as a transfer is, above). */
        if (!was && !LBStored(object)) {
            if ([now isEqual:@"Returned"]) [returned addObject:object];
            continue;
        }
        if (![was isEqual:@"Requested"]) {
            return LBRefuse(error, [NSString stringWithFormat:@"A return returned or cancelled stays as it was: ask for another (it was %@, now %@).",
                                                              was ?: @"stored with no state", now ?: @"none"]);
        }
        if ([now isEqual:@"Returned"]) [returned addObject:object];
    }
    for (NSManagedObject *back in [returned sortedArrayUsingFunction:LBByID context:NULL]) {
        /* Returned where it was (a device's, its moves come with it). */
        if (LBLive([back valueForKey:@"moves"])) continue;
        BOOL done = [back isKindOfClass:[CustomerReturn class]] ? [(CustomerReturn *)back lb_receiveAsked:error]
                                                                : [(SupplierReturn *)back lb_sendAsked:error];
        if (!done) return NO;
    }
    return YES;
}

- (BOOL)lb_completeShippedMoves:(NSError **)error {
    (void)error;
    for (NSManagedObject *object in self.insertedObjects) {
        if (![object isKindOfClass:[Move class]]) continue;
        Move *move = (Move *)object;
        Shipment *shipment = move.shipment;
        if (!shipment) continue;
        if (!move.stockItem) move.stockItem = move.saleLine.stockItem;
        if (!move.source) move.source = shipment.shippedFrom;
        if (!move.user) move.user = shipment.shippedBy;
        if (!move.moment) move.moment = shipment.shipmentRecorded;
        if (!shipment.shippedTo) shipment.shippedTo = shipment.saleOrder.shipTo;
    }
    return YES;
}

- (BOOL)lb_holdMovedItems:(NSError **)error {
    (void)error;
    NSMutableArray<Move *> *made = [NSMutableArray array];
    for (NSManagedObject *object in self.insertedObjects) {
        if ([object isKindOfClass:[Move class]]) [made addObject:(Move *)object];
    }
    for (Move *move in [made sortedArrayUsingFunction:LBByID context:NULL]) {
        /* As the model works them out as it saves: a receipt's move is of
           its line's item, to where the receipt came in. */
        StockItem *item = move.stockItem ?: move.purchaseLine.stockItem;
        Location *to = move.destination ?: move.receipt.receivedAt;
        if (!item) continue;
        if (move.source) [move.source lb_holdingOf:item];
        if (to) [to lb_holdingOf:item];
    }
    return YES;
}

@end

/* The owner's unit of distance: theirs, else km. */
static DistanceUnit *LBDistanceUnitOf(User *owner) {
    if (owner.distanceUnit || !owner.managedObjectContext) return owner.distanceUnit;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([DistanceUnit class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"code == %@", @"km"];
    return [[owner.managedObjectContext executeFetchRequest:fetch error:NULL] firstObject];
}

@implementation Asset (LBStock)

+ (NSSet *)keyPathsForValuesAffectingLb_make {
    return [NSSet setWithObject:@"stockUnit.stockItem.manufacturer"];
}

+ (NSSet *)keyPathsForValuesAffectingLb_model {
    return [NSSet setWithObject:@"stockUnit.stockItem.itemName"];
}

+ (NSSet *)keyPathsForValuesAffectingLb_serial {
    return [NSSet setWithObject:@"stockUnit.serialNumber"];
}

- (NSString *)lb_make {
    return self.stockUnit.stockItem.manufacturer;
}

- (void)setLb_make:(NSString *)make {
    self.stockUnit.stockItem.manufacturer = make.length ? make : nil;
}

- (NSString *)lb_model {
    return self.stockUnit.stockItem.itemName;
}

- (void)setLb_model:(NSString *)model {
    if (model.length) self.stockUnit.stockItem.itemName = model;
}

- (NSString *)lb_serial {
    return self.stockUnit.serialNumber;
}

+ (NSSet *)keyPathsForValuesAffectingLb_hasNoMeter {
    return [NSSet setWithObject:@"hasNoMeter"];
}

- (BOOL)lb_hasNoMeter {
    return self.hasNoMeter;
}

- (void)setLb_hasNoMeter:(BOOL)none {
    self.hasNoMeter = none;
    self.meterUnit = none ? nil : self.meterUnit ?: LBDistanceUnitOf(self.owner);
}

- (void)setLb_serial:(NSString *)serial {
    self.stockUnit.serialNumber = serial.length ? serial : nil;
}

+ (NSSet *)keyPathsForValuesAffectingLb_components {
    return [NSSet setWithObject:@"components"];
}

- (NSString *)lb_components {
    NSMutableArray *names = [NSMutableArray array];
    for (Asset *component in self.components) {
        if (!component.isDeleted && component.vehicleName.length) [names addObject:component.vehicleName];
    }
    if (!names.count) return nil;
    return [[names sortedArrayUsingSelector:@selector(localizedStandardCompare:)] componentsJoinedByString:@", "];
}

@end

/* The catalog an owner's assets are products of: their first, by name;
   "My assets" made where they have none. */
static Catalog *LBAssetsCatalog(User *owner) {
    NSArray *catalogs = [[owner.ownedCatalogs.allObjects filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isDeleted == NO"]]
        sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"catalogName" ascending:YES] ]];
    return catalogs.firstObject ?: [Catalog lb_newCatalogNamed:@"My assets" owner:owner inContext:owner.managedObjectContext];
}

/* Its first location, by warehouse and then location name. */
static Location *LBFirstLocation(Catalog *catalog) {
    NSArray *byName = @[ [NSSortDescriptor sortDescriptorWithKey:@"warehouse.warehouseName" ascending:YES],
                         [NSSortDescriptor sortDescriptorWithKey:@"locationName" ascending:YES] ];
    NSMutableArray *locations = [NSMutableArray array];
    for (Warehouse *warehouse in catalog.warehouses) {
        for (Location *location in warehouse.locations) if (!location.isDeleted) [locations addObject:location];
    }
    return [locations sortedArrayUsingDescriptors:byName].firstObject;
}

static StockItem *LBNewProduct(Catalog *catalog, NSString *make, NSString *model) {
    StockItem *item = LBNew([StockItem class], catalog.managedObjectContext, nil);
    item.catalog = catalog;
    item.itemName = model;
    item.manufacturer = make.length ? make : nil;
    item.created = [NSDate date];
    item.sku = [catalog lb_nextSKU];
    return item;
}

static Asset *LBMakeAssetOf(Class cls, Asset *existing, User *owner, Catalog *catalog, StockItem *item, NSString *serial, NSDate *day,
                            NSDecimalNumber *price, NSString *currency, NSString *seller, NSError **error);

Asset *LBMakeAsset(Class cls, User *owner, NSString *make, NSString *model, NSString *serial, NSDate *day,
                   NSDecimalNumber *price, NSString *currency, NSString *seller, NSError **error) {
    Catalog *catalog = LBAssetsCatalog(owner);
    StockItem *item = nil;
    for (StockItem *each in catalog.stockItems) {
        if (!each.isDeleted && [each.itemName isEqualToString:model] && (each.manufacturer == make || [each.manufacturer isEqualToString:make])) item = each;
    }
    return LBMakeAssetOf(cls, nil, owner, catalog, item ?: LBNewProduct(catalog, make, model), serial, day, price, currency, seller, error);
}

Asset *LBMakeNewAsset(Class cls, User *owner, NSString *name, NSDate *day, NSError **error) {
    Catalog *catalog = LBAssetsCatalog(owner);
    return LBMakeAssetOf(cls, nil, owner, catalog, LBNewProduct(catalog, nil, name), nil, day, nil, nil, nil, error);
}

static Asset *LBMakeAssetOf(Class cls, Asset *existing, User *owner, Catalog *catalog, StockItem *item, NSString *serial, NSDate *day,
                            NSDecimalNumber *price, NSString *currency, NSString *seller, NSError **error) {
    NSManagedObjectContext *context = owner.managedObjectContext;
    Location *location = LBFirstLocation(catalog);
    if (!location) {
        return LBRefuse(error, [NSString stringWithFormat:@"%@ has no location to bring the asset in at.", catalog.catalogName]), nil;
    }
    StockUnit *unit = LBNew([StockUnit class], context, nil);
    unit.stockItem = item;
    unit.serialNumber = serial.length ? serial : nil;
    /* Midday of the day: its day wherever the owner lives. */
    NSDate *moment = [LBDay(day) dateByAddingTimeInterval:12 * 3600];
    Move *in = nil;
    if (price) {
        NSString *name = seller.length ? seller : @"Previous owner";
        Supplier *supplier = nil;
        for (Supplier *each in catalog.suppliers) {
            if (!each.isDeleted && [each.contact.contactName isEqualToString:name]) supplier = each;
        }
        if (!supplier) {
            Contact *contact = LBNew([Contact class], context, nil);
            contact.catalog = catalog;
            contact.contactName = name;
            contact.lb_isSupplier = YES;
            supplier = contact.supplier;
        }
        PurchaseOrder *order = [catalog lb_newPurchaseOrderFrom:supplier on:day];
        PurchaseLine *line = LBNew([PurchaseLine class], context, nil);
        line.purchaseOrder = order;
        line.stockItem = item;
        line.quantity = [NSDecimalNumber one];
        line.lineUnitCostAmount = price;
        line.lineUnitCostCurrency = currency ?: catalog.currency;
        if (![order lb_confirm:error]) return nil;
        Receipt *receipt = [order lb_receiveLines:@{ line.id: [NSDecimalNumber one] } at:location on:day by:owner at:moment error:error];
        if (!receipt) return nil;
        in = receipt.moves.anyObject;
    } else {
        in = [item lb_adjust:[NSDecimalNumber one] at:location reason:@"Opening" note:nil by:owner at:moment error:error];
        if (!in) return nil;
    }
    in.stockUnit = unit;
    Asset *asset = existing ?: LBNew(cls, context, nil);
    asset.owner = owner;
    asset.stockUnit = unit;
    /* A vehicle's meter counts in its owner's unit of distance (km, else);
       another asset's is the caller's to say. */
    if (!existing && [asset isKindOfClass:[Vehicle class]]) asset.meterUnit = LBDistanceUnitOf(owner);
    Move *out = [item lb_adjust:[NSDecimalNumber decimalNumberWithString:@"-1"] at:location reason:@"Put in service" note:nil
                             by:owner at:[moment dateByAddingTimeInterval:60] error:error];
    if (!out) return nil;
    out.stockUnit = unit;
    out.asset = asset;
    return asset;
}

#pragma mark A store from before assets

/* The model a store from before assets is first migrated to: this one,
   nothing in it a must, and a vehicle's make, model and VIN kept where
   they were, for the migration to read. */
static NSManagedObjectModel *LBMigratingModel(NSManagedObjectModel *model) {
    NSManagedObjectModel *migrating = [model copy];
    for (NSEntityDescription *entity in migrating.entities) {
        for (NSPropertyDescription *property in entity.properties) property.optional = YES;
    }
    NSEntityDescription *vehicle = migrating.entitiesByName[@"Vehicle"];
    NSMutableArray *properties = [vehicle.properties mutableCopy];
    for (NSString *name in @[ @"make", @"carModel", @"vin" ]) {
        NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
        attribute.name = name;
        attribute.attributeType = NSStringAttributeType;
        attribute.optional = YES;
        [properties addObject:attribute];
    }
    vehicle.properties = properties;
    return migrating;
}

BOOL LBIsStoreBeforeAssets(NSString *type, NSURL *url, NSDictionary *options) {
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:type URL:url options:options error:NULL];
    NSDictionary *hashes = metadata[NSStoreModelVersionHashesKey];
    return hashes[@"Vehicle"] != nil && hashes[@"Asset"] == nil;
}

/* What the migrating model holds made what this one asks: each vehicle a
   unit of its product, bought as it was (or come in by an opening move),
   put in service; metered in its readings' unit; the units' dimensions
   (the reference data); the sale's kind 'Sale'. */
/* Each migrated asset's schedules made its product's plan (docs/CSDP.md, A
   unit that is an asset): a plan task for each work and intervals of the
   product's assets' schedules (a task or a checklist; one gone on in
   another is history, and an expense's stays the owner's own), once for
   the same; each schedule then follows its plan task. The same work at
   other intervals is a conflict: a plan task each, each asset following
   its own, the plan task's note saying so, for the owner's review. */
static NSString *LBIntervalsText(Schedule *schedule) {
    NSMutableArray *parts = [NSMutableArray array];
    if (schedule.intervalQuantity && schedule.intervalDistanceUnit) {
        [parts addObject:[NSString stringWithFormat:@"%@ %@", schedule.intervalQuantity, schedule.intervalDistanceUnit.code ?: @""]];
    }
    if (schedule.duration > 0) [parts addObject:[NSString stringWithFormat:@"%d months", schedule.duration]];
    return [parts componentsJoinedByString:@" or "];
}

static BOOL LBPlansOfMigrated(NSManagedObjectContext *context, NSError **error) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Schedule class])];
    NSArray *schedules = [[context executeFetchRequest:fetch error:error] ?: @[]
        sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"id.UUIDString" ascending:YES] ]];
    NSMutableDictionary<NSString *, PlanTask *> *plans = [NSMutableDictionary dictionary];   /* item, work, intervals */
    NSMutableDictionary<NSString *, NSMutableArray<PlanTask *> *> *works = [NSMutableDictionary dictionary];   /* item, work */
    for (Schedule *schedule in schedules) {
        if (schedule.planTask || (schedule.continuation && !schedule.continuation.isDeleted)) continue;
        if (!schedule.task.length && !schedule.checklist) continue;
        StockItem *item = schedule.vehicle.stockUnit.stockItem;
        if (!item) continue;
        NSString *work = [NSString stringWithFormat:@"%@|%@|%@", item.id.UUIDString, schedule.task ?: @"",
                                                    schedule.checklist.id.UUIDString ?: @""];
        NSString *key = [work stringByAppendingFormat:@"|%@", LBIntervalsText(schedule)];
        PlanTask *plan = plans[key];
        if (!plan) {
            plan = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([PlanTask class]) inManagedObjectContext:context];
            plan.id = LBNamedUUID([@"plan of " stringByAppendingString:schedule.id.UUIDString.lowercaseString]);
            plan.stockItem = item;
            plan.task = schedule.task.length ? schedule.task : nil;
            plan.checklist = plan.task ? nil : schedule.checklist;
            plan.intervalQuantity = schedule.intervalDistanceUnit ? schedule.intervalQuantity : nil;
            plan.intervalDistanceUnit = schedule.intervalQuantity ? schedule.intervalDistanceUnit : nil;
            if (schedule.duration > 0) plan.duration = schedule.duration;
            plans[key] = plan;
            if (!works[work]) works[work] = [NSMutableArray array];
            [works[work] addObject:plan];
        }
        schedule.planTask = plan;
    }
    /* Conflicts said: the same work of a product at other intervals. */
    for (NSString *work in [works.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray<PlanTask *> *same = works[work];
        if (same.count < 2) continue;
        for (PlanTask *plan in same) {
            NSMutableArray *others = [NSMutableArray array];
            for (PlanTask *other in same) {
                if (other == plan) continue;
                for (Schedule *schedule in other.schedules) {
                    [others addObject:[NSString stringWithFormat:@"%@ every %@", schedule.vehicle.vehicleName ?: @"another", LBIntervalsText(schedule)]];
                }
            }
            plan.note = [NSString stringWithFormat:@"From the logbook before plans: at other intervals for %@. Review the plan.",
                                                   [[others sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]];
        }
    }
    return YES;
}

static BOOL LBFillMigrated(NSManagedObjectContext *context, NSError **error) {
    NSError * __autoreleasing ignored = nil;
    if (!error) error = &ignored;
    if (![LogbookReferenceData seedContext:context error:error]) return NO;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Vehicle class])];
    /* In the order of their ids (as text: an NSUUID compares on no platform
       but Apple's). */
    NSArray *vehicles = [[context executeFetchRequest:fetch error:error] ?: @[]
        sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"id.UUIDString" ascending:YES] ]];
    for (Vehicle *vehicle in vehicles) {
        if (vehicle.stockUnit) continue;
        NSString *make = [vehicle valueForKey:@"make"], *model = [vehicle valueForKey:@"carModel"], *vin = [vehicle valueForKey:@"vin"];
        if (!model.length) model = vehicle.vehicleName.length ? vehicle.vehicleName : @"Vehicle";
        /* Kept since it was acquired, else since its first record. */
        NSDate *day = vehicle.purchaseDate;
        NSDate *first = nil;
        for (Record *record in vehicle.records) {
            NSDate *moment = [record isKindOfClass:[Event class]] ? ((Event *)record).timestamp : nil;
            if (moment && (!first || [moment compare:first] == NSOrderedAscending)) first = moment;
        }
        if (!day) day = LBDayIn(first ?: [NSDate date], vehicle.owner.timeZone);
        Catalog *catalog = LBAssetsCatalog(vehicle.owner);
        StockItem *item = nil;
        for (StockItem *each in catalog.stockItems) {
            if (!each.isDeleted && [each.itemName isEqualToString:model] && (each.manufacturer == make || [each.manufacturer isEqualToString:make])) item = each;
        }
        if (!LBMakeAssetOf([Vehicle class], vehicle, vehicle.owner, catalog, item ?: LBNewProduct(catalog, make, model), vin, day,
                           vehicle.purchasePriceAmount, vehicle.purchasePriceCurrency, nil, error))
            return NO;
        /* Its meter: the unit its readings were in, else its owner's. */
        if (!vehicle.hasNoMeter && !vehicle.meterUnit) {
            DistanceUnit *unit = vehicle.purchaseMileageDistanceUnit;
            NSDate *latest = nil;
            for (Record *record in vehicle.records) {
                if (![record isKindOfClass:[Event class]]) continue;
                Event *event = (Event *)record;
                if (event.mileageDistanceUnit && (!latest || [event.timestamp compare:latest] == NSOrderedDescending)) {
                    latest = event.timestamp;
                    unit = event.mileageDistanceUnit;
                }
            }
            vehicle.meterUnit = unit ?: LBDistanceUnitOf(vehicle.owner);
        }
        [vehicle setValue:nil forKey:@"make"];
        [vehicle setValue:nil forKey:@"carModel"];
        [vehicle setValue:nil forKey:@"vin"];
    }
    if (!LBPlansOfMigrated(context, error)) return NO;
    /* An asset's sale: of kind 'Sale', not 'Car sale'. */
    NSFetchRequest *sales = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Income class])];
    sales.predicate = [NSPredicate predicateWithFormat:@"incomeKind == %@", @"Car sale"];
    for (Income *income in [context executeFetchRequest:sales error:NULL] ?: @[]) income.incomeKind = @"Sale";
    return [context orm_prepareForSave:error] && [context save:error];
}

BOOL LBMigrateStoreBeforeAssets(NSString *type, NSURL *url, NSManagedObjectModel *model, NSDictionary *options, NSError **error) {
    if (!LBIsStoreBeforeAssets(type, url, options)) return YES;
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:LBMigratingModel(model)];
    NSMutableDictionary *migrating = [options mutableCopy] ?: [NSMutableDictionary dictionary];
    migrating[NSMigratePersistentStoresAutomaticallyOption] = @YES;
    migrating[NSInferMappingModelAutomaticallyOption] = @YES;
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:type configuration:nil URL:url options:migrating error:error];
    if (!store) return NO;
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    __block BOOL done = NO;
    __block NSError *failure = nil;
    [context performBlockAndWait:^{
        NSError *e = nil;
        done = LBFillMigrated(context, &e);
        failure = e;
    }];
    [coordinator removePersistentStore:store error:NULL];
    if (!done && error) {
        /* Each rule it broke said, not "several". */
        NSMutableArray *said = [NSMutableArray array];
        for (NSError *each in failure.userInfo[NSDetailedErrorsKey] ?: @[]) {
            [said addObject:each.localizedRecoverySuggestion ?: each.localizedDescription];
        }
        *error = said.count ? [NSError errorWithDomain:failure.domain code:failure.code
                                              userInfo:@{ NSLocalizedDescriptionKey: [said componentsJoinedByString:@"; "] }]
                            : failure;
    }
    return done;
}

@implementation PlanTask (LBStock)

+ (NSSet *)keyPathsForValuesAffectingLb_work {
    return [NSSet setWithObjects:@"task", @"checklist", @"checklist.checklistName", nil];
}

- (NSString *)lb_work {
    return self.task ?: self.checklist.checklistName;
}

- (void)setLb_work:(NSString *)work {
    NSString *named = [work stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!named.length) return;
    if (self.checklist && [named isEqualToString:self.checklist.checklistName]) return;
    self.task = named;
    self.checklist = nil;
}

+ (NSSet *)keyPathsForValuesAffectingLb_checklist {
    return [NSSet setWithObject:@"checklist"];
}

- (Checklist *)lb_checklist {
    return self.checklist;
}

- (void)setLb_checklist:(Checklist *)checklist {
    if (!checklist) {
        if (!self.task.length) self.task = self.checklist.checklistName ?: @"New Task";
        self.checklist = nil;
        return;
    }
    self.checklist = checklist;
    self.task = nil;
}

+ (NSSet *)keyPathsForValuesAffectingLb_months {
    return [NSSet setWithObject:@"duration"];
}

- (NSNumber *)lb_months {
    return self.duration > 0 ? @(self.duration) : nil;
}

- (void)setLb_months:(NSNumber *)months {
    if (months.intValue > 0) self.duration = months.intValue;
    else [self setValue:nil forKey:NSStringFromSelector(@selector(duration))];
}

@end
