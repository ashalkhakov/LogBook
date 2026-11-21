// The open tasks of the server's processes (LBTasks.h), in a window of
// their own (TasksWindow.xib; Window > Tasks): each a person's step --
// Confirm the order, Receive the goods -- with the order it is about.
// Open (or a double-click) shows its order in the order's window
// (LBStockOrderWindowController's task), where its step is done: Confirm
// or Cancel for ConfirmPurchaseOrder, Receive for ReceiveGoods; the server
// completes the task as the order changes, wherever it is changed. Asked
// again as a step is done, as the window becomes key, and on Refresh.
//
// Offline first, after them the steps done here and saved that wait to be
// submitted (the server not reached: LBAppState's), each in the place of
// its task: Submit sends it now (after a sync); Start Again forgets it and
// opens its order, where its step is done again. They are submitted after
// each sync too (LBAppController), and kept across launches.

#import <AppKit/AppKit.h>

@class LBStore, LBTasks, LBTask, LBStockOrderWindowController, LBPendingSubmission;

NS_ASSUME_NONNULL_BEGIN

@interface LBTasksWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>

- (instancetype)initWithStore:(LBStore *)store;
@property (nonatomic, readonly, strong) LBTasks *tasks;
// The open tasks listed, the table's first rows: those of no step waiting.
@property (nonatomic, readonly, copy) NSArray<LBTask *> *openTasks;
// The steps waiting, the rows after them.
@property (nonatomic, readonly, copy) NSArray<LBPendingSubmission *> *waiting;
// Whether the row chosen is a step waiting (Submit, Start Again).
@property (nonatomic, readonly) BOOL waitingChosen;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
// The window the last task opened was shown in.
@property (nonatomic, readonly, strong, nullable) LBStockOrderWindowController *orderWindow;

- (IBAction)refresh:(nullable id)sender;
- (IBAction)openTask:(nullable id)sender;
- (IBAction)submitWaiting:(nullable id)sender;
- (IBAction)startAgain:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
