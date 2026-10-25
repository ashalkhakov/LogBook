// An order's window (StockSale.xib, StockPurchase.xib; docs/STOCK.md,
// Orders): a sale or a purchase, its lines, and its shipments or receipts;
// confirmed, closed, cancelled or reopened, and its lines shipped or
// received, by the server's actions. It reads the order and what is of it.

#import "LBStockEditor.h"

@class Location, StockItem;

NS_ASSUME_NONNULL_BEGIN

@interface LBStockOrderWindowController : LBStockEditor

// The window of a SaleOrder or a PurchaseOrder.
- (instancetype)initWithStore:(LBStore *)store order:(NSManagedObject *)order;
@property (nonatomic, readonly, strong) NSManagedObject *order;
// A sale (else a purchase).
@property (nonatomic, readonly) BOOL sale;

// Its lines, by item, a phantom kit's components under its line; its
// shipments or receipts, the latest first.
@property (nonatomic, readonly, copy) NSArray *lines;
@property (nonatomic, readonly, copy) NSArray *documents;
@property (nonatomic, strong) IBOutlet NSArrayController *lineList;
@property (nonatomic, strong) IBOutlet NSTableView *linesTable;
// What its form chooses from: the catalog's customers (suppliers), items,
// locations.
@property (nonatomic, readonly, copy) NSArray *parties;
@property (nonatomic, readonly, copy) NSArray<StockItem *> *catalogItems;
@property (nonatomic, readonly, copy) NSArray<Location *> *locations;
// What a line is about to ship or receive: how many, from or at where.
@property (nonatomic, copy, nullable) NSString *moveQuantity;
@property (nonatomic, strong, nullable) Location *moveAt;

// The server's Confirm, Close, Cancel and Reopen.
- (IBAction)confirmOrder:(nullable id)sender;
- (IBAction)closeOrder:(nullable id)sender;
- (IBAction)cancelOrder:(nullable id)sender;
- (IBAction)reopenOrder:(nullable id)sender;
// A line of the first item, at its price (its cost), one of it; the
// chosen ones removed (a sale's through its procedure; a purchase's
// refused once some is received).
- (IBAction)addLine:(nullable id)sender;
- (IBAction)removeLine:(nullable id)sender;
// The chosen line, so many as typed, shipped from (received at) moveAt;
// every line's outstanding (shipping: what moveAt holds of each).
- (IBAction)moveLine:(nullable id)sender;
- (IBAction)moveOutstanding:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
