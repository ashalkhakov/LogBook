#import "LBScreen.h"
#import "LBWorkspace.h"
#import "LBMainWindowController.h"

NSNotificationName const LBScreenWillCloseNotification = @"LBScreenWillCloseNotification";

@implementation LBScreen

static void *LBScreenTitleChanged = &LBScreenTitleChanged;

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTableViewSelectionDidChangeNotification object:nil];
    if (_titleKeyPath) [self removeObserver:self forKeyPath:_titleKeyPath context:LBScreenTitleChanged];
}

#pragma mark The inspector: the chosen row of a list

/* Whether its pages have one of that identifier. */
- (BOOL)hasInspectorPage:(NSString *)identifier {
    return identifier && [_inspectorPages indexOfTabViewItemWithIdentifier:identifier] != NSNotFound;
}

- (NSString *)inspectorPageForList:(NSTableView *)list {
    NSString *own = [@"row-" stringByAppendingString:list.identifier ?: @""];
    if ([self hasInspectorPage:own]) return own;
    /* Else its tab's page (an item's Suppliers, Stock's Items). */
    for (NSView *view = list.superview; view; view = view.superview) {
        if (![view isKindOfClass:[NSTabView class]]) continue;
        NSString *tab = ((NSTabView *)view).selectedTabViewItem.identifier;
        if ([self hasInspectorPage:tab]) return tab;
    }
    return nil;
}

/* The first list under the view (depth first) with a row chosen, of the
   screen's (not the inspector's own lists). */
static NSTableView *LBFirstChosenList(NSView *view, NSView *inspector) {
    if (view == inspector || view.isHidden) return nil;
    if ([view isKindOfClass:[NSTableView class]] && ((NSTableView *)view).selectedRow >= 0) return (NSTableView *)view;
    for (NSView *each in view.subviews) {
        NSTableView *found = LBFirstChosenList(each, inspector);
        if (found) return found;
    }
    return nil;
}

- (void)lb_listChosen:(NSNotification *)note {
    NSTableView *list = note.object;
    if (![list isKindOfClass:[NSTableView class]] || !self.isViewLoaded || ![list isDescendantOf:self.view]) return;
    /* Only a row the user chose (the list has the focus): a list choosing
       its first row as it reloads leaves the page as it is. */
    if (list.selectedRow < 0 || list.window.firstResponder != list) return;
    NSString *page = [self inspectorPageForList:list];
    if (page) [self showInspectorPage:page];
}

- (BOOL)inspectorHasChoice {
    return YES;
}

- (void)inspectorFollowTab:(NSTabViewItem *)item {
    /* The tab's own page (an item's Stock form, Stock's Items), else its
       first list's chosen row's. */
    if ([self hasInspectorPage:item.identifier]) return [self showInspectorPage:item.identifier];
    NSTableView *list = LBFirstChosenList(item.view, self.inspectorView);
    [self showInspectorPage:list ? [self inspectorPageForList:list] : nil];
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lb_listChosen:) name:NSTableViewSelectionDidChangeNotification
                                               object:nil];
    /* Its inspector's first page chosen (GNUstep chooses none in a view
       loaded outside a window). */
    if (_inspectorPages.numberOfTabViewItems && !_inspectorPages.selectedTabViewItem) [_inspectorPages selectTabViewItemAtIndex:0];
    /* A click in a list (its chosen row clicked again too) shows its row:
       each of its lists with no action of its own. */
    LBListsClickedTo(self.view, self, @selector(lb_listClicked:));
}

/* Each list under the view with no action set: the target's. */
void LBListsClickedTo(NSView *view, id target, SEL action) {
    NSTableView *list = [view isKindOfClass:[NSTableView class]] ? (NSTableView *)view : nil;
    if (list && !list.action && (!list.target || list.target == target)) {
        list.target = target;
        list.action = action;
    }
    for (NSView *each in view.subviews) LBListsClickedTo(each, target, action);
}

- (IBAction)lb_listClicked:(NSTableView *)list {
    if (![list isKindOfClass:[NSTableView class]] || list.selectedRow < 0) return;
    NSString *page = [self inspectorPageForList:list];
    if (page) [self showInspectorPage:page];
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

- (void)showInspectorPage:(NSString *)identifier {
    if ([self hasInspectorPage:identifier] && ![_inspectorPages.selectedTabViewItem.identifier isEqual:identifier]) {
        [_inspectorPages selectTabViewItemWithIdentifier:identifier];
    }
    if (self.isShown) [[LBWorkspace current].windowController showInspectorPage];
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
