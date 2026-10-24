// The stock model's derivations and rules checked over a store of the
// model's own, each change saved as the server saves one (the generated
// orm_prepareForSave:, then save:). Each check a line, "ok" or "FAIL"; 1
// when one failed.
//
//   lb-stock-check build/Logbook.momd build/Logbook.ormplans
//
// - holdings: what the moves leave; a move out of more than is there, or
//   where its item has no holding, refused;
// - kits: how many each can make, whole batches of its scarcest component
//   times its yield; what it contains; one containing itself refused;
// - a phantom kit is never moved;
// - a phantom kit's sale line expanded into its components' lines, shipped
//   in part and then in full: the kits shipped worked back from them
//   (contracted), what is outstanding, and the order partly, then fully,
//   shipped;
// - committed, incoming, available and short, and a reorder rule due;
// - a count's adjustments, and adjustments of reason Count only in one.

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
#import "Contact+CoreDataClass.h"
#import "Supplier+CoreDataClass.h"
#import "PurchaseOrder+CoreDataClass.h"
#import "PurchaseLine+CoreDataClass.h"
#import "StockCount+CoreDataClass.h"
#import "ReorderRule+CoreDataClass.h"

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
    __unsafe_unretained Warehouse *warehouse;
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

/* The item's holding on the shelf: made where there is none. */
static Holding *LBHolding(LBStock *stock, StockItem *item) {
    for (Holding *holding in item.holdings) {
        if (holding.location == stock->shelf) return holding;
    }
    Holding *holding = LBInsert([Holding class], stock->context);
    holding.stockItem = item;
    holding.location = stock->shelf;
    return holding;
}

/* An adjustment on the shelf: so many in (more than none) or out (less),
   for the reason. */
static Move *LBAdjust(LBStock *stock, StockItem *item, NSString *quantity, NSString *reason) {
    LBHolding(stock, item);
    Move *move = LBInsert([Move class], stock->context);
    move.stockItem = item;
    BOOL out = [quantity hasPrefix:@"-"];
    move.moved = LBN(out ? [quantity substringFromIndex:1] : quantity);
    if (out) move.source = stock->shelf; else move.destination = stock->shelf;
    move.moment = [NSDate date];
    move.user = stock->anna;
    move.adjustmentReason = reason;
    return move;
}

static void LBKeep(LBStock *stock, StockItem *item, NSString *quantity) {
    LBAdjust(stock, item, quantity, @"Opening");
}

static NSDecimalNumber *LBHeld(LBStock *stock, StockItem *item) {
    return LBHolding(stock, item).quantity;
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
    LBStock stock = { context, nil, nil, nil, nil };
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
    stock.warehouse = warehouse;
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
    LBCheck(@"kits saved, their stock come in", LBSave(context, &why), why);
    LBCheck(@"the bolts' holding: 10, as their move left it", LBSame(LBHeld(&stock, bolt), @"10"), LBHeld(&stock, bolt));
    LBCheck(@"a mount: 2, the bolts' whole batches (10 / 4), fewer than the brackets' 3", LBSame(mount.makeable, @"2"),
            mount.makeable);
    LBCheck(@"pieces: 2 rolls, 20 each", LBSame(piece.makeable, @"40"), piece.makeable);
    LBCheck(@"a bundle: 3, as many as brackets", LBSame(bundle.makeable, @"3"), bundle.makeable);
    LBCheck(@"a bolt makes nothing: no kit", bolt.makeable == nil, bolt.makeable);
    LBCheck(@"a mount contains bolts and brackets", [mount.containeds isEqualToSet:[NSSet setWithObjects:bolt, bracket, nil]],
            [mount.containeds valueForKey:@"itemName"]);

    /* None of its components gone: a kit makes none. */
    LBAdjust(&stock, bracket, @"-3", @"Damaged");
    LBCheck(@"brackets damaged, all three: saved", LBSave(context, &why), why);
    LBCheck(@"none held", LBSame(LBHeld(&stock, bracket), @"0"), LBHeld(&stock, bracket));
    LBCheck(@"then a mount makes none", LBSame(mount.makeable, @"0"), mount.makeable);
    LBAdjust(&stock, bracket, @"3", @"Found");
    LBCheck(@"brackets found: saved", LBSave(context, &why), why);

    /* Out of more than is there; where nothing is held. */
    LBAdjust(&stock, bolt, @"-11", @"Lost");
    why = nil;
    LBCheck(@"11 bolts lost of 10 is refused", !LBSave(context, &why), nil);
    printf("     (%s)\n", why.UTF8String);
    Move *nowhere = LBInsert([Move class], context);
    nowhere.stockItem = mount;
    nowhere.moved = LBN(@"1");
    nowhere.destination = shelf;
    nowhere.moment = [NSDate date];
    nowhere.user = anna;
    nowhere.adjustmentReason = @"Found";
    why = nil;
    LBCheck(@"a mount found where it has no holding is refused", !LBSave(context, &why), nil);
    printf("     (%s)\n", why.UTF8String);

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
    Contact *bobs = LBInsert([Contact class], context);
    bobs.contactName = @"Bob's Garage";
    bobs.isACompany = YES;
    bobs.catalog = catalog;
    Customer *bob = LBInsert([Customer class], context);
    bob.contact = bobs;
    bob.catalog = catalog;
    SaleOrder *order = LBInsert([SaleOrder class], context);
    order.catalog = catalog;
    order.customer = bob;
    order.runningNumber = 1;
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
    LBCheck(@"committed: its 3 brackets and 6 bolts", LBSame(bracket.committed, @"3") && LBSame(bolt.committed, @"6"),
            @[ bracket.committed ?: @"none", bolt.committed ?: @"none" ]);
    LBCheck(@"available: no brackets, 4 bolts", bracket.available == nil && LBSame(bolt.available, @"4"),
            @[ bracket.available ?: @"none", bolt.available ?: @"none" ]);
    LBCheck(@"nothing short", bracket.shortage == nil && bolt.shortage == nil, nil);

    /* Two brackets and all six bolts go out: two bundles' worth. */
    Shipment *first = LBInsert([Shipment class], context);
    first.saleOrder = order;
    first.shipped = [NSDate date];
    first.shippedFrom = shelf;
    first.runningNumber = 1;
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
    second.runningNumber = 2;
    LBShip(&stock, second, brackets, @"1");
    LBCheck(@"the second shipment saved", LBSave(context, &why), why);
    LBCheck(@"contracted: all 3 bundles shipped", LBSame(kitLine.kitsShipped, @"3"), kitLine.kitsShipped);
    LBCheck(@"the order fully shipped", order.isFullyShipped && !order.isPartlyShipped, nil);
    LBCheck(@"shipped: brackets and bolts held no more, none committed",
            LBSame(LBHeld(&stock, bracket), @"0") && LBSame(LBHeld(&stock, bolt), @"4") && bracket.committed == nil
                && bolt.committed == nil,
            @[ LBHeld(&stock, bracket), LBHeld(&stock, bolt), bracket.committed ?: @"none" ]);

    /* Ten brackets more sold: seven short of what is kept... */
    SaleOrder *more = LBInsert([SaleOrder class], context);
    more.catalog = catalog;
    more.customer = bob;
    more.runningNumber = 2;
    more.saleOrdered = [NSDate date];
    more.orderState = @"Confirmed";
    SaleLine *tenBrackets = LBInsert([SaleLine class], context);
    tenBrackets.saleOrder = more;
    tenBrackets.stockItem = bracket;
    tenBrackets.quantity = LBN(@"10");
    tenBrackets.linePriceAmount = LBN(@"2");
    tenBrackets.linePriceCurrency = @"USD";
    LBCheck(@"ten brackets sold, none held: saved", LBSave(context, &why), why);
    LBCheck(@"brackets short by 10", LBSame(bracket.shortage, @"10"), bracket.shortage);

    /* ...and twelve bought, coming. */
    Contact *parts = LBInsert([Contact class], context);
    parts.contactName = @"Parts Ltd";
    parts.catalog = catalog;
    Supplier *supplier = LBInsert([Supplier class], context);
    supplier.contact = parts;
    supplier.catalog = catalog;
    PurchaseOrder *purchase = LBInsert([PurchaseOrder class], context);
    purchase.catalog = catalog;
    purchase.supplier = supplier;
    purchase.runningNumber = 1;
    purchase.ordered = [NSDate date];
    purchase.orderState = @"Draft";
    PurchaseLine *twelve = LBInsert([PurchaseLine class], context);
    twelve.purchaseOrder = purchase;
    twelve.stockItem = bracket;
    twelve.quantity = LBN(@"12");
    twelve.lineUnitCostAmount = LBN(@"1");
    twelve.lineUnitCostCurrency = @"USD";
    ReorderRule *rule = LBInsert([ReorderRule class], context);
    rule.stockItem = bracket;
    rule.warehouse = warehouse;
    rule.reorderPoint = LBN(@"5");
    rule.reorderLevel = LBN(@"20");
    LBCheck(@"a purchase drafted, a reorder rule: saved", LBSave(context, &why), why);
    LBCheck(@"a draft brings nothing: none incoming", bracket.incoming == nil, bracket.incoming);
    LBCheck(@"brackets due for reorder: none available or coming, below 5", rule.isDue, nil);
    purchase.orderState = @"Confirmed";
    LBCheck(@"the purchase confirmed: saved", LBSave(context, &why), why);
    LBCheck(@"12 brackets incoming", LBSame(bracket.incoming, @"12"), bracket.incoming);
    LBCheck(@"due no more: 12 coming is not below 5", !rule.isDue, nil);

    /* A count: one bolt more found than held. */
    StockCount *count = LBInsert([StockCount class], context);
    count.warehouse = warehouse;
    count.countedOn = [NSDate date];
    count.counter = anna;
    count.runningNumber = 1;
    Move *found = LBAdjust(&stock, bolt, @"1", @"Count");
    found.stockCount = count;
    LBCheck(@"a count, a bolt more: saved", LBSave(context, &why), why);
    LBCheck(@"5 bolts held", LBSame(LBHeld(&stock, bolt), @"5"), LBHeld(&stock, bolt));
    LBAdjust(&stock, bolt, @"1", @"Count");
    why = nil;
    LBCheck(@"a Count adjustment of no count is refused", !LBSave(context, &why), nil);
    printf("     (%s)\n", why.UTF8String);
    Move *wrong = LBAdjust(&stock, bolt, @"1", @"Found");
    wrong.stockCount = count;
    why = nil;
    LBCheck(@"a count's adjustment of another reason is refused", !LBSave(context, &why), nil);
    printf("     (%s)\n", why.UTF8String);
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
