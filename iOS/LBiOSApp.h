// Logbook on iOS: the app's delegate. Its window shows the sign-in until the
// server is known, then the logbook (LBMainViewController); its store is
// the device's own (LBLocalStore), synced as the app opens, comes back, saves
// and every minute.
//
//   Logbook --self-test <service root>    LBiOSSelfTest.h

#pragma once
#import <UIKit/UIKit.h>
#import "LBiOSControllers.h"

NS_ASSUME_NONNULL_BEGIN

@interface LBiOSAppDelegate : UIResponder <UIApplicationDelegate, LBSignInViewControllerDelegate>
@property (nonatomic, strong, nullable) UIWindow *window;
@property (nonatomic, readonly, nullable) LBLocalStore *store;
@property (nonatomic, readonly, nullable) LBPhone *phone;
// Shown until signed in; nil after.
@property (nonatomic, readonly, nullable) LBSignInViewController *signInController;
@property (nonatomic, readonly, nullable) LBMainViewController *mainController;
// Signed out: the tokens forgotten, this device's logbook deleted (it was
// the user's), the sign-in shown.
- (IBAction)signOut:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
