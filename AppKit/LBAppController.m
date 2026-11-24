#import "LBTasksWindowController.h"
#import "LBAppController.h"
#import "LBStore.h"
#import "LBLocalStore.h"
#import "LBConflicts.h"
#import "LBTasks.h"
#import "LBDisplay.h"
#import "LBMainWindowController.h"
#import "LBSelfTest.h"
#import "LBPreferencesController.h"
#import "LBListsController.h"
#import "LBStockWindowController.h"
#import "LBUpdater.h"

/* Logbook > Check for Updates… (MainMenu.xib), gone where there is no
   updater (LBUpdater.h). */
static const NSInteger LBCheckForUpdatesTag = 1001;

@implementation LBAppController {
    LBConnectPanel *_panel;
    ODataSignIn *_signIn;
    LBMainWindowController *_window;
    LBPreferencesController *_preferences;
    LBListsController *_lists;
    LBStockWindowController *_stock;
    LBTasksWindowController *_tasks;
    LBUpdater *_updater;
    /* The steps saved here that wait, submitted after each sync. */
    LBTasks *_waitingTasks;
    BOOL _submittingWaiting;
}

/* Updates, set up before the app finishes launching (as Sparkle asks), not
   started in a self-test, which reaches no network. */
- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    _updater = [[LBUpdater alloc] initStarting:LBSelfTestRoot == nil];
    if (!_updater.available) {
        NSMenu *menu = [[NSApp mainMenu] itemAtIndex:0].submenu;
        NSInteger index = [menu indexOfItemWithTag:LBCheckForUpdatesTag];
        if (index >= 0) [menu removeItemAtIndex:index];
    }
}

- (IBAction)checkForUpdates:(id)sender {
    [_updater checkForUpdates:sender];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self showPanelWithServer:LBSelfTestRoot.absoluteString connecting:YES];
}

/* The last window closed by the user: the app done. Connecting
   elsewhere closes one and opens the other in the same event, which is
   not the last closing. */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (_stock && ![_stock shouldClose]) return NSTerminateCancel;
    return !_window || [_window shouldClose] ? NSTerminateNow : NSTerminateCancel;
}

- (void)showPanelWithServer:(NSString *)address connecting:(BOOL)connecting {
    _panel = [[LBConnectPanel alloc] init];
    _panel.delegate = self;
    [_panel showWithServer:address connecting:connecting];
}

- (IBAction)connect:(id)sender {
    if (_window && ![_window shouldClose]) return;
    [self closeLogbook];
    [self showPanelWithServer:nil connecting:NO];
}

- (IBAction)signOut:(id)sender {
    if (_window && ![_window shouldClose]) return;
    [LBConnectPanel signOut:_signIn];
    _signIn = nil;
    [self closeLogbook];
    [self showPanelWithServer:nil connecting:NO];
}

- (IBAction)showPreferences:(id)sender {
    if (!_window) return;
    if (!_preferences) _preferences = [[LBPreferencesController alloc] initWithLogbook:_window];
    [_preferences showWindow:sender];
}

- (void)showLists:(NSString *)tab {
    if (!_window) return;
    if (!_lists) _lists = [[LBListsController alloc] initWithLogbook:_window];
    [_lists showTab:tab];
}

- (IBAction)showExpenseKinds:(id)sender {
    [self showLists:@"expenseKinds"];
}

- (IBAction)showChecklists:(id)sender {
    [self showLists:@"checklists"];
}

- (IBAction)showExchangeRates:(id)sender {
    [self showLists:@"exchangeRates"];
}

/* The processes' open tasks (LBTasksWindowController.h). */
- (IBAction)showTasks:(id)sender {
    if (!_window) return;
    if (!_tasks) _tasks = [[LBTasksWindowController alloc] initWithStore:_store];
    [_tasks showWindow:sender];
}

- (IBAction)showStock:(id)sender {
    if (!_window) return;
    if (!_stock) _stock = [[LBStockWindowController alloc] initWithStore:_store];
    [_stock showWindow:sender];
}

/* Preferences and lists only while there is a logbook, whose user they
   are; updates while the updater can look for them. */
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (action == @selector(checkForUpdates:)) return _updater.canCheckForUpdates;
    BOOL needsLogbook = action == @selector(showPreferences:) || action == @selector(showExpenseKinds:) || action == @selector(showChecklists:)
                        || action == @selector(showExchangeRates:) || action == @selector(showStock:)
                        || action == @selector(showTasks:);
    return !needsLogbook || _window != nil;
}

- (void)closeLogbook {
    [_preferences close];
    _preferences = nil;
    [_lists close];
    _lists = nil;
    [_stock close];
    _stock = nil;
    [_tasks close];
    _tasks = nil;
    if (_store.local) [[NSNotificationCenter defaultCenter] removeObserver:self name:LBLocalStoreDidSyncNotification object:_store.local];
    _waitingTasks = nil;
    LBMainWindowController *window = _window;
    _window = nil;
    _store = nil;
    [window close];
}

/* Offline first: a sync done, the steps saved here that wait (Window >
   Tasks) are submitted, once the sync has said it is done. */
- (void)storeDidSync:(NSNotification *)note {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(submitWaiting) object:nil];
    [self performSelector:@selector(submitWaiting) withObject:nil afterDelay:0];
}

- (void)submitWaiting {
    LBAppState *state = _store.local.appState;
    if (_submittingWaiting || !state.pendingSubmissions.count) return;
    if (!_waitingTasks) _waitingTasks = [[LBTasks alloc] initWithServiceRoot:_store.serviceRoot signIn:_store.signIn];
    _submittingWaiting = YES;
    if ([_waitingTasks submitWaitingIn:state]) [_waitingTasks noteChange];
    _submittingWaiting = NO;
}

- (void)connectPanel:(LBConnectPanel *)panel didConnect:(ODataSignIn *)signIn {
    _signIn = signIn;
    /* Offline first: kept on this Mac, one store for each server (a
       self-test's, a new one of its own), synced with it. */
    NSURL *directory = LBSelfTestRoot
        ? [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString] isDirectory:YES]
        : [LBStore directoryForServiceRoot:signIn.serviceRoot];
    LBStore *store = [[LBStore alloc] initOfflineFirstWithServiceRoot:signIn.serviceRoot
                                                               signIn:signIn.kind == ODataSignInOpenID ? signIn : nil
                                                            directory:directory];
    NSError *error = nil;
    if (![store open:&error]) {
        /* A self-test has no one to answer the alert: it fails, and says why. */
        if (LBSelfTestRoot) {
            printf("FAIL the store opened: %s\nself-test done: 1 failed\n", error.localizedDescription.UTF8String ?: "");
            exit(1);
        }
        [[NSAlert alertWithError:error] runModal];
        [self showPanelWithServer:nil connecting:NO];
        return;
    }
    _store = store;
    if (store.local) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeDidSync:)
                                                                  name:LBLocalStoreDidSyncNotification object:store.local];
    /* What a user has not said (a currency, a time zone) taken from this
       Mac. */
    if ([store.user lbTakeDeviceSettings] && ![store save:&error]) NSLog(@"Logbook: the user's settings not kept: %@", error.localizedDescription);
    _window = [[LBMainWindowController alloc] initWithStore:store];
    [_window showWindow:nil];
    if (LBSelfTestRoot) LBRunSelfTest(_window);
}

@end
