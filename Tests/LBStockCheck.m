// The stock model's derivations and rules checked over a store of the
// model's own, each change saved as the server saves one (the generated
// orm_prepareForSave:, then save:). Each check a line, "ok" or "FAIL"; 1
// when one failed.
//
//   lb-stock-check build/Logbook.momd build/Logbook.ormplans
//
// - kits: how many each can make, whole batches of its scarcest component
//   times its yield; what it contains; one containing itself refused;
// - a phantom kit is never moved;
// - a phantom kit's sale line expanded into its components' lines, shipped
//   in part and then in full: the kits shipped worked back from them
//   (contracted), what is outstanding, and the order partly, then fully,
//   shipped.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "LogbookValidation.h"
#import "User+CoreDataClass.h"
#import "Catalog+CoreDataClass.h"
#import "Customer+CoreDataClass.h"
#import "Warehouse+CoreDataClass.h"
#import "Location+CoreDataClass.h"
#import "StockItem+CoreDataClass.h"
#import "KitLine+CoreDataClass.h"
#import "Holding+CoreDataClass.h"
#import "SaleOrder+CoreDataClass.h"
#import "SaleLine+CoreDataClass.h"
#import "Shipment+CoreDataClass.h"
#import "Move+CoreDataClass.h"

static NSUInteger LBFailures;
static NSManagedObjectModel *LBModel;

static void LBCheck(NSString *what, BOOL ok, id detail) {
    printf("%s %s%s\n", ok ? "ok  " : "FAIL", what.UTF8String,
           ok || !detail ? "" : [[NSString stringWithFormat:@": %@", detail] UTF8String]);
    fflush(stdout);
    if (!ok) LBFailures++;
}

#pragma mark A store

/* A context over a new SQLite store, its reference data seeded. */
static NSManagedObjectContext *LBNewStore(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"lb-stock-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:LBModel];
    NSError *error = nil;
    if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[NSURL fileURLWithPath:path] options:nil
                                           error:&error]) {
        printf("FAIL the store at %s: %s\n", path.UTF8String, error.localizedDescription.UTF8String);
        exit(1);
    }
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    if (![LogbookReferenceData seedContext:context error:&error] || ![context save:&error]) {
        printf("FAIL seeded: %s\n", error.localizedDescription.UTF8String);
        exit(1);
    }
    return context;
}

/* A save's failure, each violation said. */
static NSString *LBSaid(NSError *error) {
    NSArray *each = error.userInfo[NSDetailedErrorsKey];
    if (!each.count) return error.localizedDescription;
    NSMutableArray *said = [NSMutableArray array];
    for (NSError *e in each) [said addObject:e.localizedDescription];
    return [said componentsJoinedByString:@"; "];
}

/* Saved as the server saves; refused, rolled back, and why in *why. */
static BOOL LBSave(NSManagedObjectContext *context, NSString **why) {
    NSError *error = nil;
    BOOL saved = [context orm_prepareForSave:&error] && [context save:&error];
    if (!saved) {
        if (why) *why = LBSaid(error);
        [context rollback];
    }
    return saved;
}

static id LBInsert(Class cls, NSManagedObjectContext *context) {
    id object = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass(cls) inManagedObjectContext:context];
    if ([object respondsToSelector:@selector(setId:)] && ![object valueForKey:@"id"]) [object setValue:[NSUUID UUID] forKey:@"id"];
    return object;
}

static NSDecimalNumber *LBN(NSString *text) {
    return [NSDecimalNumber decimalNumberWithString:text];
}

static BOOL LBSame(NSDecimalNumber *number, NSString *text) {
    return text ? number && [number compare:LBN(text)] == NSOrderedSame : number == nil;
}

#pragma mark The stock

typedef struct {
    __unsafe_unretained NSManagedObjectContext *context;
    __unsafe_unretained User *anna;
    __unsafe_unretained Catalog *catalog;
    __unsafe_unretained Location *shelf;
} LBStock;

static StockItem *LBItem(LBStock *stock, NSString *name) {
    StockItem *item = LBInsert([StockItem class], stock->context);
    item.itemName = name;
    item.catalog = stock->catalog;
    item.created = [NSDate date];
    return item;
}

static KitLine *LBTakes(LBStock *stock, StockItem *kit, NSString *perBatch, StockItem *component) {
    KitLine *line = LBInsert([KitLine class], stock->context);
    line.kit = kit;
    line.component = component;
    line.perBatch = LBN(perBatch);
    return line;
}

static void LBKeep(LBStock *stock, StockItem *item, NSString *quantity) {
    Holding *holding = LBInsert([Holding class], stock->context);
    holding.stockItem = item;
    holding.location = stock->shelf;
    holding.quantity = LBN(quantity);
}

static Move *LBShip(LBStock *stock, Shipment *shipment, SaleLine *line, NSString *quantity) {
    Move *move = LBInsert([Move class], stock->context);
    move.stockItem = line.stockItem;
    move.moved = LBN(quantity);
    move.source = stock->shelf;
    move.moment = [NSDate date];
    move.user = stock->anna;
    move.shipment = shipment;
    move.saleLine = line;
    return move;
}

static void LBKits(void) {
    NSManagedObjectContext *context = LBNewStore();
    LBStock stock = { context, nil, nil, nil };
    User *anna = LBInsert([User class], context);
    anna.email = @"anna@example.org";
    stock.anna = anna;
    Catalog *catalog = LBInsert([Catalog class], context);
    catalog.catalogName = @"Workshop";
    catalog.catalogOwner = anna;
    stock.catalog = catalog;
    Warehouse *warehouse = LBInsert([Warehouse class], context);
    warehouse.warehouseName = @"Garage";
    warehouse.catalog = catalog;
    Location *shelf = LBInsert([Location class], context);
    shelf.locationName = @"Shelf A";
    shelf.warehouse = warehouse;
    stock.shelf = shelf;

    /* A mount: 4 bolts and a bracket make one. Pieces: a roll yields 20.
       A bundle, a phantom: 2 bolts and a bracket. */
    StockItem *bolt = LBItem(&stock, @"Bolt");
    StockItem *bracket = LBItem(&stock, @"Bracket");
    StockItem *roll = LBItem(&stock, @"Roll");
    StockItem *mount = LBItem(&stock, @"Mount");
    StockItem *piece = LBItem(&stock, @"Piece");
    StockItem *bundle = LBItem(&stock, @"Bundle");
    LBTakes(&stock, mount, @"4", bolt);
    LBTakes(&stock, mount, @"1", bracket);
    LBTakes(&stock, piece, @"1", roll);
    piece.yield = LBN(@"20");
    LBTakes(&stock, bundle, @"2", bolt);
    LBTakes(&stock, bundle, @"1", bracket);
    bundle.isAPhantomKit = YES;
    LBKeep(&stock, bolt, @"10");
    LBKeep(&stock, bracket, @"3");
    LBKeep(&stock, roll, @"2");
    NSString *why = nil;
    LBCheck(@"kits saved", LBSave(context, &why), why);
    LBCheck(@"a mount: 2, the bolts' whole batches (10 / 4), fewer than the brackets' 3", LBSame(mount.makeable, @"2"),
            mount.makeable);
    LBCheck(@"pieces: 2 rolls, 20 each", LBSame(piece.makeable, @"40"), piece.makeable);
    LBCheck(@"a bundle: 3, as many as brackets", LBSame(bundle.makeable, @"3"), bundle.makeable);
    LBCheck(@"a bolt makes nothing: no kit", bolt.makeable == nil, bolt.makeable);
    LBCheck(@"a mount contains bolts and brackets", [mount.containeds isEqualToSet:[NSSet setWithObjects:bolt, bracket, nil]],
            [mount.containeds valueForKey:@"itemName"]);

    /* None of its components gone: a kit makes none. */
    for (Holding *holding in bracket.holdings) holding.quantity = LBN(@"0");
    LBCheck(@"brackets used up: saved", LBSave(context, &why), why);
    LBCheck(@"then a mount makes none", LBSame(mount.makeable, @"0"), mount.makeable);
    for (Holding *holding in bracket.holdings) holding.quantity = LBN(@"3");
    LBCheck(@"brackets back: saved", LBSave(context, &why), why);

    /* A kit inside itself, through another. */
    LBTakes(&stock, bolt, @"1", mount);
    why = nil;
    LBCheck(@"a bolt made of mounts, which are made of bolts, is refused", !LBSave(context, &why), nil);
    printf("     (%s)\n", why.UTF8String);

    /* A phantom kit is never moved. */
    Move *moved = LBInsert([Move class], context);
    moved.stockItem = bundle;
    moved.moved = LBN(@"1");
    moved.destination = shelf;
    moved.moment = [NSDate date];
    moved.user = anna;
    moved.adjustmentReason = @"Found";
    why = nil;
    LBCheck(@"a bundle moved is refused: a phantom is never kept", !LBSave(context, &why), nil);
    printf("     (%s)\n", why.UTF8String);

    /* Three bundles sold: the line expanded into 3 brackets and 6 bolts. */
    Customer *bob = LBInsert([Customer class], context);
    bob.customerName = @"Bob";
    bob.catalog = catalog;
    SaleOrder *order = LBInsert([SaleOrder class], context);
    order.catalog = catalog;
    order.customer = bob;
    order.saleOrdered = [NSDate date];
    order.orderState = @"Confirmed";
    SaleLine *kitLine = LBInsert([SaleLine class], context);
    kitLine.saleOrder = order;
    kitLine.stockItem = bundle;
    kitLine.quantity = LBN(@"3");
    kitLine.linePriceAmount = LBN(@"12.50");
    kitLine.linePriceCurrency = @"USD";
    SaleLine *brackets = LBInsert([SaleLine class], context);
    brackets.saleOrder = order;
    brackets.stockItem = bracket;
    brackets.quantity = LBN(@"3");
    brackets.expandedFrom = kitLine;
    SaleLine *bolts = LBInsert([SaleLine class], context);
    bolts.saleOrder = order;
    bolts.stockItem = bolt;
    bolts.quantity = LBN(@"6");
    bolts.expandedFrom = kitLine;
    LBCheck(@"the order, its bundle line expanded, saved", LBSave(context, &why), why);
    LBCheck(@"nothing shipped: the bundle line outstanding, 3", LBSame(kitLine.kitsShipped, @"0") || kitLine.kitsShipped == nil,
            kitLine.kitsShipped);
    LBCheck(@"its outstanding 3", LBSame([kitLine valueForKey:@"backorderedQuantity"], @"3"),
            [kitLine valueForKey:@"backorderedQuantity"]);
    LBCheck(@"the order neither partly nor fully shipped", !order.isPartlyShipped && !order.isFullyShipped, nil);

    /* Two brackets and all six bolts go out: two bundles' worth. */
    Shipment *first = LBInsert([Shipment class], context);
    first.saleOrder = order;
    first.shipped = [NSDate date];
    first.shippedFrom = shelf;
    LBShip(&stock, first, brackets, @"2");
    LBShip(&stock, first, bolts, @"6");
    LBCheck(@"the first shipment saved", LBSave(context, &why), why);
    LBCheck(@"brackets shipped 2, bolts 6", LBSame(brackets.shippedQuantity, @"2") && LBSame(bolts.shippedQuantity, @"6"),
            @[ brackets.shippedQuantity ?: @"none", bolts.shippedQuantity ?: @"none" ]);
    LBCheck(@"contracted: 2 bundles shipped, the brackets' whole batches", LBSame(kitLine.kitsShipped, @"2"), kitLine.kitsShipped);
    LBCheck(@"the bundle line: 1 outstanding", LBSame([kitLine valueForKey:@"backorderedQuantity"], @"1"),
            [kitLine valueForKey:@"backorderedQuantity"]);
    LBCheck(@"the bolts' line: none outstanding", [bolts valueForKey:@"backorderedQuantity"] == nil,
            [bolts valueForKey:@"backorderedQuantity"]);
    LBCheck(@"the order partly shipped", order.isPartlyShipped && !order.isFullyShipped, nil);

    /* The last bracket. */
    Shipment *second = LBInsert([Shipment class], context);
    second.saleOrder = order;
    second.shipped = [NSDate date];
    second.shippedFrom = shelf;
    LBShip(&stock, second, brackets, @"1");
    LBCheck(@"the second shipment saved", LBSave(context, &why), why);
    LBCheck(@"contracted: all 3 bundles shipped", LBSame(kitLine.kitsShipped, @"3"), kitLine.kitsShipped);
    LBCheck(@"the order fully shipped", order.isFullyShipped && !order.isPartlyShipped, nil);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: lb-stock-check Logbook.momd Logbook.ormplans\n");
            return 2;
        }
        LBModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@(argv[1])]];
        NSError *error = nil;
        NSData *plans = [NSData dataWithContentsOfFile:@(argv[2])];
        id list = plans ? [NSPropertyListSerialization propertyListWithData:plans options:0 format:NULL error:&error] : nil;
        ORMTables *tables = list ? [ORMTables tablesWithPropertyList:list error:&error] : nil;
        if (!LBModel.entities.count || !tables) {
            fprintf(stderr, "no model at %s, or no tables at %s: %s\n", argv[1], argv[2], error.localizedDescription.UTF8String ?: "");
            return 2;
        }
        [ORMTables registerTables:tables named:@"Logbook"];
        LBKits();
        printf("stock: %lu failed\n", (unsigned long)LBFailures);
    }
    return LBFailures ? 1 : 0;
}
