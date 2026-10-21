#import "LBAppController.h"
#import "LBStore.h"
#import "LBDisplay.h"
#import "LBMainWindowController.h"
#import "LBSelfTest.h"
#import "LBPreferencesController.h"
#import "LBListsController.h"

@implementation LBAppController {
    LBConnectPanel *_panel;
    ODataSignIn *_signIn;
    LBMainWindowController *_window;
    LBPreferencesController *_preferences;
    LBListsController *_lists;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self showPanelWithServer:LBSelfTestRoot.absoluteString];
}

/* The last window closed by the user: the app done. Connecting
   elsewhere closes one and opens the other in the same event, which is
   not the last closing. */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    return !_window || [_window shouldClose] ? NSTerminateNow : NSTerminateCancel;
}

- (void)showPanelWithServer:(NSString *)address {
    _panel = [[LBConnectPanel alloc] init];
    _panel.delegate = self;
    [_panel showWithServer:address];
}

- (IBAction)connect:(id)sender {
    if (_window && ![_window shouldClose]) return;
    [self closeLogbook];
    [self showPanelWithServer:nil];
}

- (IBAction)signOut:(id)sender {
    if (_window && ![_window shouldClose]) return;
    [_signIn signOut];
    [self closeLogbook];
    [self showPanelWithServer:nil];
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

/* Preferences and lists only while there is a logbook, whose user they
   are. */
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    BOOL needsLogbook = action == @selector(showPreferences:) || action == @selector(showExpenseKinds:) || action == @selector(showChecklists:)
                        || action == @selector(showExchangeRates:);
    return !needsLogbook || _window != nil;
}

- (void)closeLogbook {
    [_preferences close];
    _preferences = nil;
    [_lists close];
    _lists = nil;
    LBMainWindowController *window = _window;
    _window = nil;
    _store = nil;
    [window close];
}

- (void)connectPanel:(LBConnectPanel *)panel didConnect:(ODataSignIn *)signIn {
    _signIn = signIn;
    LBStore *store = [[LBStore alloc] initWithServiceRoot:signIn.serviceRoot signIn:signIn.kind == ODataSignInOpenID ? signIn : nil];
    NSError *error = nil;
    if (![store open:&error]) {
        /* A self-test has no one to answer the alert: it fails, and says why. */
        if (LBSelfTestRoot) {
            printf("FAIL the store opened: %s\nself-test done: 1 failed\n", error.localizedDescription.UTF8String ?: "");
            exit(1);
        }
        [[NSAlert alertWithError:error] runModal];
        [self showPanelWithServer:nil];
        return;
    }
    _store = store;
    /* A user who prefers no currency takes this Mac's: what their costs by
       month are reported in. */
    if ([store.user lbTakeLocaleCurrency] && ![store save:&error]) NSLog(@"Logbook: the currency not kept: %@", error.localizedDescription);
    _window = [[LBMainWindowController alloc] initWithStore:store];
    [_window showWindow:nil];
    if (LBSelfTestRoot) LBRunSelfTest(_window);
}

@end
