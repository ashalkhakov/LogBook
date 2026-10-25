// How stock is shown (docs/STOCK.md): what a pick list calls each object
// (lbTitle, as LBDisplay.h has it for the logbook's), and a move as the
// changelog shows it. Categories on the generated classes, so that windows
// bind to them.

#pragma once
#import <Foundation/Foundation.h>
#import "LBDisplay.h"
#import "LBStockProcedures.h"
#import "Category+CoreDataClass.h"

NS_ASSUME_NONNULL_BEGIN

@interface Catalog (LBStockDisplay) <LBTitled>
@end
@interface StockItem (LBStockDisplay) <LBTitled>
// Whether a reorder rule of it is due.
@property (nonatomic, readonly) BOOL lbIsDue;
@end
@interface Category (LBStockDisplay) <LBTitled>
@end
@interface Contact (LBStockDisplay) <LBTitled>
@end
@interface Customer (LBStockDisplay) <LBTitled>
@end
@interface Supplier (LBStockDisplay) <LBTitled>
@end
@interface Warehouse (LBStockDisplay) <LBTitled>
@end
// A location by its warehouse and where it is within: "Garage / Shelf A".
@interface Location (LBStockDisplay) <LBTitled>
@end
@interface Holding (LBStockDisplay)
@property (nonatomic, readonly, copy) NSString *lbLocationTitle;
@end

// An order as the overview lists sales and purchases together: which it
// is, and to whom or from whom.
@interface SaleOrder (LBStockDisplay)
// How far it is shipped: "Shipped", "Partly", or nothing.
@property (nonatomic, readonly, copy) NSString *lbFilled;
@property (nonatomic, readonly, copy) NSString *lbKind;
@property (nonatomic, readonly, copy) NSString *lbParty;
@end
@interface PurchaseOrder (LBStockDisplay)
// How far it is received: "Received", "Partly", or nothing.
@property (nonatomic, readonly, copy) NSString *lbFilled;
@property (nonatomic, readonly, copy) NSString *lbKind;
@property (nonatomic, readonly, copy) NSString *lbParty;
@end
// The order an order's lines are listed in: by item, a phantom kit's
// components under its line.
@interface SaleLine (LBStockDisplay)
@property (nonatomic, readonly, copy) NSString *lbLineOrder;
@end
@interface PurchaseLine (LBStockDisplay)
@property (nonatomic, readonly, copy) NSString *lbLineOrder;
@end

@interface Move (LBStockDisplay)
// Where it went from and to: a location's title, or nothing.
@property (nonatomic, readonly, copy) NSString *lbFromTitle;
@property (nonatomic, readonly, copy) NSString *lbToTitle;
// What made it: "Receipt PO-GAR-0001/1", "Shipment SO-GAR-0002/1",
// "Assembly", "Count CT-0003", "Adjustment: Lost", "Transfer".
@property (nonatomic, readonly, copy) NSString *lbWhat;
// What kind of thing made it, as the changelog filters by: one of
// +lbKinds.
@property (nonatomic, readonly, copy) NSString *lbKind;
+ (NSArray<NSString *> *)lbKinds;
// Where an adjustment was (its one location), and what it changed there:
// so many more, or (out) less.
@property (nonatomic, readonly, copy) NSString *lbPlaceTitle;
@property (nonatomic, readonly, nullable) NSDecimalNumber *lbChange;
@end

@interface ReorderRule (LBStockDisplay)
// "Due" when it is, else nothing.
@property (nonatomic, readonly, copy) NSString *lbDue;
@end

// A count as the Counts tab lists it: its number (CT-GAR-0001), and where:
// its location, or its whole warehouse.
@interface StockCount (LBStockDisplay)
@property (nonatomic, readonly, copy) NSString *lbNumber;
@property (nonatomic, readonly, copy) NSString *lbWhere;
@end

NS_ASSUME_NONNULL_END
