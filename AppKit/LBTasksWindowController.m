#import "LBTasksWindowController.h"
#import "LBTasks.h"
#import "LBStore.h"
#import "LBStockOrderWindowController.h"
#import "LBStockProcedures.h"
#import "LBLocalStore.h"
#import "LBConflicts.h"

@implementation LBTasksWindowController {
    LBStore *_store;
    NSArray<LBTask *> *_openTasks;
    NSArray<LBPendingSubmission *> *_waiting;
    NSDateFormatter *_since;
}

- (instancetype)initWithStore:(LBStore *)store {
    if ((self = [super initWithWindowNibName:@"TasksWindow"])) {
        _store = store;
        _tasks = [[LBTasks alloc] initWithServiceRoot:store.serviceRoot signIn:store.signIn];
        _openTasks = @[];
        _waiting = @[];
        _since = [[NSDateFormatter alloc] init];
        _since.dateStyle = NSDateFormatterShortStyle;
        _since.timeStyle = NSDateFormatterShortStyle;
        /* Any tasks' change: this window's, an order window's, the steps
           waiting submitted after a sync. */
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tasksDidChange:)
                                                     name:LBTasksDidChangeNotification object:nil];
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

- (NSArray<LBPendingSubmission *> *)waiting {
    return _waiting;
}

/* Whether a step of the task waits. */
- (LBPendingSubmission *)waitingOf:(LBTask *)task {
    for (LBPendingSubmission *waiting in _waiting) {
        if ([waiting.formName isEqualToString:task.formName] && [waiting.businessKey isEqualToString:task.businessKey]) return waiting;
    }
    return nil;
}

- (IBAction)refresh:(id)sender {
    /* Asked first (the run loop turns meanwhile, the table drawn as it
       was), then both lists at once. A step waiting named by its task. */
    NSError *error = nil;
    NSArray *tasks = [_tasks openTasks:&error];
    [self willChangeValueForKey:@"waitingChosen"];
    _waiting = _store.local.appState.pendingSubmissions ?: @[];
    NSMutableArray *open = [NSMutableArray array];
    for (LBTask *task in tasks ?: @[]) {
        LBPendingSubmission *waiting = [self waitingOf:task];
        if (!waiting) [open addObject:task];
        else if (!waiting.taskName.length) [_store.local.appState noteSubmission:waiting task:task.name];
    }
    _openTasks = open;
    NSString *said = tasks ? (tasks.count || _waiting.count ? @"" : @"No task is open.") : (error.localizedDescription ?: @"");
    if (_waiting.count) {
        said = [said stringByAppendingFormat:@"%@%lu saved here, waiting to be submitted.", said.length ? @" " : @"", (unsigned long)_waiting.count];
    }
    self.messageLabel.stringValue = said;
    [self.table reloadData];
    [self didChangeValueForKey:@"waitingChosen"];
}

- (LBPendingSubmission *)chosenWaiting {
    NSInteger row = self.table.selectedRow - (NSInteger)_openTasks.count;
    return row >= 0 && row < (NSInteger)_waiting.count ? _waiting[(NSUInteger)row] : nil;
}

- (BOOL)waitingChosen {
    return [self chosenWaiting] != nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self willChangeValueForKey:@"waitingChosen"];
    [self didChangeValueForKey:@"waitingChosen"];
    LBPendingSubmission *waiting = [self chosenWaiting];
    if (waiting.lastError.length) self.messageLabel.stringValue = [@"Not submitted: " stringByAppendingString:waiting.lastError];
}

/* The order a task is about (its business key: a purchase's, a sale's),
   in the store's context. */
- (NSManagedObject *)orderOf:(LBTask *)task {
    return [self orderAbout:task.businessKey];
}

- (NSManagedObject *)orderAbout:(NSString *)businessKey {
    NSUUID *orderId = businessKey ? [[NSUUID alloc] initWithUUIDString:businessKey] : nil;
    if (!orderId) return nil;
    for (Class kind in @[ [PurchaseOrder class], [SaleOrder class] ]) {
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(kind)];
        fetch.predicate = [NSPredicate predicateWithFormat:@"id == %@", orderId];
        NSManagedObject *order = [[_store.context executeFetchRequest:fetch error:NULL] firstObject];
        if (order) return order;
    }
    return nil;
}

#pragma mark The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)(_openTasks.count + _waiting.count);
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSString *which = column.identifier;
    LBTask *task = row < (NSInteger)_openTasks.count ? _openTasks[(NSUInteger)row] : nil;
    LBPendingSubmission *waiting = task ? nil : _waiting[(NSUInteger)row - _openTasks.count];
    if ([which isEqualToString:@"task"]) {
        return task ? task.name : [NSString stringWithFormat:@"%@ — saved here, not submitted", waiting.taskName ?: waiting.formName];
    }
    NSDate *since = task ? task.createdAt : waiting.savedAt;
    if ([which isEqualToString:@"since"]) return since ? [_since stringFromDate:since] : @"";
    NSString *about = task ? task.businessKey : waiting.businessKey;
    NSManagedObject *order = [self orderAbout:about];
    if (!order) return about ?: @"";
    NSString *party = [[order valueForKey:[order isKindOfClass:[SaleOrder class]] ? @"customer" : @"supplier"] valueForKey:@"lbTitle"];
    NSString *number = [order valueForKey:@"lb_number"];
    return party.length ? [NSString stringWithFormat:@"%@, %@", number, party] : number;
}

#pragma mark Opening

- (IBAction)openTask:(id)sender {
    NSInteger row = self.table.clickedRow >= 0 ? self.table.clickedRow : self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)_openTasks.count) {
        NSBeep();
        return;
    }
    if (row >= (NSInteger)_openTasks.count + (NSInteger)_waiting.count) {
        NSBeep();
        return;
    }
    if (row >= (NSInteger)_openTasks.count) {
        LBPendingSubmission *waiting = _waiting[(NSUInteger)row - _openTasks.count];
        [self openOrderAbout:waiting.businessKey task:nil named:waiting.taskName ?: waiting.formName sender:sender];
        return;
    }
    LBTask *task = _openTasks[(NSUInteger)row];
    [self openOrderAbout:task.businessKey task:task named:task.name sender:sender];
}

- (void)openOrderAbout:(NSString *)businessKey task:(LBTask *)task named:(NSString *)name sender:(id)sender {
    NSManagedObject *order = [self orderAbout:businessKey];
    if (!order) {
        self.messageLabel.stringValue = [NSString stringWithFormat:@"%@: its order is not in the logbook.", name];
        return;
    }
    _orderWindow = [[LBStockOrderWindowController alloc] initWithStore:_store order:order];
    _orderWindow.task = task;
    _orderWindow.tasks = _tasks;
    [_orderWindow showWindow:sender];
}

#pragma mark The steps waiting

/* Sent now: synced first (the facts it saved at the server before its
   task is told). */
- (IBAction)submitWaiting:(id)sender {
    LBPendingSubmission *waiting = [self chosenWaiting];
    if (!waiting) {
        NSBeep();
        return;
    }
    NSError *error = nil;
    NSString *name = waiting.taskName ?: waiting.formName;
    if (![LBTasks hold:waiting]) {
        self.messageLabel.stringValue = [NSString stringWithFormat:@"%@: being submitted.", name];
        return;
    }
    NSManagedObjectID *held = waiting.objectID;
    if (![_store syncAndWait:&error]) {
        [LBTasks letGo:waiting];
        [_store.local.appState noteSubmission:waiting failed:@"The server cannot be reached."];
        [self refresh:nil];
        self.messageLabel.stringValue = [NSString stringWithFormat:@"%@: not submitted, the server cannot be reached.", name];
        return;
    }
    BOOL submitted = [_tasks submitWaiting:waiting in:_store.local.appState error:&error];
    [LBTasks letGo:(LBPendingSubmission *)[_store.local.appState.context objectWithID:held]];
    [self refresh:nil];
    self.messageLabel.stringValue = submitted ? [NSString stringWithFormat:@"%@: submitted.", name]
                                              : [NSString stringWithFormat:@"%@: not submitted: %@", name, error.localizedDescription ?: @""];
}

/* Forgotten, and its order opened for its task, where its step is done
   again (its form, as the order is now). */
- (IBAction)startAgain:(id)sender {
    LBPendingSubmission *waiting = [self chosenWaiting];
    if (!waiting) {
        NSBeep();
        return;
    }
    NSString *form = waiting.formName, *about = waiting.businessKey, *name = waiting.taskName ?: waiting.formName;
    [_store.local.appState removeSubmission:waiting];
    [self refresh:nil];
    LBTask *task = nil;
    for (LBTask *open in _openTasks) {
        if ([open.formName isEqualToString:form] && [open.businessKey isEqualToString:about]) task = open;
    }
    [self openOrderAbout:about task:task named:task.name ?: name sender:sender];
}

@end
