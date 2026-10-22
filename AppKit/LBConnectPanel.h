// Where the logbook is, and as whom (ConnectPanel.xib): the server's
// address, then signed in as it asks (LBSignIn.h): by a code entered in a
// browser, on any device (OpenID Connect's device flow), which the panel
// shows until the server lets the app in; or, a server that asks no one
// (to try it out), as the email the user gives, asked for once and kept
// (LBUser). The server it connected to is kept (LBServer), and offered next
// time.

#import <AppKit/AppKit.h>
#import <ODataSync/ODataSignIn.h>

@class LBConnectPanel;

NS_ASSUME_NONNULL_BEGIN

@protocol LBConnectPanelDelegate <NSObject>
// Connected: the server's root, signed in as it asks.
- (void)connectPanel:(LBConnectPanel *)panel didConnect:(ODataSignIn *)signIn;
@end

@interface LBConnectPanel : NSWindowController <ODataSignInDelegate>
@property (nonatomic, strong) IBOutlet NSTextField *serverField;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSTextField *codeLabel;
@property (nonatomic, strong) IBOutlet NSButton *openPageButton;
@property (nonatomic, strong) IBOutlet NSButton *connectButton;
// Who the user is, to a server that asks no one: shown only then.
@property (nonatomic, strong) IBOutlet NSTextField *emailLabel;
@property (nonatomic, strong) IBOutlet NSTextField *emailField;
@property (nonatomic, weak, nullable) id<LBConnectPanelDelegate> delegate;

// Shown, the address given (nil: the last one) and, when there is one,
// connected to at once.
- (void)showWithServer:(nullable NSString *)address;
- (IBAction)connect:(nullable id)sender;
- (IBAction)openPage:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
