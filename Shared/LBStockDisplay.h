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

@interface Move (LBStockDisplay)
// Where it went from and to: a location's title, or nothing.
@property (nonatomic, readonly, copy) NSString *lbFromTitle;
@property (nonatomic, readonly, copy) NSString *lbToTitle;
// What made it: "Receipt PO-GAR-0001/1", "Shipment SO-GAR-0002/1",
// "Assembly", "Count CT-0003", "Adjustment: Lost", "Transfer".
@property (nonatomic, readonly, copy) NSString *lbWhat;
@end

NS_ASSUME_NONNULL_END
