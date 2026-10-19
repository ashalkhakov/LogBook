#import "LBAppController.h"
#import "LBStore.h"
#import "LBMainWindowController.h"
#import "LBSelfTest.h"

@implementation LBAppController {
    LBConnectPanel *_panel;
    ODataSignIn *_signIn;
    LBMainWindowController *_window;
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

- (void)closeLogbook {
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
        [[NSAlert alertWithError:error] runModal];
        [self showPanelWithServer:nil];
        return;
    }
    _store = store;
    _window = [[LBMainWindowController alloc] initWithStore:store];
    [_window showWindow:nil];
    if (LBSelfTestRoot) LBRunSelfTest(_window);
}

@end
