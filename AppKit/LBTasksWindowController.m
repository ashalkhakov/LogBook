#import "LBTasksWindowController.h"
#import "LBTasks.h"
#import "LBStore.h"
#import "LBStockOrderWindowController.h"
#import "LBStockProcedures.h"

@implementation LBTasksWindowController {
    LBStore *_store;
    NSArray<LBTask *> *_openTasks;
    NSDateFormatter *_since;
}

- (instancetype)initWithStore:(LBStore *)store {
    if ((self = [super initWithWindowNibName:@"TasksWindow"])) {
        _store = store;
        _tasks = [[LBTasks alloc] initWithServiceRoot:store.serviceRoot signIn:store.signIn];
        _openTasks = @[];
        _since = [[NSDateFormatter alloc] init];
        _since.dateStyle = NSDateFormatterShortStyle;
        _since.timeStyle = NSDateFormatterShortStyle;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tasksDidChange:)
                                                     name:LBTasksDidChangeNotification object:_tasks];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.table.target = self;
    self.table.doubleAction = @selector(openTask:);
    [self refresh:nil];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self refresh:nil];
}

- (void)tasksDidChange:(NSNotification *)notification {
    [self refresh:nil];
}

- (NSArray<LBTask *> *)openTasks {
    return _openTasks;
}

- (IBAction)refresh:(id)sender {
    NSError *error = nil;
    NSArray *tasks = [_tasks openTasks:&error];
    _openTasks = tasks ?: @[];
    self.messageLabel.stringValue = tasks ? (tasks.count ? @"" : @"No task is open.") : (error.localizedDescription ?: @"");
    [self.table reloadData];
}

/* The purchase order a task is about, in the store's context. */
- (PurchaseOrder *)orderOf:(LBTask *)task {
    NSUUID *orderId = task.businessKey ? [[NSUUID alloc] initWithUUIDString:task.businessKey] : nil;
    if (!orderId) return nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([PurchaseOrder class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"id == %@", orderId];
    return [[_store.context executeFetchRequest:fetch error:NULL] firstObject];
}

#pragma mark The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_openTasks.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    LBTask *task = _openTasks[(NSUInteger)row];
    NSString *which = column.identifier;
    if ([which isEqualToString:@"task"]) return task.name;
    if ([which isEqualToString:@"since"]) return task.createdAt ? [_since stringFromDate:task.createdAt] : @"";
    PurchaseOrder *order = [self orderOf:task];
    if (!order) return task.businessKey ?: @"";
    NSString *supplier = [order.supplier valueForKey:@"lbTitle"];
    return supplier.length ? [NSString stringWithFormat:@"%@, %@", order.lb_number, supplier] : order.lb_number;
}

#pragma mark Opening

- (IBAction)openTask:(id)sender {
    NSInteger row = self.table.clickedRow >= 0 ? self.table.clickedRow : self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)_openTasks.count) {
        NSBeep();
        return;
    }
    LBTask *task = _openTasks[(NSUInteger)row];
    PurchaseOrder *order = [self orderOf:task];
    if (!order) {
        self.messageLabel.stringValue = [NSString stringWithFormat:@"%@: its order is not in the logbook.", task.name];
        return;
    }
    _orderWindow = [[LBStockOrderWindowController alloc] initWithStore:_store order:order];
    _orderWindow.task = task;
    _orderWindow.tasks = _tasks;
    [_orderWindow showWindow:sender];
}

@end
