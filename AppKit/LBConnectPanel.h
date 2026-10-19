// Where the logbook is, and as whom (ConnectPanel.xib): the server's
// address, then signed in as it asks (LBSignIn.h): with no one, or by a
// code entered in a browser, on any device (OpenID Connect's device flow),
// which the panel shows until the server lets the app in.

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
@property (nonatomic, weak, nullable) id<LBConnectPanelDelegate> delegate;

// Shown, the address given (nil: the last one) and, when there is one,
// connected to at once.
- (void)showWithServer:(nullable NSString *)address;
- (IBAction)connect:(nullable id)sender;
- (IBAction)openPage:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
