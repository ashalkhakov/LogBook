#import "LBStockActions.h"
#import "LBPermissions.h"
#import <ODataKit/ODataError.h>

/* Who carries out the procedure: the signed-in user, when they may; for
   an anonymous request, the catalog's owner. nil, the reply failed, when
   no one may. */
static User *LBStockActor(ODataReply *reply, Catalog *catalog, BOOL may, NSString *why) {
    NSString *email = LBEmailOf(reply.request);
    if (!email) {
        if (!catalog.catalogOwner) [reply failWithError:ODataServiceError(400, @"The catalog has no owner to act for")];
        return catalog.catalogOwner;
    }
    if (!may) {
        [reply failWithError:ODataServiceError(403, why)];
        return nil;
    }
    return LBUserNamed(reply.request.context, email, YES);
}

static User *LBOrderActor(ODataReply *reply, Catalog *catalog) {
    NSString *email = LBEmailOf(reply.request);
    return LBStockActor(reply, catalog, email && LBManagesIn(catalog, email), @"Only a catalog's owner or managers do that");
}

/* Whoever keeps the warehouses (each of them); the owner. */
static User *LBKeeperActor(ODataReply *reply, Catalog *catalog, NSArray<Warehouse *> *warehouses) {
    NSString *email = LBEmailOf(reply.request);
    BOOL may = email != nil;
    for (Warehouse *warehouse in warehouses) {
        may = may && warehouse.catalog == catalog && LBKeeps(warehouse, email);
    }
    return LBStockActor(reply, catalog, may, @"Only a warehouse's staff, or its catalog's owner, do that there");
}

/* A procedure's refusal, answered: 400. */
static void LBRefuse(ODataReply *reply, NSError *error) {
    [reply failWithError:ODataServiceError(400, error.localizedDescription ?: @"Refused")];
}

/* A quantity as JSON says one: a number, or a decimal string. */
static NSDecimalNumber *LBQuantity(id value) {
    if ([value isKindOfClass:[NSDecimalNumber class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [NSDecimalNumber decimalNumberWithDecimal:[value decimalValue]];
    if ([value isKindOfClass:[NSString class]]) {
        NSDecimalNumber *parsed = [NSDecimalNumber decimalNumberWithString:value locale:@{ NSLocaleDecimalSeparator: @"." }];
        return parsed == [NSDecimalNumber notANumber] ? nil : parsed;
    }
    return nil;
}

/* Lines as Ship and Receive take them: {"<line id>": quantity}. nil, the
   reply failed, for one not so. */
static NSDictionary<NSUUID *, NSDecimalNumber *> *LBLines(ODataReply *reply, NSDictionary *lines) {
    NSMutableDictionary *read = [NSMutableDictionary dictionary];
    for (id key in [lines isKindOfClass:[NSDictionary class]] ? lines : nil) {
        NSUUID *uuid = [key isKindOfClass:[NSString class]] ? [[NSUUID alloc] initWithUUIDString:key] : nil;
        NSDecimalNumber *quantity = LBQuantity(lines[key]);
        if (!uuid || !quantity) {
            [reply failWithError:ODataServiceError(400, @"Lines are {\"<line id>\": quantity, ...}")];
            return nil;
        }
        read[uuid] = quantity;
    }
    if (![lines isKindOfClass:[NSDictionary class]]) {
        [reply failWithError:ODataServiceError(400, @"Lines are {\"<line id>\": quantity, ...}")];
        return nil;
    }
    return read;
}

/* An object of the entity by its id; nil for none. */
static id LBByID(NSManagedObjectContext *context, Class cls, id text) {
    NSUUID *uuid = [text isKindOfClass:[NSString class]] ? [[NSUUID alloc] initWithUUIDString:text] : nil;
    if (!uuid) return nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"id == %@", uuid];
    return [[context executeFetchRequest:fetch error:NULL] firstObject];
}

static NSDate *LBToday(NSDate *day) {
    return day ?: [NSDate date];
}

@implementation SaleOrder (LBStockActions)

- (SaleOrder *)confirm:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_confirm:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (SaleOrder *)close:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_close:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (SaleOrder *)cancel:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_cancel:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (SaleOrder *)reopen:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_reopen:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (SaleOrder *)expandKits:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_expandKits:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (Shipment *)shipWithLines:(NSDictionary *)lines from:(Location *)from day:(NSDate *)day reply:(ODataReply *)reply {
    User *user = LBKeeperActor(reply, self.catalog, from ? @[ from.warehouse ] : @[]);
    NSDictionary *read = user ? LBLines(reply, lines) : nil;
    if (!read) return nil;
    NSError *error = nil;
    Shipment *shipment = [self lb_shipLines:read from:from on:LBToday(day) by:user at:[NSDate date] error:&error];
    if (!shipment) LBRefuse(reply, error);
    return shipment;
}

@end

@implementation PurchaseOrder (LBStockActions)

- (PurchaseOrder *)confirm:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_confirm:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (PurchaseOrder *)close:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_close:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (PurchaseOrder *)cancel:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_cancel:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (PurchaseOrder *)reopen:(ODataReply *)reply {
    NSError *error = nil;
    if (!LBOrderActor(reply, self.catalog)) return nil;
    if (![self lb_reopen:&error]) return LBRefuse(reply, error), nil;
    return self;
}

- (Receipt *)receiveWithLines:(NSDictionary *)lines at:(Location *)at day:(NSDate *)day reply:(ODataReply *)reply {
    User *user = LBKeeperActor(reply, self.catalog, at ? @[ at.warehouse ] : @[]);
    NSDictionary *read = user ? LBLines(reply, lines) : nil;
    if (!read) return nil;
    NSError *error = nil;
    Receipt *receipt = [self lb_receiveLines:read at:at on:LBToday(day) by:user at:[NSDate date] error:&error];
    if (!receipt) LBRefuse(reply, error);
    return receipt;
}

@end

@implementation StockItem (LBStockActions)

- (Move *)transferWithQuantity:(NSDecimalNumber *)quantity from:(Location *)from to:(Location *)to reply:(ODataReply *)reply {
    NSMutableArray *at = [NSMutableArray array];
    if (from.warehouse) [at addObject:from.warehouse];
    if (to.warehouse) [at addObject:to.warehouse];
    User *user = LBKeeperActor(reply, self.catalog, at);
    if (!user) return nil;
    NSError *error = nil;
    Move *move = [self lb_transfer:quantity from:from to:to by:user at:[NSDate date] error:&error];
    if (!move) LBRefuse(reply, error);
    return move;
}

- (Move *)adjustWithQuantity:(NSDecimalNumber *)quantity at:(Location *)at reason:(NSString *)reason note:(NSString *)note
                       reply:(ODataReply *)reply {
    User *user = LBKeeperActor(reply, self.catalog, at.warehouse ? @[ at.warehouse ] : @[]);
    if (!user) return nil;
    NSError *error = nil;
    Move *move = [self lb_adjust:quantity at:at reason:reason note:note by:user at:[NSDate date] error:&error];
    if (!move) LBRefuse(reply, error);
    return move;
}

+ (NSDictionary<NSString *, NSString *> *)ODataOperationTypes {
    return @{ @"assembleWithBatches:at:day:disassemble:reply:.disassemble": @"Edm.Boolean" };
}

- (Assembly *)assembleWithBatches:(NSDecimalNumber *)batches at:(Location *)at day:(NSDate *)day disassemble:(NSNumber *)disassemble
                            reply:(ODataReply *)reply {
    User *user = LBKeeperActor(reply, self.catalog, at.warehouse ? @[ at.warehouse ] : @[]);
    if (!user) return nil;
    NSError *error = nil;
    Assembly *assembly = [self lb_assemble:batches at:at on:LBToday(day) disassemble:disassemble.boolValue by:user at:[NSDate date]
                                     error:&error];
    if (!assembly) LBRefuse(reply, error);
    return assembly;
}

@end

@implementation Warehouse (LBStockActions)

- (StockCount *)countWithLocation:(Location *)location found:(NSArray *)found day:(NSDate *)day reply:(ODataReply *)reply {
    User *user = LBKeeperActor(reply, self.catalog, @[ self ]);
    if (!user) return nil;
    NSMutableArray *counted = [NSMutableArray array];
    for (id each in [found isKindOfClass:[NSArray class]] ? found : @[ [NSNull null] ]) {
        NSDictionary *said = [each isKindOfClass:[NSDictionary class]] ? each : nil;
        StockItem *item = LBByID(self.managedObjectContext, [StockItem class], said[@"Item"]);
        Location *place = LBByID(self.managedObjectContext, [Location class], said[@"Location"]);
        NSDecimalNumber *quantity = LBQuantity(said[@"Quantity"]);
        if (!item || !place || !quantity || item.catalog != self.catalog) {
            [reply failWithError:ODataServiceError(400, @"Found is [{\"Item\": <id>, \"Location\": <id>, \"Quantity\": n}, ...], "
                                                         @"of this catalog's items")];
            return nil;
        }
        [counted addObject:[LBCounted countedItem:item at:place quantity:quantity]];
    }
    NSError *error = nil;
    StockCount *count = [self lb_countLocation:location found:counted on:LBToday(day) by:user at:[NSDate date] error:&error];
    if (!count) LBRefuse(reply, error);
    return count;
}

+ (NSDictionary<NSString *, NSString *> *)ODataOperationTypes {
    return @{ @"reorderWithDay:reply:": @"Collection(Default.PurchaseOrder)",
              @"countWithLocation:found:day:reply:.found": @"Edm.Untyped" };
}

- (NSArray<PurchaseOrder *> *)reorderWithDay:(NSDate *)day reply:(ODataReply *)reply {
    NSString *email = LBEmailOf(reply.request);
    if (!LBStockActor(reply, self.catalog, email && LBManages(self, email), @"Only a warehouse's managers, or its catalog's owner, reorder")) {
        return nil;
    }
    NSError *error = nil;
    return [self lb_reorderOn:LBToday(day) skipped:NULL error:&error];
}

@end
