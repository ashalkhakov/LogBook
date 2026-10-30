// Logbook's updates. On macOS, Sparkle (LBUpdater-Apple.m): the newest
// release's appcast (SUFeedURL in AppKit/Info.plist, its updates signed
// with the key SUPublicEDKey names) checked once a day if the user allows
// it, and Logbook > Check for Updates… checks now. On GNUstep
// (LBUpdater-GNUstep.m), the stack's GSUpdater: on Windows WinSparkle; on
// Linux nothing, the AppImage carrying its own update information (for
// AppImageUpdate, Gear Lever and the like). Each build compiles its own.

#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LBUpdater : NSObject

// Started at once unless told not to: a self-test reaches no network.
- (instancetype)initStarting:(BOOL)start;
// Whether this system has an updater at all (Check for Updates… shown).
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) BOOL canCheckForUpdates;
- (IBAction)checkForUpdates:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
