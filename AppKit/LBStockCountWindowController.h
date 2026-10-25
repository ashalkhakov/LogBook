// A count's window (StockCount.xib; docs/STOCK.md, Counts): a count of a
// warehouse, or one of its locations, taken: each holding there listed,
// what is held shown or hidden as the counter chooses, what was found
// typed, an item found that was not expected added; posted by the
// server's Count.

#import "LBStockEditor.h"

@class Warehouse, Location, StockItem, Holding, StockCount, LBCountPlace;

NS_ASSUME_NONNULL_BEGIN

// A row of the count: an item at a location, and how many were found
// (typed; none yet, nil).
@interface LBCountRow : NSObject
@property (nonatomic, strong, nullable) StockItem *item;
@property (nonatomic, strong, nullable) Location *location;
@property (nonatomic, copy, nullable) NSDecimalNumber *found;
// What is held there, when the counter chooses to see it; else nothing.
@property (nonatomic, readonly, nullable) NSDecimalNumber *expectedShown;
@end

@interface LBStockCountWindowController : LBStockEditor

- (instancetype)initWithStore:(LBStore *)store catalog:(Catalog *)catalog;

// What it may be of, and what it is of; the rows of the count started,
// and the locations a row may be at; the items one may be of; whether
// what is held is shown.
@property (nonatomic, readonly, copy) NSArray<LBCountPlace *> *countPlaces;
@property (nonatomic, strong, nullable) LBCountPlace *countPlace;
@property (nonatomic, readonly, copy) NSArray<LBCountRow *> *rowsCounted;
@property (nonatomic, readonly, copy) NSArray<Location *> *countLocations;
@property (nonatomic, readonly, copy) NSArray<StockItem *> *catalogItems;
@property (nonatomic) BOOL showsExpected;
@property (nonatomic, strong) IBOutlet NSArrayController *countRows;
@property (nonatomic, strong) IBOutlet NSTableView *countRowsTable;
// The count posted last; nil, none yet.
@property (nonatomic, readonly, strong, nullable) StockCount *posted;

// Started: a row for each holding of countPlace, nothing found yet. A row
// added or removed. Posted: the server's Count of what each row found;
// refused while one has nothing typed, or one is counted twice.
- (IBAction)startCount:(nullable id)sender;
- (IBAction)addCountRow:(nullable id)sender;
- (IBAction)removeCountRow:(nullable id)sender;
- (IBAction)postCount:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
