#import "LBStockProcedures.h"

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

- (void)setLb_isCustomer:(BOOL)flag {
    if (flag == self.lb_isCustomer) return;
    if (flag) {
        Customer *customer = LBNew([Customer class], self.managedObjectContext, nil);
        customer.contact = self;
        customer.catalog = self.catalog;
    } else if (self.customer.saleOrders.count == 0) {
        [self.managedObjectContext deleteObject:self.customer];
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
    } else if (self.supplier.purchaseOrders.count == 0 && self.supplier.stockItems.count == 0) {
        [self.managedObjectContext deleteObject:self.supplier];
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

@implementation SaleLine (LBStock)

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
    /* What was found, by item and location; what is held there besides,
       found none. */
    NSMutableDictionary *counted = [NSMutableDictionary dictionary];
    for (LBCounted *each in found) {
        BOOL covered = each.location.warehouse == self && (!location || LBWithin(each.location, location));
        if (!covered) return LBRefuse(error, [NSString stringWithFormat:@"%@ is not where this count counts.", each.location.locationName]), nil;
        if (!each.quantity || [each.quantity compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
            return LBRefuse(error, @"Say how many were found: none, or more."), nil;
        }
        counted[@[ each.item.objectID, each.location.objectID ]] = each;
    }
    for (Location *place in self.locations) {
        if (location && !LBWithin(place, location)) continue;
        for (Holding *holding in place.holdings) {
            NSArray *key = @[ holding.stockItem.objectID, place.objectID ];
            if (!counted[key]) counted[key] = [LBCounted countedItem:holding.stockItem at:place quantity:[NSDecimalNumber zero]];
        }
    }
    NSManagedObjectContext *context = self.managedObjectContext;
    StockCount *count = LBNew([StockCount class], context, nil);
    count.warehouse = self;
    count.countedLocation = location;
    count.countedOn = LBDay(day);
    count.counter = user;
    count.runningNumber = LBNextOf(self.stockCounts);
    for (LBCounted *each in [counted.allValues sortedArrayUsingFunction:LBByItemAndLocation context:NULL]) {
        NSDecimalNumber *difference = [each.quantity decimalNumberBySubtracting:[each.location lb_heldOf:each.item]];
        NSComparisonResult sign = [difference compare:[NSDecimalNumber zero]];
        if (sign == NSOrderedSame) continue;
        BOOL out = sign == NSOrderedAscending;
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ for %@ at %@", LBText(count.id), LBText(each.item.id),
                                                              LBText(each.location.id)]);
        Move *move = LBMove(context, uuid, each.item, out ? [[NSDecimalNumber zero] decimalNumberBySubtracting:difference] : difference,
                            out ? each.location : nil, out ? nil : each.location, user, now);
        move.adjustmentReason = @"Count";
        move.stockCount = count;
    }
    if (!location) self.lastInventory = LBDay(day);
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
        if (!item.supplier || !item.unitCostAmount) {
            [left addObject:item];
            continue;
        }
        NSDecimalNumber *has = [LBOr(item.available, [NSDecimalNumber zero]) decimalNumberByAdding:LBOr(item.incoming, [NSDecimalNumber zero])];
        NSDecimalNumber *wanted = [LBOr(rule.reorderLevel, rule.reorderPoint) decimalNumberBySubtracting:has];
        if (!LBPositive(wanted)) continue;
        PurchaseOrder *order = orders[item.supplier.objectID];
        if (!order) {
            NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"reorder at %@ on %@ from %@", LBText(self.id), dayText,
                                                                  LBText(item.supplier.id)]);
            order = LBNamed([PurchaseOrder class], context, uuid);
            if (!order) {
                order = [self.catalog lb_newPurchaseOrderFrom:item.supplier on:day];
                order.id = uuid;
            }
            orders[item.supplier.objectID] = order;
            [made addObject:order];
        }
        NSUUID *uuid = LBNamedUUID([NSString stringWithFormat:@"%@ for %@", LBText(order.id), LBText(item.id)]);
        PurchaseLine *line = LBNamed([PurchaseLine class], context, uuid) ?: LBNew([PurchaseLine class], context, uuid);
        line.purchaseOrder = order;
        line.stockItem = item;
        line.quantity = wanted;
        line.lineUnitCostAmount = item.unitCostAmount;
        line.lineUnitCostCurrency = item.unitCostCurrency ?: self.catalog.currency;
    }
    if (skipped) *skipped = left;
    return made;
}

@end
