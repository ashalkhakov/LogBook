// Logbook's desktop app (macOS and GNUstep), the owner's: the vehicles,
// what is recorded of them, who drives them, and the reports. Online: the
// server's (LBStore.h), connected to and signed in as it asks
// (LBConnectPanel.h).
//
// The server: the LBServer default, else asked for. With --self-test
// <server root> the app drives itself against a running server
// (LBSelfTest.h) and quits.

#import <AppKit/AppKit.h>
#import "LBConnectPanel.h"

@class LBStore;

NS_ASSUME_NONNULL_BEGIN

@interface LBAppController : NSObject <NSApplicationDelegate, LBConnectPanelDelegate>
@property (nonatomic, readonly, strong, nullable) LBStore *store;
// Another server, asked for.
- (IBAction)connect:(nullable id)sender;
- (IBAction)signOut:(nullable id)sender;
// The same server signed in to afresh (its tokens forgotten): what is kept
// on this Mac kept, and sent once signed in.
- (IBAction)signInAgain:(nullable id)sender;
// The signed-in user's preferences (LBPreferencesController.h).
- (IBAction)showPreferences:(nullable id)sender;
// The kinds of expense, the checklists and the exchange rates, each at its
// tab (LBListsController.h).
- (IBAction)showExpenseKinds:(nullable id)sender;
- (IBAction)showChecklists:(nullable id)sender;
- (IBAction)showExchangeRates:(nullable id)sender;
// The stock window (LBStockWindowController.h): the catalogs, their items
// and their stock, over the same server.
- (IBAction)showStock:(nullable id)sender;
// Go > Tasks: the processes' open tasks (LBTasksWindowController.h).
- (IBAction)showTasks:(nullable id)sender;
// Go > Logbook: the logbook's page, at the vehicle chosen.
- (IBAction)showLogbook:(nullable id)sender;
// Help > Logbook Help: the project's page, its README (no help book yet).
- (IBAction)showHelp:(nullable id)sender;
// Updates, now (LBUpdater.h).
- (IBAction)checkForUpdates:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
