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
// The signed-in user's preferences (LBPreferencesController.h).
- (IBAction)showPreferences:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
