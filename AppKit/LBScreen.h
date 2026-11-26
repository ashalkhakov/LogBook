// A screen of the one window (MainWindow.xib, LBWorkspace.h): what was a
// window of its own (the stock's lists, an item, an order, a count, a
// catalog's settings, the tasks, the lists), its view shown in the
// window's main pane, the sidebar's choice or opened from another screen.
// Its XIB's File's Owner, the view its `view`; its sheets are the window's.
//
// Kept by the workspace from when it is shown until it is closed: going to
// another screen leaves it as it is, and Back shows it again. Leaving one
// with changes not saved asks first (-shouldLeave), as closing its window
// did.

#import <AppKit/AppKit.h>

@class LBWorkspace;

NS_ASSUME_NONNULL_BEGIN

// Posted as a screen is closed (no longer kept by the workspace).
FOUNDATION_EXPORT NSNotificationName const LBScreenWillCloseNotification;

// Each list under the view with no action of its own: clicked, the
// target's action sent (the inspector shows its row, the chosen row
// clicked again too).
FOUNDATION_EXPORT void LBListsClickedTo(NSView *view, id target, SEL action);

@interface LBScreen : NSViewController

// The window it is shown in, the one window; nil, none open.
@property (nonatomic, readonly, nullable) NSWindow *window;
// Whether it is the screen shown in the main pane now.
@property (nonatomic, readonly) BOOL isShown;
// Whether its view has loaded.
@property (nonatomic, readonly) BOOL isWindowLoaded;

// Shown in the main pane (and kept), the screen shown before left.
- (IBAction)showWindow:(nullable id)sender;
// No longer kept: the screen before it shown again where it was shown.
- (void)close;

// Whether it may be left for another screen: its edits committed, its
// changes saved or let go, as the user says. YES here.
- (BOOL)shouldLeave;
// Whether it may close: the same, by default.
- (BOOL)shouldClose;
// Once its view is in the window, shown: what it does then (a task's
// sheet, its lists read again).
- (void)screenDidShow;

// File > Save and File > Revert to Saved, while it is the screen shown
// (the window's controller sends them on): its changes saved, or let go
// and what it shows read again. Nothing here: a screen with nothing of its
// own to save (the tasks).
- (IBAction)save:(nullable id)sender;
- (IBAction)revertChanges:(nullable id)sender;
// Whether it has changes of its own to save, File's Save and Revert to
// Saved enabled for it: NO here.
@property (nonatomic, readonly) BOOL savable;

// The form of what it has chosen (a line, a row), shown in the window's
// inspector while it is shown (its XIB's "screenInspector", a view drawn
// from the top of its height); nil, none ("No Selection").
@property (nonatomic, strong, nullable) IBOutlet NSView *inspectorView;
// Its pages, where it has several (one per tab of the screen's): the one
// it shows chosen by it, the inspector fitted to it.
@property (nonatomic, strong, nullable) IBOutlet NSTabView *inspectorPages;
// The inspector's page of that identifier chosen, the window told.
- (void)showInspectorPage:(nullable NSString *)identifier;
// The list a row was chosen in last (by the user: the list has the focus)
// decides the page: "row-<the list's identifier>", else the page of the tab
// it is on. A tab chosen: the tab's own page, else its first list's chosen
// row's.
- (nullable NSString *)inspectorPageForList:(NSTableView *)list;
- (void)inspectorFollowTab:(NSTabViewItem *)item;
// Whether it has something chosen for its inspector to show: YES here; a
// screen whose one list has nothing chosen says NO ("No Selection").
@property (nonatomic, readonly) BOOL inspectorHasChoice;

// Its title kept as a key path of it says (an item's name): observed, so
// on GNUstep too, whose bindings bind no title.
@property (nonatomic, copy, nullable) NSString *titleKeyPath;

// The size its view was drawn at in its XIB: the least the main pane
// gives it.
@property (nonatomic, readonly) NSSize drawnSize;

@end

NS_ASSUME_NONNULL_END
