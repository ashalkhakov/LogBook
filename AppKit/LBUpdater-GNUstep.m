#import "LBUpdater.h"
#import <GSUpdater/GSUpdater.h>

/* GNUstep: the stack's GSUpdater (LBUpdater.h), WinSparkle on Windows; on
   Linux nothing, the AppImage being updated from outside it. */
@implementation LBUpdater {
    GSUpdater *_updater;
}

- (instancetype)initStarting:(BOOL)start {
    if ((self = [super init])) _updater = [[GSUpdater alloc] initStarting:start];
    return self;
}

- (BOOL)available {
    return [_updater available];
}

- (BOOL)canCheckForUpdates {
    return [_updater canCheckForUpdates];
}

- (IBAction)checkForUpdates:(id)sender {
    [_updater checkForUpdates:sender];
}

@end
