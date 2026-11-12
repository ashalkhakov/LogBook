// The open tasks of the server's processes (LBTasks.h), in a window of
// their own (TasksWindow.xib; Window > Tasks): each a person's step --
// Confirm the order, Receive the goods -- with the order it is about.
// Open (or a double-click) shows its order in the order's window
// (LBStockOrderWindowController's task), where its step is done: Confirm
// or Cancel for ConfirmPurchaseOrder, Receive for ReceiveGoods; the server
// completes the task as the order changes, wherever it is changed. Asked
// again as a step is done, as the window becomes key, and on Refresh.

#import <AppKit/AppKit.h>

@class LBStore, LBTasks, LBTask, LBStockOrderWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface LBTasksWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>

- (instancetype)initWithStore:(LBStore *)store;
@property (nonatomic, readonly, strong) LBTasks *tasks;
@property (nonatomic, readonly, copy) NSArray<LBTask *> *openTasks;
@property (nonatomic, strong) IBOutlet NSTableView *table;
@property (nonatomic, strong) IBOutlet NSTextField *messageLabel;
// The window the last task opened was shown in.
@property (nonatomic, readonly, strong, nullable) LBStockOrderWindowController *orderWindow;

- (IBAction)refresh:(nullable id)sender;
- (IBAction)openTask:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
