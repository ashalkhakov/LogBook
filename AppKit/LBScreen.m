#import "LBScreen.h"
#import "LBWorkspace.h"

NSNotificationName const LBScreenWillCloseNotification = @"LBScreenWillCloseNotification";

@implementation LBScreen

static void *LBScreenTitleChanged = &LBScreenTitleChanged;

- (void)dealloc {
    if (_titleKeyPath) [self removeObserver:self forKeyPath:_titleKeyPath context:LBScreenTitleChanged];
}

- (void)setTitleKeyPath:(NSString *)keyPath {
    if (_titleKeyPath) [self removeObserver:self forKeyPath:_titleKeyPath context:LBScreenTitleChanged];
    _titleKeyPath = [keyPath copy];
    if (_titleKeyPath) [self addObserver:self forKeyPath:_titleKeyPath options:NSKeyValueObservingOptionInitial context:LBScreenTitleChanged];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != LBScreenTitleChanged) return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    id value = [self valueForKeyPath:_titleKeyPath];
    NSString *title = [value isKindOfClass:[NSString class]] ? value : [value description];
    if (![self.title isEqual:title] && (title || self.title)) self.title = title;
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

- (BOOL)savable {
    return NO;
}

- (IBAction)save:(id)sender {
}

- (IBAction)revertChanges:(id)sender {
}

- (BOOL)shouldClose {
    return [self shouldLeave];
}

- (void)screenDidShow {
}

@end
