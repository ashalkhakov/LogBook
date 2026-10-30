#import "LBConnectPanel.h"
#import "LBSignIn.h"
#import "LBSelfTest.h"

@implementation LBConnectPanel {
    ODataSignIn *_signIn;
    NSURL *_page;
}

- (instancetype)init {
    return [super initWithWindowNibName:@"ConnectPanel"];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self waiting:NO said:@"Its address, as whoever runs it gave it to you."];
}

- (void)showWithServer:(NSString *)address {
    [self window];
    _serverField.stringValue = address ?: [[NSUserDefaults standardUserDefaults] stringForKey:@"LBServer"] ?: @"";
    [self showWindow:nil];
    [self.window center];
    if (_serverField.stringValue.length) [self connect:nil];
}

/* Asking the server (or for the code), or waiting for the user. */
- (void)waiting:(BOOL)waiting said:(NSString *)status {
    _statusLabel.stringValue = status;
    _serverField.enabled = !waiting;
    _connectButton.enabled = !waiting;
    _codeLabel.hidden = YES;
    _openPageButton.hidden = YES;
    _emailLabel.hidden = YES;
    _emailField.hidden = YES;
}

/* A server that asks no one: who the user is, asked for. */
- (void)askForEmail {
    [self waiting:NO said:@"This server asks no one to sign in. Your email names you in the logbook, as the owner "
                          @"of your vehicles; this Mac keeps it."];
    _emailLabel.hidden = NO;
    _emailField.hidden = NO;
    [self.window makeFirstResponder:_emailField];
}

- (void)takeEmail {
    NSString *email = [_emailField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSRange at = [email rangeOfString:@"@"];
    if (at.location == NSNotFound || at.location == 0 || at.location + 1 == email.length) {
        [self askForEmail];
        _statusLabel.stringValue = @"That is not an email.";
        return;
    }
    LBSetDefault(@"LBUser", email);
    [self connected];
}

- (IBAction)connect:(id)sender {
    NSURL *root = LBServiceRootOf(_serverField.stringValue);
    if (![_emailField isHidden] && _signIn.kind == ODataSignInNone && [_signIn.serviceRoot isEqual:root]) {
        [self takeEmail];
        return;
    }
    if (!root) {
        [self waiting:NO said:@"That is not a server's address."];
        return;
    }
    [self waiting:YES said:[NSString stringWithFormat:@"Asking %@ how to sign in…", root.host]];
    _signIn = LBSignInTo(root);
    _signIn.delegate = self;
    [_signIn learn];
}

- (IBAction)openPage:(id)sender {
    if (_page) [[NSWorkspace sharedWorkspace] openURL:_page];
}

- (void)signInDidLearn:(ODataSignIn *)signIn {
    if (signIn.kind == ODataSignInOpenID && !signIn.isSignedIn) {
        [self waiting:YES said:@"Asking for a code to sign in with…"];
        [signIn begin];
        return;
    }
    if (signIn.kind == ODataSignInNone && ![[NSUserDefaults standardUserDefaults] stringForKey:@"LBUser"].length) {
        [self askForEmail];
        return;
    }
    [self connected];
}

- (void)signIn:(ODataSignIn *)signIn showCode:(NSString *)code page:(NSURL *)page completePage:(NSURL *)completePage {
    _page = completePage ?: page;
    _statusLabel.stringValue = [NSString stringWithFormat:@"Open %@ in a browser, on any device, and enter this code. "
                                                          @"The logbook opens once you have signed in.", page.absoluteString];
    _codeLabel.stringValue = code;
    _codeLabel.hidden = NO;
    _openPageButton.hidden = NO;
}

- (void)signInDidFinish:(ODataSignIn *)signIn {
    [self connected];
}

- (void)signIn:(ODataSignIn *)signIn didFail:(NSError *)error {
    [self waiting:NO said:error.localizedDescription];
}

- (void)connected {
    LBSetDefault(@"LBServer", _signIn.serviceRoot.absoluteString);
    /* The logbook's window open before this one closes: closed first, this
       would be the app's last window, and the app would quit. */
    [_delegate connectPanel:self didConnect:_signIn];
    [self close];
}

@end
