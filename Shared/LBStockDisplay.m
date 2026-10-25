#import "LBStockDisplay.h"

@implementation Catalog (LBStockDisplay)
- (NSString *)lbTitle { return self.catalogName ?: @""; }
@end

@implementation StockItem (LBStockDisplay)
- (NSString *)lbTitle { return self.itemName ?: @""; }

- (BOOL)lbIsDue {
    for (ReorderRule *rule in self.reorderRules) {
        if (rule.isDue) return YES;
    }
    return NO;
}
@end

@implementation Category (LBStockDisplay)
- (NSString *)lbTitle {
    return self.parent ? [NSString stringWithFormat:@"%@ / %@", self.parent.lbTitle, self.categoryName ?: @""] : self.categoryName ?: @"";
}
@end

@implementation Contact (LBStockDisplay)
- (NSString *)lbTitle { return self.contactName ?: @""; }
@end

@implementation Customer (LBStockDisplay)
- (NSString *)lbTitle { return self.contact.lbTitle ?: @""; }
@end

@implementation Supplier (LBStockDisplay)
- (NSString *)lbTitle { return self.contact.lbTitle ?: @""; }
@end

@implementation Warehouse (LBStockDisplay)
- (NSString *)lbTitle { return self.warehouseName ?: @""; }
@end

@implementation Location (LBStockDisplay)
- (NSString *)lbTitle {
    NSMutableArray *names = [NSMutableArray array];
    for (Location *at = self; at; at = at.container) [names insertObject:at.locationName ?: @"" atIndex:0];
    if (self.warehouse) [names insertObject:self.warehouse.lbTitle atIndex:0];
    return [names componentsJoinedByString:@" / "];
}
@end

@implementation Holding (LBStockDisplay)
- (NSString *)lbLocationTitle { return self.location.lbTitle ?: @""; }
@end

@implementation SaleOrder (LBStockDisplay)
- (NSString *)lbFilled { return self.isFullyShipped ? @"Shipped" : self.isPartlyShipped ? @"Partly" : @""; }
- (NSString *)lbKind { return @"Sale"; }
- (NSString *)lbParty { return self.customer.lbTitle ?: @""; }
@end

@implementation PurchaseOrder (LBStockDisplay)
- (NSString *)lbFilled { return self.isFullyReceived ? @"Received" : self.isPartlyReceived ? @"Partly" : @""; }
- (NSString *)lbKind { return @"Purchase"; }
- (NSString *)lbParty { return self.supplier.lbTitle ?: @""; }
@end

@implementation SaleLine (LBStockDisplay)
- (NSString *)lbLineOrder {
    NSString *own = self.stockItem.itemName ?: @"";
    if (!self.expandedFrom) return [own stringByAppendingString:@" 0"];
    return [NSString stringWithFormat:@"%@ 1 %@", self.expandedFrom.stockItem.itemName ?: @"", own];
}
@end

@implementation PurchaseLine (LBStockDisplay)
- (NSString *)lbLineOrder { return self.stockItem.itemName ?: @""; }
@end

@implementation Move (LBStockDisplay)

- (NSString *)lbFromTitle { return self.source.lbTitle ?: @""; }
- (NSString *)lbToTitle { return self.destination.lbTitle ?: @""; }

- (NSString *)lbWhat {
    if (self.receipt) {
        return [NSString stringWithFormat:@"Receipt %@/%d", self.receipt.purchaseOrder.lb_number ?: @"", self.receipt.runningNumber];
    }
    if (self.shipment) {
        return [NSString stringWithFormat:@"Shipment %@/%d", self.shipment.saleOrder.lb_number ?: @"", self.shipment.runningNumber];
    }
    if (self.assembly) return self.assembly.isADisassembly ? @"Taken apart" : @"Assembly";
    if (self.stockCount) return [NSString stringWithFormat:@"Count %@", self.stockCount.lbNumber];
    if (self.adjustmentReason) return [NSString stringWithFormat:@"Adjustment: %@", self.adjustmentReason];
    return @"Transfer";
}

+ (NSArray<NSString *> *)lbKinds {
    return @[ @"Receipt", @"Shipment", @"Assembly", @"Count", @"Adjustment", @"Transfer" ];
}

- (NSString *)lbKind {
    if (self.receipt) return @"Receipt";
    if (self.shipment) return @"Shipment";
    if (self.assembly) return @"Assembly";
    if (self.stockCount) return @"Count";
    if (self.adjustmentReason) return @"Adjustment";
    return @"Transfer";
}

- (NSString *)lbPlaceTitle {
    return (self.destination ?: self.source).lbTitle ?: @"";
}

- (NSDecimalNumber *)lbChange {
    if (self.destination || !self.moved) return self.moved;
    return [[NSDecimalNumber zero] decimalNumberBySubtracting:self.moved];
}

@end

@implementation ReorderRule (LBStockDisplay)
- (NSString *)lbDue { return self.isDue ? @"Due" : @""; }
@end

@implementation StockCount (LBStockDisplay)

- (NSString *)lbNumber {
    return [self.warehouse.catalog lb_numberOfKind:@"CT" running:self.runningNumber] ?: @"";
}

- (NSString *)lbWhere {
    if (self.countedLocation) return self.countedLocation.lbTitle;
    return [NSString stringWithFormat:@"%@ (all of it)", self.warehouse.lbTitle ?: @""];
}

@end

@implementation LBChange

- (instancetype)initWithMove:(Move *)move from:(NSString *)from to:(NSString *)to {
    if ((self = [super init])) {
        _move = move;
        _fromTitle = [from copy];
        _toTitle = [to copy];
    }
    return self;
}

/* "Place: before → after", what the move does to the place's count of its
   item, kept in held. */
static NSString *LBStep(Location *place, Move *move, BOOL in, NSMutableDictionary *held) {
    if (!place) return @"";
    NSArray *key = @[ move.stockItem.objectID ?: [NSNull null], place.objectID ];
    NSDecimalNumber *before = held[key] ?: [NSDecimalNumber zero];
    NSDecimalNumber *moved = move.moved ?: [NSDecimalNumber zero];
    NSDecimalNumber *after = in ? [before decimalNumberByAdding:moved] : [before decimalNumberBySubtracting:moved];
    held[key] = after;
    return [NSString stringWithFormat:@"%@: %@ \u2192 %@", place.lbTitle, before, after];
}

+ (NSArray<LBChange *> *)changesOf:(NSArray<Move *> *)moves {
    NSSortDescriptor *oldest = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(moment)) ascending:YES];
    NSMutableDictionary *held = [NSMutableDictionary dictionary];
    NSMapTable *made = [NSMapTable strongToStrongObjectsMapTable];
    for (Move *move in [moves sortedArrayUsingDescriptors:@[ oldest ]]) {
        NSString *from = LBStep(move.source, move, NO, held);
        NSString *to = LBStep(move.destination, move, YES, held);
        [made setObject:[[LBChange alloc] initWithMove:move from:from to:to] forKey:move];
    }
    NSMutableArray *changes = [NSMutableArray arrayWithCapacity:moves.count];
    for (Move *move in moves) [changes addObject:[made objectForKey:move]];
    return changes;
}

@end

@implementation LBStockTotals

/* So many of the unit's factor (kg, or m, of one). */
static NSDecimalNumber *LBInBase(NSDecimalNumber *quantity, NSDecimalNumber *factor) {
    return factor ? [quantity decimalNumberByMultiplyingBy:factor] : quantity;
}

static NSDecimalNumber *LBRounded(NSDecimalNumber *number) {
    NSDecimalNumberHandler *three = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:3 raiseOnExactness:NO
                                                                                    raiseOnOverflow:NO raiseOnUnderflow:NO
                                                                                 raiseOnDivideByZero:NO];
    return [number decimalNumberByRoundingAccordingToBehavior:three];
}

+ (instancetype)totalsOf:(NSArray<StockItem *> *)items weightIn:(WeightUnit *)weightUnit sizeIn:(SizeUnit *)sizeUnit {
    NSDecimalNumber *kilograms = [NSDecimalNumber zero], *cubicMetres = [NSDecimalNumber zero];
    for (StockItem *item in items) {
        NSDecimalNumber *held = item.totalQuantity;
        if (!held) continue;
        if (item.weightQuantity) {
            kilograms = [kilograms decimalNumberByAdding:[held decimalNumberByMultiplyingBy:LBInBase(item.weightQuantity, item.weightWeightUnit.factor)]];
        }
        if (item.lengthQuantity && item.widthQuantity && item.heightQuantity) {
            NSDecimalNumber *each = [[LBInBase(item.lengthQuantity, item.lengthSizeUnit.factor)
                decimalNumberByMultiplyingBy:LBInBase(item.widthQuantity, item.widthSizeUnit.factor)]
                decimalNumberByMultiplyingBy:LBInBase(item.heightQuantity, item.heightSizeUnit.factor)];
            cubicMetres = [cubicMetres decimalNumberByAdding:[held decimalNumberByMultiplyingBy:each]];
        }
    }
    LBStockTotals *totals = [[self alloc] init];
    NSDecimalNumber *perWeight = weightUnit.factor, *perSize = sizeUnit.factor;
    totals->_weight = LBRounded(perWeight ? [kilograms decimalNumberByDividingBy:perWeight] : kilograms);
    NSDecimalNumber *perVolume = perSize ? [[perSize decimalNumberByMultiplyingBy:perSize] decimalNumberByMultiplyingBy:perSize] : nil;
    totals->_volume = LBRounded(perVolume ? [cubicMetres decimalNumberByDividingBy:perVolume] : cubicMetres);
    totals->_weightText = [NSString stringWithFormat:@"%@ %@", totals->_weight, weightUnit.code ?: @"kg"];
    totals->_volumeText = [NSString stringWithFormat:@"%@ %@\u00B3", totals->_volume, sizeUnit.code ?: @"m"];
    return totals;
}

@end
