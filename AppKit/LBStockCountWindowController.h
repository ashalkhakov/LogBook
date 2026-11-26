// A count's window (StockCount.xib; docs/STOCK.md, Counts): a view of the
// model's CountStock. A count of a warehouse, or one of its locations,
// taken: a line for each holding there, what is held shown or hidden as
// the counter chooses, what was found typed, an item found that was not
// expected added; submitted, saved as counted, for a manager to review.
// Its review (ReviewStockCount, a sheet over it) posts it, its differences
// adjusted, or rejects it: its process's task (Model/CountReview.bpmn, the
// flow Counting's Review), opened from Go > Tasks.

#import "LBStockEditor.h"

@class Warehouse, Location, StockItem, Holding, StockCount, LBCountPlace, ORMFlowSession;

NS_ASSUME_NONNULL_BEGIN

@interface LBStockCountWindowController : LBStockEditor

// A new count of the catalog's.
- (instancetype)initWithStore:(LBStore *)store catalog:(Catalog *)catalog;
// A count taken, as it is: its review's task's (LBStockEditor's task).
- (instancetype)initWithStore:(LBStore *)store count:(StockCount *)count;

// What it may be of, and what the count started is of.
@property (nonatomic, readonly, copy) NSArray<LBCountPlace *> *countPlaces;
@property (nonatomic, strong, nullable) LBCountPlace *countPlace;
// Whether what is held is shown.
@property (nonatomic) BOOL showsExpected;
// The count being taken, or reviewed; nil before one is started.
@property (nonatomic, readonly, strong, nullable) StockCount *stockCount;
// Its forms, as the window and its sheet bind them (LBFormValues.h):
// CountStock while a count is shown, ReviewStockCount while its sheet is.
@property (nonatomic, readonly, strong, nullable) LBFormValues *countForm;
@property (nonatomic, readonly, strong, nullable) LBFormValues *reviewForm;
@property (nonatomic, strong) IBOutlet NSArrayController *countRows;
@property (nonatomic, strong) IBOutlet NSTableView *countRowsTable;
@property (nonatomic, strong) IBOutlet NSWindow *reviewPanel;
// Its way through its forms (Model/Counting.flow, ORMRuntime's
// ORMFlowSession): CountStock, and its review's ReviewStockCount.
@property (nonatomic, readonly, strong, nullable) ORMFlowSession *flow;
// The count submitted last; nil, none yet.
@property (nonatomic, readonly, strong, nullable) StockCount *submitted;

// Started: a count of countPlace, today, by the user, a line for each
// holding there, nothing found yet. A line added or removed. Submitted:
// saved as counted by its form; refused while a line has nothing typed.
- (IBAction)startCount:(nullable id)sender;
- (IBAction)addCountRow:(nullable id)sender;
- (IBAction)removeCountRow:(nullable id)sender;
- (IBAction)submitCount:(nullable id)sender;
// Its review's sheet's Submit: its form saved (posted, or rejected), then
// submitted to its task; its Cancel (and Escape): nothing of it kept.
- (IBAction)submitReview:(nullable id)sender;
- (IBAction)dismissForm:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
