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
    if (self.stockCount) {
        Catalog *catalog = self.stockCount.warehouse.catalog;
        return [NSString stringWithFormat:@"Count %@", [catalog lb_numberOfKind:@"CT" running:self.stockCount.runningNumber]];
    }
    if (self.adjustmentReason) return [NSString stringWithFormat:@"Adjustment: %@", self.adjustmentReason];
    return @"Transfer";
}

@end
