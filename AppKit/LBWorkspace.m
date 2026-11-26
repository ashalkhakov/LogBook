#import "LBWorkspace.h"
#import "LBMainWindowController.h"
#import "LBScreen.h"
#import "LBStore.h"
#import "LBLocalStore.h"
#import "LBDisplay.h"
#import "LBStockDisplay.h"
#import "LBStockProcedures.h"
#import "LBStockWindowController.h"
#import "LBCatalogSettingsWindowController.h"
#import "LBTasksWindowController.h"
#import "LBListsController.h"
#import "LBTiming.h"
#import "UDPaneSplitController.h"
#import "LBSelectors.h"

/* The least the logbook's page is given: its forms' fields keep their
   widths (as MainWindow.xib draws them). */
static const CGFloat LBLogbookWidth = 780, LBLogbookHeight = 680;

/* A row of the sidebar: a group's heading, or a place. Its key names the
   place (a vehicle's, a catalog's tab, Tasks, a list), the same across
   reloads, so that the same row is chosen again. */
@interface LBSidebarItem : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL group;
@property (nonatomic, copy) NSArray<LBSidebarItem *> *children;
// A vehicle's, a catalog's: in the window's context.
@property (nonatomic, strong, nullable) NSManagedObject *object;
// A catalog's tab (overview, items, ..., settings), a list's tab.
@property (nonatomic, copy, nullable) NSString *tab;
@end

@implementation LBSidebarItem
@end

static __weak LBWorkspace *LBCurrentWorkspace;
/* A catalog's tabs that are its settings' pages (LBCatalogSettingsWindowController). */
#define LBSettingsPages (@[ @"warehouses", @"contacts", @"categories", @"settings" ])
static void *LBVehiclesChanged = &LBVehiclesChanged;
static void *LBScreenTitled = &LBScreenTitled;

@implementation LBWorkspace {
    LBStockWindowController *_stock;
    LBTasksWindowController *_tasks;
    LBListsController *_lists;
    NSMutableArray<LBScreen *> *_kept;
    /* Back and Forward: each screen shown (NSNull: the logbook's page)
       with the sidebar's place it was shown for (NSNull: none). */
    NSMutableArray<NSArray *> *_history;
    NSInteger _at;
    /* The sidebar's rows by key, kept across reloads; the top ones. */
    NSMutableDictionary<NSString *, LBSidebarItem *> *_items;
    NSArray<LBSidebarItem *> *_groups;
    /* The place shown (a sidebar key); nil, none of the sidebar's. */
    NSString *_place;
    /* The sidebar chosen in code, not by the user. */
    BOOL _choosing;
    BOOL _loaded;
    /* The workspace itself choosing a screen's tab or catalog: not a
       change of place within the screen. */
    BOOL _navigating;
}

+ (LBWorkspace *)current {
    return LBCurrentWorkspace;
}

- (instancetype)init {
    if ((self = [super init])) {
        _kept = [NSMutableArray array];
        _history = [NSMutableArray array];
        _items = [NSMutableDictionary dictionary];
        _groups = @[];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_loaded) [_windowController.vehicles removeObserver:self forKeyPath:@"arrangedObjects" context:LBVehiclesChanged];
    if (_shownScreen) [_shownScreen removeObserver:self forKeyPath:@"title" context:LBScreenTitled];
}

- (NSWindow *)window {
    return _windowController.window;
}

- (NSArray<LBScreen *> *)keptScreens {
    return [_kept copy];
}

- (void)windowDidLoad {
    LBCurrentWorkspace = self;
    _loaded = YES;
    _paneSplit.flexiblePaneIndex = LBScreenPane;
    _paneSplit.minimumThicknesses = @[ @160, @(LBLogbookWidth), @200 ];
    _paneSplit.defaultThicknesses = @[ @220, @0, @260 ];
    NSString *autosave = @"LogbookWorkspacePanes";
    BOOL saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:[@"UDPaneSplitController " stringByAppendingString:autosave]] != nil;
    _paneSplit.autosaveName = autosave;
    [_paneSplit restoreLayout];
    /* The inspector, at first, hidden: it shows nothing yet. */
    if (!saved) [_paneSplit setPane:LBInspectorPane visible:NO];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(panesChanged:)
                                                 name:UDPaneSplitControllerDidChangeVisibilityNotification object:_paneSplit];
    /* The sidebar's catalogs, as stock changes and as syncs bring them. */
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stockDidChange:) name:LBStockDidChangeNotification
                                               object:nil];
    LBStore *store = _windowController.store;
    if (store.local) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stockDidChange:)
                                                                 name:LBLocalStoreDidSyncNotification object:store.local];
    [_windowController.vehicles addObserver:self forKeyPath:@"arrangedObjects" options:0 context:LBVehiclesChanged];
    _sidebar.target = self;
    [self reloadSidebar];
    for (LBSidebarItem *group in _groups) [_sidebar expandItem:group expandChildren:YES];
    [_history addObject:@[ [NSNull null], [NSNull null] ]];
    _at = 0;
    /* The first vehicle chosen, its page shown. */
    Vehicle *first = _windowController.chosenVehicle ?: [_windowController.vehicles.arrangedObjects firstObject];
    if (first) [self go:[self itemOfKey:[self keyOfVehicle:first]] recording:NO];
    else [self present:nil place:nil recording:NO asking:NO];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == LBVehiclesChanged) {
        /* Not in the change itself: once the controller is done. */
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadSidebar) object:nil];
        [self performSelector:@selector(reloadSidebar) withObject:nil afterDelay:0];
    } else if (context == LBScreenTitled) {
        [self showTitle];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)stockDidChange:(NSNotification *)note {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reloadSidebar) object:nil];
    [self performSelector:@selector(reloadSidebar) withObject:nil afterDelay:0];
}

#pragma mark The sidebar

- (NSString *)keyOfObject:(NSManagedObject *)object {
    return object.objectID.URIRepresentation.absoluteString ?: @"";
}

- (NSString *)keyOfVehicle:(Vehicle *)vehicle {
    return [@"vehicle " stringByAppendingString:[self keyOfObject:vehicle]];
}

- (LBSidebarItem *)itemOfKey:(NSString *)key {
    return key ? _items[key] : nil;
}

- (LBSidebarItem *)item:(NSString *)key title:(NSString *)title {
    LBSidebarItem *item = _items[key];
    if (!item) {
        item = [[LBSidebarItem alloc] init];
        item.key = key;
        _items[key] = item;
    }
    item.title = title;
    item.children = @[];
    return item;
}

- (LBSidebarItem *)group:(NSString *)key title:(NSString *)title children:(NSArray<LBSidebarItem *> *)children {
    LBSidebarItem *group = [self item:key title:title];
    group.group = YES;
    group.children = children;
    return group;
}

- (NSArray<Catalog *> *)catalogs {
    NSManagedObjectContext *context = _windowController.context;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Catalog class])];
    NSArray *found = [context executeFetchRequest:request error:NULL] ?: @[];
    return [found sortedArrayUsingDescriptors:_windowController.byTitle];
}

- (void)reloadSidebar {
    if (!_loaded) return;
    NSMutableArray<LBSidebarItem *> *vehicles = [NSMutableArray array];
    for (Vehicle *vehicle in _windowController.vehicles.arrangedObjects) {
        if (vehicle.isDeleted) continue;
        LBSidebarItem *item = [self item:[self keyOfVehicle:vehicle] title:vehicle.lbTitle.length ? vehicle.lbTitle : @"New Vehicle"];
        item.object = vehicle;
        [vehicles addObject:item];
    }
    NSMutableArray<LBSidebarItem *> *catalogs = [NSMutableArray array];
    NSArray<NSArray<NSString *> *> *tabs = @[ @[ @"overview", @"Overview" ], @[ @"items", @"Items" ], @[ @"purchaseOrders", @"Purchases" ],
                                              @[ @"saleOrders", @"Sales" ], @[ @"counts", @"Counts" ], @[ @"changes", @"Changelog" ],
                                              @[ @"warehouses", @"Warehouses" ], @[ @"contacts", @"Contacts" ],
                                              @[ @"categories", @"Categories" ], @[ @"settings", @"Settings" ] ];
    for (Catalog *catalog in [self catalogs]) {
        NSString *key = [@"catalog " stringByAppendingString:[self keyOfObject:catalog]];
        NSMutableArray<LBSidebarItem *> *pages = [NSMutableArray array];
        for (NSArray<NSString *> *tab in tabs) {
            LBSidebarItem *page = [self item:[NSString stringWithFormat:@"%@ %@", key, tab[0]] title:tab[1]];
            page.object = catalog;
            page.tab = tab[0];
            [pages addObject:page];
        }
        LBSidebarItem *item = [self item:key title:catalog.lbTitle];
        item.object = catalog;
        item.tab = @"overview";
        item.children = pages;
        [catalogs addObject:item];
    }
    LBSidebarItem *tasks = [self item:@"tasks" title:@"Tasks"];
    NSMutableArray<LBSidebarItem *> *lists = [NSMutableArray array];
    for (NSArray<NSString *> *list in @[ @[ @"expenseKinds", @"Expense Kinds" ], @[ @"checklists", @"Checklists" ],
                                         @[ @"exchangeRates", @"Exchange Rates" ] ]) {
        LBSidebarItem *item = [self item:[@"list " stringByAppendingString:list[0]] title:list[1]];
        item.tab = list[0];
        [lists addObject:item];
    }
    _groups = @[ [self group:@"vehicles" title:@"Vehicles" children:vehicles], [self group:@"stock" title:@"Stock" children:catalogs],
                 [self group:@"work" title:@"Work" children:@[ tasks ]], [self group:@"lists" title:@"Lists" children:lists] ];
    _choosing = YES;
    [_sidebar reloadData];
    for (LBSidebarItem *group in _groups) [_sidebar expandItem:group];
    [self showPlaceChosen];
    _choosing = NO;
    [self validateButtons];
}

/* The place shown chosen in the sidebar; none, where it is none of its. */
- (void)showPlaceChosen {
    LBSidebarItem *item = [self itemOfKey:_place];
    BOOL was = _choosing;
    _choosing = YES;
    /* A catalog's tab: the catalog opened, so that its row is there. */
    for (LBSidebarItem *catalog in [self itemOfKey:@"stock"].children) {
        if ([catalog.children containsObject:item]) [_sidebar expandItem:catalog];
    }
    NSInteger row = item ? [_sidebar rowForItem:item] : -1;
    if (row >= 0) [_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    else [_sidebar deselectAll:nil];
    _choosing = was;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (NSInteger)(item ? [(LBSidebarItem *)item children] : _groups).count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return (item ? [(LBSidebarItem *)item children] : _groups)[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [(LBSidebarItem *)item children].count > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item {
    LBSidebarItem *row = item;
    return row.group ? row.title.uppercaseString : row.title;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
    return [(LBSidebarItem *)item group];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    return ![(LBSidebarItem *)item group];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)column item:(id)item {
    return NO;
}

/* A group's heading small and grey, as a source list's. */
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column item:(id)item {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    BOOL group = [(LBSidebarItem *)item group];
    [cell setFont:group ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont systemFontSize]]];
    if (![cell isHighlighted]) [cell setTextColor:group ? [NSColor disabledControlTextColor] : [NSColor controlTextColor]];
}

/* LB_TIMING: a click on the sidebar, as it asks to change the choice and
   as it has. */
- (BOOL)selectionShouldChangeInOutlineView:(NSOutlineView *)outlineView {
    if (!_choosing) LBTimingNote(@"click asks to change the sidebar's choice (row %ld clicked)", (long)outlineView.clickedRow);
    return YES;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note {
    if (_choosing) return;
    LBTimingNote(@"the sidebar's choice changed: row %ld", (long)_sidebar.selectedRow);
    LBSidebarItem *item = _sidebar.selectedRow >= 0 ? [_sidebar itemAtRow:_sidebar.selectedRow] : nil;
    /* Not left (its user said Cancel): the place shown chosen again. */
    if (item && ![self go:item recording:YES]) [self showPlaceChosen];
    [self validateButtons];
}

/* The place of the sidebar's row shown. */
- (BOOL)go:(LBSidebarItem *)item recording:(BOOL)recording {
    if (!item || item.group) return NO;
    NSString *key = item.key;
    if ([key hasPrefix:@"vehicle "]) {
        if (![self mayLeaveFor:nil]) return NO;
        if (![_windowController.chosenVehicle isEqual:item.object]) _windowController.vehicles.selectedObjects = @[ item.object ];
        return [self present:nil place:key recording:recording asking:NO];
    }
    if ([key hasPrefix:@"catalog "] && [LBSettingsPages containsObject:item.tab]) {
        LBCatalogSettingsWindowController *settings = [self settingsOfCatalog:(Catalog *)item.object];
        if (![self mayLeaveFor:settings]) return NO;
        [settings view];
        [settings.tabs selectTabViewItemWithIdentifier:item.tab];
        return [self present:settings place:key recording:recording asking:NO];
    }
    if ([key hasPrefix:@"catalog "]) {
        LBStockWindowController *stock = self.stock;
        if (![self mayLeaveFor:stock]) return NO;
        [stock view];
        Catalog *catalog = [stock own:item.object];
        _navigating = YES;
        if (catalog && catalog != stock.catalog) stock.catalog = catalog;
        [stock.tabs selectTabViewItemWithIdentifier:item.tab];
        _navigating = NO;
        return [self present:stock place:key recording:recording asking:NO];
    }
    if ([key isEqualToString:@"tasks"]) return [self present:self.tasks place:key recording:recording asking:YES];
    if ([key hasPrefix:@"list "]) {
        LBListsController *lists = self.lists;
        if (![self mayLeaveFor:lists]) return NO;
        [lists view];
        [lists.tabs selectTabViewItemWithIdentifier:item.tab];
        return [self present:lists place:key recording:recording asking:NO];
    }
    return NO;
}

#pragma mark Screens

- (LBStockWindowController *)stock {
    if (!_stock) {
        _stock = [[LBStockWindowController alloc] initWithStore:_windowController.store];
        _stock.quiet = _windowController.quiet;
    }
    return _stock;
}

- (LBTasksWindowController *)tasks {
    if (!_tasks) _tasks = [[LBTasksWindowController alloc] initWithStore:_windowController.store];
    return _tasks;
}

- (LBListsController *)lists {
    if (!_lists) _lists = [[LBListsController alloc] initWithLogbook:_windowController];
    return _lists;
}

- (LBCatalogSettingsWindowController *)settingsOfCatalog:(Catalog *)catalog {
    for (LBScreen *screen in _kept) {
        if ([screen isKindOfClass:[LBCatalogSettingsWindowController class]]
            && [((LBCatalogSettingsWindowController *)screen).catalog.objectID isEqual:catalog.objectID]) {
            return (LBCatalogSettingsWindowController *)screen;
        }
    }
    return [[LBCatalogSettingsWindowController alloc] initWithStore:_windowController.store catalog:catalog];
}

- (BOOL)showStockTab:(NSString *)tab ofCatalog:(Catalog *)catalog {
    LBStockWindowController *stock = self.stock;
    if (![self mayLeaveFor:stock]) return NO;
    [stock view];
    _navigating = YES;
    if (catalog) stock.catalog = [stock own:catalog] ?: stock.catalog;
    if (tab) [stock.tabs selectTabViewItemWithIdentifier:tab];
    _navigating = NO;
    return [self present:stock place:[self placeOfStock] recording:YES asking:NO];
}

/* The sidebar's row of the stock's screen as it is: its catalog's tab. */
- (NSString *)placeOfStock {
    Catalog *catalog = _stock.catalog;
    NSString *tab = _stock.tabs.selectedTabViewItem.identifier;
    if (!catalog || !tab) return nil;
    return [NSString stringWithFormat:@"catalog %@ %@", [self keyOfObject:catalog], tab];
}

- (BOOL)showTasks {
    return [self present:self.tasks place:@"tasks" recording:YES asking:YES];
}

- (BOOL)showListsTab:(NSString *)tab {
    LBListsController *lists = self.lists;
    if (![self mayLeaveFor:lists]) return NO;
    [lists view];
    [lists.tabs selectTabViewItemWithIdentifier:tab];
    return [self present:lists place:[@"list " stringByAppendingString:tab] recording:YES asking:NO];
}

- (BOOL)showScreen:(LBScreen *)screen {
    return [self present:screen place:[self placeOfScreen:screen] recording:YES asking:YES];
}

/* The sidebar's row of a screen as it is (its tab chosen); nil, none of
   the sidebar's. */
- (NSString *)placeOfScreen:(LBScreen *)screen {
    if (screen == _stock) return [self placeOfStock];
    if (screen == _tasks) return @"tasks";
    if (screen == _lists) return [@"list " stringByAppendingString:_lists.tabs.selectedTabViewItem.identifier ?: @""];
    if ([screen isKindOfClass:[LBCatalogSettingsWindowController class]]) {
        LBCatalogSettingsWindowController *settings = (LBCatalogSettingsWindowController *)screen;
        Catalog *catalog = settings.catalog;
        if (!catalog) return nil;
        [settings view];
        return [NSString stringWithFormat:@"catalog %@ %@", [self keyOfObject:catalog], settings.tabs.selectedTabViewItem.identifier ?: @"settings"];
    }
    return nil;
}

- (BOOL)showLogbook {
    Vehicle *vehicle = _windowController.chosenVehicle;
    return [self present:nil place:vehicle ? [self keyOfVehicle:vehicle] : nil recording:YES asking:YES];
}

/* Whether the screen shown may be left for that one (nil: the logbook's
   page): its user asked about its changes. */
- (BOOL)mayLeaveFor:(LBScreen *)next {
    if (_shownScreen == next || !_shownScreen) return [_windowController commitEdits] || _shownScreen;
    return [_shownScreen shouldLeave];
}

/* The screen (nil: the logbook's page) put in the main pane for the
   sidebar's place (nil: none of its), kept, and recorded for Back. */
- (BOOL)present:(LBScreen *)screen place:(NSString *)place recording:(BOOL)recording asking:(BOOL)asking {
    if (asking && ![self mayLeaveFor:screen]) return NO;
    [self notePlaceLeft];
    if (screen != _shownScreen) {
        if (_shownScreen) {
            [_shownScreen removeObserver:self forKeyPath:@"title" context:LBScreenTitled];
            [_shownScreen.view removeFromSuperview];
        }
        _shownScreen = screen;
        if (screen) {
            NSView *view = screen.view;
            view.frame = _screenHost.bounds;
            view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [_screenHost addSubview:view];
            [screen addObserver:self forKeyPath:@"title" options:0 context:LBScreenTitled];
            if (![_kept containsObject:screen]) [_kept addObject:screen];
        }
    }
    _screenHost.hidden = screen == nil;
    _logbookPage.hidden = screen != nil;
    [self fitWindow];
    _place = [place copy];
    if (recording) {
        NSArray *entry = @[ screen ?: [NSNull null], place ?: [NSNull null] ];
        NSArray *now = _at >= 0 && _at < (NSInteger)_history.count ? _history[(NSUInteger)_at] : nil;
        if (![now isEqual:entry]) {
            if (_at + 1 < (NSInteger)_history.count) [_history removeObjectsInRange:NSMakeRange((NSUInteger)_at + 1, _history.count - (NSUInteger)_at - 1)];
            [_history addObject:entry];
            _at = (NSInteger)_history.count - 1;
        }
    }
    [self showPlaceChosen];
    [self showTitle];
    [self validateButtons];
    [self.window makeFirstResponder:nil];
    [screen screenDidShow];
    return YES;
}

- (void)screenChangedPlace:(LBScreen *)screen {
    if (_navigating || screen != _shownScreen || screen != _stock) return;
    NSString *place = [self placeOfStock];
    if (!place || [place isEqualToString:_place]) return;
    _place = place;
    [self notePlaceLeft];
    [self showPlaceChosen];
}

/* The place being left as it is now, for Back: the stock's tab, the
   lists' (chosen there, not only in the sidebar). */
- (void)notePlaceLeft {
    if (_at < 0 || _at >= (NSInteger)_history.count || _history[(NSUInteger)_at][0] != (id)_shownScreen || !_shownScreen) return;
    NSString *now = _shownScreen == _tasks ? nil : [self placeOfScreen:_shownScreen];
    if (now) _history[(NSUInteger)_at] = @[ _shownScreen, now ];
}

/* The window no smaller than the screen shown was drawn, with the sides
   shown beside it. */
- (void)fitWindow {
    NSWindow *window = self.window;
    if (!window) return;
    NSSize drawn = _shownScreen ? _shownScreen.drawnSize : NSZeroSize;
    CGFloat width = MAX(LBLogbookWidth, drawn.width), height = MAX(_shownScreen ? 400 : LBLogbookHeight, drawn.height);
    _paneSplit.minimumThicknesses = @[ @160, @(width), @200 ];
    for (NSNumber *pane in @[ @(LBSidebarPane), @(LBInspectorPane) ]) {
        if ([_paneSplit isPaneVisible:pane.integerValue]) width += [_paneSplit thicknessOfPane:pane.integerValue] + 1;
    }
    window.contentMinSize = NSMakeSize(width, height);
    NSSize now = [window.contentView frame].size;
    if (now.width < width || now.height < height) [window setContentSize:NSMakeSize(MAX(now.width, width), MAX(now.height, height))];
}

- (void)panesChanged:(NSNotification *)note {
    [self fitWindow];
}

- (void)showTitle {
    NSString *host = _windowController.store.serviceRoot.host ?: @"";
    NSString *title = _shownScreen.title;
    self.window.title = title.length ? [NSString stringWithFormat:@"%@ — %@", title, host] : [NSString stringWithFormat:@"Logbook — %@", host];
}

- (void)closeScreen:(LBScreen *)screen {
    if (![_kept containsObject:screen]) return;
    BOOL shown = screen == _shownScreen;
    NSUInteger before = 0;
    for (NSUInteger i = 0; i < _history.count && (NSInteger)i <= _at; i++) {
        if (_history[i][0] == screen) before++;
    }
    [_history filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray *entry, NSDictionary *bindings) {
                  return entry[0] != screen;
              }]];
    if (!_history.count) [_history addObject:@[ [NSNull null], [NSNull null] ]];
    _at = MIN(MAX(_at - (NSInteger)before, 0), (NSInteger)_history.count - 1);
    [_kept removeObject:screen];
    if (screen == _stock) _stock = nil;
    if (screen == _tasks) _tasks = nil;
    if (screen == _lists) _lists = nil;
    if (shown) {
        NSArray *entry = _history[(NSUInteger)_at];
        [self present:entry[0] == [NSNull null] ? nil : entry[0] place:entry[1] == [NSNull null] ? nil : entry[1] recording:NO asking:NO];
    }
}

- (BOOL)closeScreensAsking:(BOOL)asking {
    if (asking) {
        for (LBScreen *screen in [_kept copy]) {
            if (![screen shouldClose]) {
                if (screen != _shownScreen) [self present:screen place:nil recording:YES asking:NO];
                return NO;
            }
        }
    }
    for (LBScreen *screen in [_kept copy]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:LBScreenWillCloseNotification object:screen];
        [self closeScreen:screen];
    }
    if (LBCurrentWorkspace == self && !asking) LBCurrentWorkspace = nil;
    return YES;
}

#pragma mark Back and Forward

- (void)goTo:(NSInteger)at {
    if (at < 0 || at >= (NSInteger)_history.count) return;
    NSArray *entry = _history[(NSUInteger)at];
    LBScreen *screen = entry[0] == [NSNull null] ? nil : entry[0];
    NSString *place = entry[1] == [NSNull null] ? nil : entry[1];
    if (![self mayLeaveFor:screen]) return;
    /* The place as it was: the vehicle, the catalog's tab. */
    LBSidebarItem *item = [self itemOfKey:place];
    if (item && [place hasPrefix:@"vehicle "] && ![_windowController.chosenVehicle isEqual:item.object]) {
        _windowController.vehicles.selectedObjects = @[ item.object ];
    } else if (item && screen == _stock && item.tab) {
        Catalog *catalog = [_stock own:item.object];
        _navigating = YES;
        if (catalog && catalog != _stock.catalog) _stock.catalog = catalog;
        [_stock.tabs selectTabViewItemWithIdentifier:item.tab];
        _navigating = NO;
    } else if (item && screen == _lists && item.tab) {
        [_lists.tabs selectTabViewItemWithIdentifier:item.tab];
    } else if (item && [screen isKindOfClass:[LBCatalogSettingsWindowController class]] && item.tab) {
        [((LBCatalogSettingsWindowController *)screen).tabs selectTabViewItemWithIdentifier:item.tab];
    }
    if ([self present:screen place:place recording:NO asking:NO]) _at = at;
    [self validateButtons];
}

- (IBAction)goBack:(id)sender {
    [self goTo:_at - 1];
}

- (IBAction)goForward:(id)sender {
    [self goTo:_at + 1];
}

- (IBAction)toggleSidebarPane:(id)sender {
    [_paneSplit setPane:LBSidebarPane visible:![_paneSplit isPaneVisible:LBSidebarPane]];
}

- (IBAction)toggleInspectorPane:(id)sender {
    [_paneSplit setPane:LBInspectorPane visible:![_paneSplit isPaneVisible:LBInspectorPane]];
}

#pragma mark The sidebar's + and -

- (IBAction)newVehicle:(id)sender {
    if (![self mayLeaveFor:nil]) return;
    NSArrayController *vehicles = _windowController.vehicles;
    /* Added now (not at the end of the event, as -add: does): chosen, its
       page shown at its details. */
    [vehicles addObject:[vehicles newObject]];
    [self showNewVehicle];
}

- (void)showNewVehicle {
    [self reloadSidebar];
    Vehicle *vehicle = _windowController.chosenVehicle;
    LBSidebarItem *item = vehicle ? [self itemOfKey:[self keyOfVehicle:vehicle]] : nil;
    if (item) [self present:nil place:item.key recording:YES asking:NO];
    [_windowController showVehicleTab];
}

- (IBAction)newCatalog:(id)sender {
    LBStockWindowController *stock = self.stock;
    if (![self mayLeaveFor:stock]) return;
    [stock view];
    [stock newCatalog:sender];
    [self reloadSidebar];
}

- (IBAction)removeVehicle:(id)sender {
    Vehicle *vehicle = _windowController.chosenVehicle;
    if (!vehicle || _shownScreen) return;
    [_windowController.vehicles remove:sender];
    [self performSelector:@selector(showChosenVehicle) withObject:nil afterDelay:0];
}

- (void)showChosenVehicle {
    [self reloadSidebar];
    Vehicle *vehicle = _windowController.chosenVehicle;
    [self present:nil place:vehicle ? [self keyOfVehicle:vehicle] : nil recording:NO asking:NO];
}

- (void)validateButtons {
    _removeButton.enabled = !_shownScreen && [_place hasPrefix:@"vehicle "] && _windowController.vehicles.canRemove;
    for (NSToolbarItem *item in self.window.toolbar.items) {
        if (LBSameSelector(item.action, @selector(goBack:))) item.enabled = _at > 0;
        else if (LBSameSelector(item.action, @selector(goForward:))) item.enabled = _at + 1 < (NSInteger)_history.count;
    }
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    if (LBSameSelector(item.action, @selector(goBack:))) return _at > 0;
    if (LBSameSelector(item.action, @selector(goForward:))) return _at + 1 < (NSInteger)_history.count;
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (LBSameSelector(action, @selector(goBack:))) return _at > 0;
    if (LBSameSelector(action, @selector(goForward:))) return _at + 1 < (NSInteger)_history.count;
    if (LBSameSelector(action, @selector(toggleSidebarPane:))) {
        item.title = [_paneSplit isPaneVisible:LBSidebarPane] ? @"Hide Sidebar" : @"Show Sidebar";
    } else if (LBSameSelector(action, @selector(toggleInspectorPane:))) {
        item.title = [_paneSplit isPaneVisible:LBInspectorPane] ? @"Hide Inspector" : @"Show Inspector";
    } else if (LBSameSelector(action, @selector(removeVehicle:))) {
        return !_shownScreen && _windowController.vehicles.canRemove;
    }
    return YES;
}

@end
