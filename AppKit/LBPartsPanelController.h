// The parts a service or a tyre change used (Parts.xib; docs/STOCK.md,
// Parts used): its sale's lines, where they come from, a part used (an
// item, so many), or how many of one were used after all. It edits the logbook
// window's objects: the record's Save sends them, and the server ships
// them as it saves (Shared/LBStockProcedures.h).

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class Event, SaleLine, StockItem, Location;

NS_ASSUME_NONNULL_BEGIN

@interface LBPartsPanelController : NSWindowController

- (instancetype)initWithEvent:(Event *)event;
@property (nonatomic, readonly, strong) Event *event;

// Its parts, by item; every location and item it may take them from and of
// (every catalog's the user sees).
@property (nonatomic, readonly, copy) NSArray<SaleLine *> *parts;
@property (nonatomic, readonly, copy) NSArray<Location *> *locations;
@property (nonatomic, readonly, copy) NSArray<StockItem *> *items;
@property (nonatomic, strong) IBOutlet NSArrayController *partList;
// Where they come from: its sale's, else where the last were taken from
// (kept on this Mac). Chosen, its sale's too.
@property (nonatomic, strong, nullable) Location *partsLocation;
// The part about to be used, and how many (as typed).
@property (nonatomic, strong, nullable) StockItem *chosenItem;
@property (nonatomic, copy, nullable) NSString *quantityText;

// The chosen item used, so many, from partsLocation (its first location of
// the item's catalog where that is another's). The chosen part used so
// many as typed after all; the chosen parts none (what was shipped of them
// comes back, Event -lb_setUsed:). Refused: why, in lastError.
- (IBAction)usePart:(nullable id)sender;
- (IBAction)setUsed:(nullable id)sender;
- (IBAction)removePart:(nullable id)sender;
- (IBAction)done:(nullable id)sender;
@property (nonatomic, readonly, strong, nullable) NSError *lastError;
// Said in no alert, kept in lastError: a self-test has no one to answer one.
@property (nonatomic) BOOL quiet;

@end

NS_ASSUME_NONNULL_END
