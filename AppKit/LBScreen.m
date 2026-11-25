#import "LBScreen.h"
#import "LBWorkspace.h"

NSNotificationName const LBScreenWillCloseNotification = @"LBScreenWillCloseNotification";

@implementation LBScreen

- (void)dealloc {
    /* A title bound to its own (an item's name). */
    [self unbind:@"title"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _drawnSize = self.view.frame.size;
}

- (BOOL)isWindowLoaded {
    return self.isViewLoaded;
}

- (NSWindow *)window {
    return [LBWorkspace current].window;
}

- (BOOL)isShown {
    return [LBWorkspace current].shownScreen == self;
}

- (IBAction)showWindow:(id)sender {
    [[LBWorkspace current] showScreen:self];
}

- (void)close {
    [[NSNotificationCenter defaultCenter] postNotificationName:LBScreenWillCloseNotification object:self];
    [[LBWorkspace current] closeScreen:self];
}

- (BOOL)shouldLeave {
    return YES;
}

- (BOOL)shouldClose {
    return [self shouldLeave];
}

- (void)screenDidShow {
}

@end
