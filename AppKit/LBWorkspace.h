// The one window's places (MainWindow.xib), as Xcode's: the sidebar's
// outline on the left, the screen chosen in the main pane, an inspector on
// the right, each side shown or hidden (the toolbar, View); Back and
// Forward through the screens shown; the sync's state in the toolbar.
//
// The sidebar:
//   Vehicles   each vehicle: the logbook's page (MainWindow.xib's tabs:
//              Vehicle, Records, Reminders, Calendar, Reports)
//   Stock      each catalog: Overview, Items, Purchases, Sales, Counts,
//              Changelog (the stock's screen, LBStockWindowController),
//              Settings (its settings' screen)
//   Work       Tasks (LBTasksWindowController)
//   Lists      Expense Kinds, Checklists, Exchange Rates (LBListsController)
// with + (New Vehicle, New Catalog) and - (the vehicle chosen removed)
// under it. What a screen opens (an item, an order, a count) is shown in
// the main pane too (LBScreen.h); Back goes to where it was opened from.

#import <AppKit/AppKit.h>

@class LBMainWindowController, LBScreen, LBStockWindowController, LBTasksWindowController, LBListsController,
    UDPaneSplitController, Catalog;

NS_ASSUME_NONNULL_BEGIN

// The panes, as the split view has them.
typedef NS_ENUM(NSInteger, LBWorkspacePane) {
    LBSidebarPane = 0,
    LBScreenPane = 1,
    LBInspectorPane = 2,
};

@interface LBWorkspace : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>

// The workspace of the window open (one at a time); nil, none.
+ (nullable LBWorkspace *)current;

@property (nonatomic, weak) IBOutlet LBMainWindowController *windowController;
@property (nonatomic, weak) IBOutlet NSOutlineView *sidebar;
// The logbook's page (the vehicle chosen), and where another screen's view
// goes: one of them shown at a time.
@property (nonatomic, weak) IBOutlet NSView *logbookPage;
@property (nonatomic, weak) IBOutlet NSView *screenHost;
@property (nonatomic, weak) IBOutlet NSView *inspectorPane;
@property (nonatomic, strong) IBOutlet UDPaneSplitController *paneSplit;
// The sidebar's -: the vehicle chosen removed.
@property (nonatomic, weak) IBOutlet NSButton *removeButton;

@property (nonatomic, readonly, nullable) NSWindow *window;
// The screen in the main pane; nil, the logbook's page.
@property (nonatomic, readonly, nullable) LBScreen *shownScreen;
// The screens kept (shown since they were opened, not closed yet).
@property (nonatomic, readonly, copy) NSArray<LBScreen *> *keptScreens;

// Set up once the window has loaded (its controller's -windowDidLoad).
- (void)windowDidLoad;

// The screen shown in the main pane, kept, the one shown before left (NO:
// it may not be, as its user said).
- (BOOL)showScreen:(LBScreen *)screen;
// The logbook's page shown, at the vehicle chosen.
- (BOOL)showLogbook;
// The screen no longer kept; the one before it shown where it was shown.
- (void)closeScreen:(LBScreen *)screen;
// Each screen kept closed, each asked first when asking (NO: one may not
// close, as its user said; none closed then).
- (BOOL)closeScreensAsking:(BOOL)asking;

// The stock's screen, made the first time it is asked for.
@property (nonatomic, readonly, strong) LBStockWindowController *stock;
// The stock's screen shown, at the catalog's tab of that identifier
// (overview, items, purchaseOrders, saleOrders, counts, changes); nil, as
// it is (the first catalog at first).
- (BOOL)showStockTab:(nullable NSString *)tab ofCatalog:(nullable Catalog *)catalog;
// The tasks' screen, shown.
@property (nonatomic, readonly, strong) LBTasksWindowController *tasks;
- (BOOL)showTasks;
// The lists' screen, shown at its tab of that identifier (expenseKinds,
// checklists, exchangeRates).
@property (nonatomic, readonly, strong) LBListsController *lists;
- (BOOL)showListsTab:(NSString *)tab;

// What the sidebar lists, read again (vehicles and catalogs added,
// renamed, removed).
- (void)reloadSidebar;

- (IBAction)goBack:(nullable id)sender;
- (IBAction)goForward:(nullable id)sender;
- (IBAction)toggleSidebarPane:(nullable id)sender;
- (IBAction)toggleInspectorPane:(nullable id)sender;
// The sidebar's + and -.
- (IBAction)newVehicle:(nullable id)sender;
- (IBAction)newCatalog:(nullable id)sender;
- (IBAction)removeVehicle:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
