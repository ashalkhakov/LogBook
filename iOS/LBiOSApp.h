// Logbook on iOS: the app's delegate. Its window shows the sign-in until the
// server is known, then the logbook (LBMainViewController), or stock
// (LBStockTabBarController) when the user chose it last; its store is
// the device's own (LBLocalStore), synced as the app opens, comes back, saves
// and every minute.
//
//   Logbook --self-test <service root>    LBiOSSelfTest.h

#pragma once
#import <UIKit/UIKit.h>
#import "LBiOSControllers.h"
#import "LBStockControllers.h"

NS_ASSUME_NONNULL_BEGIN

// Defaults: what the app shows, "stock" or (none) the logbook.
FOUNDATION_EXPORT NSString * const LBModeDefaultsKey;     // @"LBMode"

@interface LBiOSAppDelegate : UIResponder <UIApplicationDelegate, LBSignInViewControllerDelegate>
@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, readonly, nullable) LBLocalStore *store;
@property (nonatomic, readonly, nullable) LBPhone *phone;
// Shown until signed in; nil after.
@property (nonatomic, readonly, nullable) LBSignInViewController *signInController;
@property (nonatomic, readonly, nullable) LBMainViewController *mainController;
// Stock, while it is shown in place of the logbook; nil otherwise.
@property (nonatomic, readonly, nullable) LBStockTabBarController *stockController;
// Stock shown in place of the logbook, and kept so across launches; the
// logbook shown again.
- (IBAction)showStock:(nullable id)sender;
- (IBAction)showLogbook:(nullable id)sender;
// Signed out: the tokens forgotten, this device's logbook deleted (it was
// the user's), the sign-in shown.
- (IBAction)signOut:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
