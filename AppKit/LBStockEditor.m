#import "LBStockEditor.h"
#import "LBStore.h"
#import "LBLocalStore.h"
#import "LBStockProcedures.h"
#import "LBTasks.h"
#import "LBConflicts.h"
#import "LBFormValues.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>

/* Something being typed in the window, or in its sheet: a field's editor
   open. Read again then, its row or field would be taken from under it. */
static BOOL LBTyping(NSWindow *window) {
    for (NSWindow *each in @[ window ?: [NSNull null], window.attachedSheet ?: [NSNull null] ]) {
        if (![each isKindOfClass:[NSWindow class]]) continue;
        id responder = each.firstResponder;
        if ([responder isKindOfClass:[NSText class]] && [(NSText *)responder isFieldEditor]) return YES;
    }
    return NO;
}

NSNotificationName const LBStockDidChangeNotification = @"LBStockDidChangeNotification";
NSString *const LBStockCatalogKey = @"LBStockCatalog";

@implementation LBStockEditor

@synthesize task = _task, tasks = _tasks, waiting = _waiting;

- (instancetype)initWithStore:(LBStore *)store windowNibName:(NSString *)name {
    if ((self = [super initWithWindowNibName:name])) {
        _store = store;
        _context = [store newContext];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stockDidChange:) name:LBStockDidChangeNotification
                                                   object:nil];
        /* Offline first: what a sync brought down, read again. */
        if (store.local) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeDidSync:)
                                                                      name:LBLocalStoreDidSyncNotification object:store.local];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.delegate = (id<NSWindowDelegate>)self;
    [self readAgain];
}

- (User *)user {
    return [self own:_store.user];
}

- (id)own:(NSManagedObject *)object {
    if (!object) return nil;
    if (object.managedObjectContext == _context) return object;
    return [_context existingObjectWithID:object.objectID error:NULL];
}

- (NSArray<NSSortDescriptor *> *)byTitle {
    return @[ [NSSortDescriptor sortDescriptorWithKey:@"lbTitle" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)] ];
}

#pragma mark Reading

- (void)readAgain {
}

- (NSArray *)fetch:(Class)cls where:(NSPredicate *)predicate sortedBy:(NSArray<NSSortDescriptor *> *)order {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    request.predicate = predicate;
    NSError *error = nil;
    NSArray *found = [_context executeFetchRequest:request error:&error];
    if (!found) {
        [self reportError:error];
        return @[];
    }
    /* The fetch brought the server's rows: those already here are read
       from them again, as they fault. */
    for (NSManagedObject *object in found) {
        if (!object.isInserted) [_context refreshObject:object mergeChanges:object.hasChanges];
    }
    return order.count ? [found sortedArrayUsingDescriptors:order] : found;
}

- (void)stockDidChange:(NSNotification *)note {
    if (!self.isWindowLoaded) return;
    NSManagedObjectID *changed = note.userInfo[LBStockCatalogKey];
    if (!changed || !_catalog || [changed isEqual:_catalog.objectID]) [self storeDidSync:nil];
}

/* What a sync brought down, or another window saved, read again. */
- (void)storeDidSync:(NSNotification *)note {
    if (!self.isWindowLoaded) return;
    /* Not while the user types: once they are done. */
    if (LBTyping(self.window)) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(storeDidSync:) object:nil];
        return [self performSelector:@selector(storeDidSync:) withObject:nil afterDelay:1];
    }
    [self readAgain];
}

- (void)announce {
    NSDictionary *info = _catalog && !_catalog.objectID.isTemporaryID ? @{ LBStockCatalogKey: _catalog.objectID } : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:LBStockDidChangeNotification object:self userInfo:info];
}

#pragma mark Editing

- (NSArray<NSArrayController *> *)editedControllers {
    return @[];
}

- (BOOL)commitEdits {
    if (self.isWindowLoaded && ![self.window makeFirstResponder:nil]) return NO;
    for (NSArrayController *controller in [self editedControllers]) {
        if (![controller commitEditing]) return NO;
    }
    return YES;
}

/* An amount typed with no currency (an item's, a line's, a supplier's):
   the catalog's, else the user's. */
- (void)completeMoney {
    NSMutableSet *changed = [NSMutableSet setWithSet:_context.insertedObjects];
    [changed unionSet:_context.updatedObjects];
    NSString *currency = _catalog.currency ?: self.user.currency;
    for (NSManagedObject *object in changed) {
        if ([object isKindOfClass:[SaleLine class]]) {
            SaleLine *line = (SaleLine *)object;
            if (line.linePriceAmount && !line.linePriceCurrency) line.linePriceCurrency = currency;
        } else if ([object isKindOfClass:[PurchaseLine class]]) {
            PurchaseLine *line = (PurchaseLine *)object;
            if (line.lineUnitCostAmount && !line.lineUnitCostCurrency) line.lineUnitCostCurrency = currency;
        } else if ([object isKindOfClass:[SupplierItem class]]) {
            SupplierItem *bought = (SupplierItem *)object;
            if (bought.supplierCostAmount && !bought.supplierCostCurrency) bought.supplierCostCurrency = currency;
        } else if ([object isKindOfClass:[StockItem class]]) {
            StockItem *item = (StockItem *)object;
            if (item.priceAmount && !item.priceCurrency) item.priceCurrency = currency;
            if (item.unitCostAmount && !item.unitCostCurrency) item.unitCostCurrency = currency;
        }
    }
}

/* Saved, not yet said to the others. */
- (BOOL)saveHere {
    /* Nothing left to save (a form saved it): saved, what was refused
       before no longer so. */
    if (!_context.hasChanges) {
        _lastError = nil;
        return YES;
    }
    [self completeMoney];
    NSError *error = nil;
    if ([_store saveContext:_context error:&error]) {
        _lastError = nil;
        return YES;
    }
    [self reportError:error];
    return NO;
}

- (BOOL)saveChanges {
    if (![self commitEdits] || ![self saveHere]) return NO;
    [self announce];
    return YES;
}

- (id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(NSDictionary *)parameters {
    if (![self commitEdits] || ![self saveHere]) return nil;
    NSError *error = nil;
    /* Offline first, done here and saved here (then synced); online, the
       server's. */
    id result = [_store performAction:name on:object parameters:parameters error:&error];
    if (result && _store.local && ![_store saveContext:_context error:&error]) {
        [_context rollback];
        result = nil;
    }
    if (result) _lastError = nil;
    else [self reportError:error];
    [self announce];
    return result;
}

/* A save's refusal, each violation said, wherever it comes from (a save
   here, an action's save offline): Core Data's message names none. */
- (void)reportError:(NSError *)error {
    if (error.userInfo[NSDetailedErrorsKey] || error.userInfo[NSValidationKeyErrorKey]) {
        error = [NSError errorWithDomain:error.domain code:error.code
                                userInfo:@{ NSLocalizedDescriptionKey: @"The changes break the stock's rules",
                                            NSLocalizedRecoverySuggestionErrorKey: [[LBLocalStore sentencesOfError:error] componentsJoinedByString:@"\n"] }];
    }
    _lastError = error;
    if (error && !_quiet) [self presentError:error];
}

- (void)refuse:(NSString *)why {
    [self reportError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationErrorMinimum userInfo:@{ NSLocalizedDescriptionKey: why }]];
}

- (NSDecimalNumber *)typed:(NSString *)text {
    NSDecimalNumber *quantity = text.length ? [NSDecimalNumber decimalNumberWithString:text locale:[NSLocale currentLocale]] : nil;
    if (!quantity || quantity == [NSDecimalNumber notANumber]) {
        [self refuse:@"Say how many: a number."];
        return nil;
    }
    return quantity;
}

- (IBAction)save:(id)sender {
    [self saveChanges];
}

- (IBAction)revertChanges:(id)sender {
    if (self.isWindowLoaded) [self.window makeFirstResponder:nil];
    [_context rollback];
    [self readAgain];
}

- (BOOL)shouldClose {
    if (![self commitEdits]) return NO;
    if (!_context.hasChanges) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save the changes before closing?";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Don't Save"];
    NSModalResponse answer = [alert runModal];
    if (answer == NSAlertSecondButtonReturn) return NO;
    if (answer == NSAlertThirdButtonReturn) {
        [_context rollback];
        return YES;
    }
    return [self saveChanges];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    return [self shouldClose];
}

#pragma mark Its forms, and its tasks

- (NSString *)businessKey {
    return nil;
}

/* The model's form opened on the object as the context has it now, given
   what it comes with, saved as the store saves; its values as a view binds
   them (LBFormValues.h). nil, and why said, where it does not open. */
- (LBFormValues *)valuesOfForm:(NSString *)name given:(NSDictionary *)given object:(NSManagedObject *)object {
    NSError *error = nil;
    ORMForm *form = [ORMForm formNamed:name error:&error];
    ORMFormSession *session = form ? [[ORMFormSession alloc] initWithForm:form given:given] : nil;
    LBStore *store = self.store;
    if (session) [LBFormValues session:session useContext:self.context saving:^BOOL(NSManagedObjectContext *context, NSError **failure) {
        return [store saveContext:context error:failure];
    }];
    session.key = [[object valueForKey:@"id"] UUIDString];
    if (!session || ![session open:&error]) {
        [self reportError:error];
        return nil;
    }
    return [[LBFormValues alloc] initWithSession:session object:object];
}

/* What a save refused, said: under its controls where the view has them,
   the rest in the form's words. */
- (void)refuseForm:(LBFormValues *)values error:(NSError *)error under:(NSView *)view {
    /* What the store refused, each violation said (Core Data's own name
       the object and the property); else under the controls. */
    NSError *failure = error ?: [LBFormValues saveFailureOf:values.session];
    if (failure) return [self reportError:failure];
    NSArray<NSString *> *rest = [values showErrors:values.session.errors under:view];
    [self refuse:rest.count ? [rest componentsJoinedByString:@"\n"] : @"Not saved: see under its fields."];
}

/* A step's form saved, opened again on its object as it is now (what its
   sheet changed of it), then its instance submitted to the order's task
   of it where one is open: the process goes on with it. */
- (BOOL)submitForm:(LBFormValues *)values sheet:(NSWindow *)sheet {
    [sheet makeFirstResponder:nil];
    LBFormValues *now = [self valuesOfForm:values.session.form.name given:values.session.given object:values.object];
    NSError *error = nil;
    if (!now || ![now.session save:&error]) {
        if (now) [self refuseForm:now error:error under:sheet.contentView];
        return NO;
    }
    [self saveChanges];
    /* The server's tasks, where it has some: opened from Window > Tasks,
       those; from the stock's window, asked here. */
    if (!_tasks && self.store.serviceRoot) _tasks = [[LBTasks alloc] initWithServiceRoot:self.store.serviceRoot signIn:self.store.signIn];
    NSString *formName = now.session.form.name;
    NSString *about = self.businessKey;
    NSString *instance = [LBTasks instanceOf:now.session];
    /* What the form saved, at the server before its task is told: the
       process goes on with the facts. Offline first, where the server
       cannot be reached, the step waits, saved (Window > Tasks), and is
       submitted after a sync. */
    if (![self.store syncAndWait:&error]) {
        if (self.store.local) return [self wait:formName about:about instance:instance task:_task.name];
        [self reportError:error];
        return NO;
    }
    error = nil;
    LBTask *task = [_task.formName isEqualToString:formName] ? _task : [_tasks openTaskOfForm:formName about:about error:&error];
    if (!task && self.store.local && [LBTasks isUnreachable:error]) return [self wait:formName about:about instance:instance task:_task.name];
    if (error) [self reportError:error];
    if (task && ![_tasks submitInstance:instance toTask:task error:&error]) {
        if (self.store.local && [LBTasks isUnreachable:error]) return [self wait:formName about:about instance:instance task:task.name];
        [self reportError:error];
        return NO;
    }
    /* Submitted: one of it that waited is done with. */
    for (LBPendingSubmission *waiting in [self.store.local.appState pendingSubmissions]) {
        if (task && [waiting.formName isEqualToString:formName] && [waiting.businessKey isEqualToString:about]) [self.store.local.appState removeSubmission:waiting];
    }
    _waiting = nil;
    [self stepDone:formName];
    return YES;
}

/* The step saved here, waiting to be submitted (LBAppState): said, unless
   quiet. */
- (BOOL)wait:(NSString *)formName about:(NSString *)about instance:(NSString *)instance task:(NSString *)taskName {
    _waiting = [self.store.local.appState keepSubmissionOfForm:formName about:about taskName:taskName instance:instance];
    if (!self.quiet) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Saved here, not submitted yet";
        alert.informativeText = [NSString stringWithFormat:@"The server cannot be reached. %@ waits in Window > Tasks, and is submitted "
                                                           @"after the next sync.", taskName.length ? taskName : @"The step"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
    return YES;
}

/* The step of the form's done here: the title says it no more, and the
   tasks are asked again. */
- (void)stepDone:(NSString *)form {
    if (![_task.formName isEqualToString:form]) return;
    self.task = nil;
    [_tasks noteChange];
}

@end
