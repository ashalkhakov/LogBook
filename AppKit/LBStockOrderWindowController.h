// An order's window (StockSale.xib, StockPurchase.xib; docs/STOCK.md,
// Orders): a sale or a purchase, its lines, its shipments or receipts and
// its returns. A purchase's window is a view of the model's form
// EditPurchaseOrder (its supplier, day, reference, note and lines, their
// items of its catalog, as the form offers them), saved by the form; its
// steps are sheets, each a view of its form: Confirm or Cancel,
// ConfirmPurchaseOrder; Receive, ReceiveGoods (a receipt made of what is
// outstanding, each line's quantity changed or taken away), submitted to
// the order's process. A sale's is the order's own, its steps the server's
// actions; Close and Reopen, and returns, are.

#import "LBStockEditor.h"

@class Location, StockItem, LBTask, LBTasks, LBFormValues;

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
// Its returns, the latest first.
@property (nonatomic, readonly, copy) NSArray *returns;
@property (nonatomic, strong) IBOutlet NSArrayController *lineList;
// A purchase's forms, as its window and its sheets bind them
// (LBFormValues.h): EditPurchaseOrder, always; ConfirmPurchaseOrder and
// ReceiveGoods while their sheet is shown.
@property (nonatomic, readonly, strong, nullable) LBFormValues *orderForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *confirmForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *receiveForm;
@property (nonatomic, strong) IBOutlet NSWindow *confirmPanel;
@property (nonatomic, strong) IBOutlet NSWindow *receivePanel;
@property (nonatomic, strong) IBOutlet NSTableView *linesTable;
// What its form chooses from: the catalog's customers (suppliers), items,
// locations.
@property (nonatomic, readonly, copy) NSArray *parties;
@property (nonatomic, readonly, copy) NSArray<StockItem *> *catalogItems;
@property (nonatomic, readonly, copy) NSArray<Location *> *locations;
// What a line is about to ship or receive: how many, from or at where.
@property (nonatomic, copy, nullable) NSString *moveQuantity;
@property (nonatomic, strong, nullable) Location *moveAt;
// Why a line comes back (goes back): one of returnReasons.
@property (nonatomic, readonly, copy) NSArray<NSString *> *returnReasons;
@property (nonatomic, copy) NSString *returnReason;

// The process's task it was opened for (LBTasksWindowController.h), named
// in its title. A purchase's steps are done here with the model's forms --
// Confirm or Cancel with ConfirmPurchaseOrder, Receive with ReceiveGoods:
// the form saved, then its instance submitted to the order's open task of
// it (this one, or found), which the server's process goes on with
// (Server/LBWorkflow.h); the title says it no more, and the tasks are asked
// again. nil: no task.
@property (nonatomic, strong, nullable) LBTask *task;
@property (nonatomic, strong, nullable) LBTasks *tasks;

// A purchase's step sheet's Submit: its form saved, then submitted to
// the order's task of it; its Cancel (and Escape): nothing of it kept.
- (IBAction)submitConfirm:(nullable id)sender;
- (IBAction)submitReceive:(nullable id)sender;
- (IBAction)dismissForm:(nullable id)sender;
// A purchase's Receive: its sheet, a move of each line outstanding.
- (IBAction)receiveGoods:(nullable id)sender;
// Confirm and Cancel: a purchase's sheet, its state chosen; a sale's, the
// server's. Close and Reopen, the server's.
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
// The chosen line, so many as typed, returned to (from) moveAt, for
// returnReason: the server's Return.
- (IBAction)returnLine:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
