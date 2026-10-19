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

/* The logbook's window closed by the user: the app done. Not the
   connect panel's closing, nor the window's when connecting elsewhere. */
- (void)windowWillClose:(NSNotification *)notification {
    if (_window && notification.object == _window.window) [NSApp terminate:nil];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowWillCloseNotification object:window.window];
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:)
                                                 name:NSWindowWillCloseNotification object:_window.window];
    if (LBSelfTestRoot) LBRunSelfTest(_window);
}

@end
