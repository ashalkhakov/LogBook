#import "LBWorkflow.h"
#import <WorkflowKitOData/WFODataService.h>
#import "LogbookValidation.h"
#import "LBStockProcedures.h"
#import "Catalog+CoreDataClass.h"
#import "Warehouse+CoreDataClass.h"
#import "WarehouseStaff+CoreDataClass.h"

static NSError *LBWorkflowError(NSString *message) {
    return [NSError errorWithDomain:@"LBWorkflow" code:1 userInfo:@{ NSLocalizedDescriptionKey : message }];
}

/* A service task over the logbook's store: the order the process is of
   (its variable purchaseOrder, saleOrder), in a context of its own, done
   with by the block, and saved as the server saves (its rules first). */
@interface LBOrderTask : NSObject <WFActivityDelegate>
@property (nonatomic, strong) NSPersistentStoreCoordinator *coordinator;
@property (nonatomic) Class orderClass;
@property (nonatomic, copy) BOOL (^work)(id order, WFDelegateExecution *execution, NSError **error);
@end

@implementation LBOrderTask

- (BOOL)executeWithExecution:(WFDelegateExecution *)execution error:(NSError **)error {
    BOOL sale = _orderClass == [SaleOrder class];
    NSUUID *orderId = [[NSUUID alloc] initWithUUIDString:[[execution variableNamed:sale ? @"saleOrder" : @"purchaseOrder"] description] ?: @""];
    if (!orderId) {
        if (error) *error = LBWorkflowError(sale ? @"The process names no sale order." : @"The process names no purchase order.");
        return NO;
    }
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = self.coordinator;
    __block BOOL done = NO;
    __block NSError *failure = nil;
    [context performBlockAndWait:^{
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(self.orderClass)];
        fetch.predicate = [NSPredicate predicateWithFormat:@"id == %@", orderId];
        NSManagedObject *order = [[context executeFetchRequest:fetch error:&failure] firstObject];
        if (!order) {
            failure = failure ?: LBWorkflowError([NSString stringWithFormat:@"There is no %@ order %@.", sale ? @"sale" : @"purchase", orderId.UUIDString]);
            return;
        }
        done = self.work(order, execution, &failure)
            && (!context.hasChanges || ([context orm_prepareForSave:&failure] && [context save:&failure]));
    }];
    if (!done && error) *error = failure;
    return done;
}

@end

/* With no sign-in (the logbook tried out), everyone is a trial user who
   may work every task: as open as the logbook is then. */
@interface LBTrialAuthenticator : NSObject <HSAuthenticator>
@end

@implementation LBTrialAuthenticator
- (void)authenticateRequest:(HSRequest *)request reply:(HSAuthenticationReply *)reply {
    NSString *scopes = [@[ WFODataScopeWork, WFODataScopeReadAllTasks, WFODataScopeAssignTasks, WFODataScopeOperationsRead,
                           WFODataScopeReadAllDefinitions, WFODataScopeStartAny ] componentsJoinedByString:@" "];
    [reply finishWithPrincipal:[[HSPrincipal alloc] initWithSubject:@"trial" claims:@{ @"scope" : scopes }]];
}
@end

/* Signed in: who is asking, as the server's authenticator says, with what
   the logbook's permissions make them (Logbook.permissions.plist): the
   catalogs they manage (its owner, or a Manager of one of its warehouses)
   and those they keep (a manager, or a Keeper of one of its warehouses),
   their claims manager and keeper, which the processes' candidate groups
   name (manager:<catalog>); and the warehouses they keep (its Keeper or
   Manager, or its catalog's owner), keeperAt (keeperAt:<warehouse>). The task list is the logbook's to give:
   whoever is signed in may work theirs (Tasks.Work); which tasks are
   theirs, the claims say. */
@interface LBRolesAuthenticator : NSObject <HSAuthenticator>
- (instancetype)initWithAuthenticator:(id<HSAuthenticator>)inner coordinator:(NSPersistentStoreCoordinator *)coordinator;
@end

@implementation LBRolesAuthenticator {
    id<HSAuthenticator> _inner;
    NSPersistentStoreCoordinator *_coordinator;
}

- (instancetype)initWithAuthenticator:(id<HSAuthenticator>)inner coordinator:(NSPersistentStoreCoordinator *)coordinator {
    if ((self = [super init])) {
        _inner = inner;
        _coordinator = coordinator;
    }
    return self;
}

- (void)authenticateRequest:(HSRequest *)request reply:(HSAuthenticationReply *)reply {
    HSAuthenticationReply *asked = [[HSAuthenticationReply alloc] initWithTarget:self action:@selector(answered:)];
    asked.context = reply;
    [_inner authenticateRequest:request reply:asked];
}

- (NSString *)challengeForRequest:(HSRequest *)request {
    return [_inner respondsToSelector:@selector(challengeForRequest:)] ? [_inner challengeForRequest:request] : @"Bearer";
}

- (NSDictionary<NSString *, id> *)authorizationDescription {
    return [_inner respondsToSelector:@selector(authorizationDescription)] ? [_inner authorizationDescription] : nil;
}

- (void)answered:(HSAuthenticationReply *)asked {
    HSAuthenticationReply *reply = asked.context;
    if (asked.error) {
        [reply failWithError:asked.error];
        return;
    }
    HSPrincipal *principal = asked.principal;
    if (!principal) {
        [reply finishWithPrincipal:nil];
        return;
    }
    id email = principal.claims[@"email"];
    NSString *who = [email isKindOfClass:[NSString class]] && [email length] ? email : principal.subject;
    NSMutableOrderedSet *managed = [NSMutableOrderedSet orderedSet], *kept = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet *keptAt = [NSMutableOrderedSet orderedSet];
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = _coordinator;
    [context performBlockAndWait:^{
        NSFetchRequest *owned = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Catalog class])];
        owned.predicate = [NSPredicate predicateWithFormat:@"catalogOwner.email == %@", who];
        for (Catalog *catalog in [context executeFetchRequest:owned error:NULL]) {
            if (catalog.id) [managed addObject:catalog.id.UUIDString];
            for (Warehouse *warehouse in catalog.warehouses) {
                if (warehouse.id) [keptAt addObject:warehouse.id.UUIDString];
            }
        }
        NSFetchRequest *staff = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([WarehouseStaff class])];
        staff.predicate = [NSPredicate predicateWithFormat:@"user.email == %@", who];
        for (WarehouseStaff *member in [context executeFetchRequest:staff error:NULL]) {
            NSUUID *catalog = member.warehouse.catalog.id;
            if (!catalog) continue;
            if (member.warehouse.id && member.staffRole.length) [keptAt addObject:member.warehouse.id.UUIDString];
            if ([member.staffRole isEqualToString:@"Manager"]) [managed addObject:catalog.UUIDString];
            else if ([member.staffRole isEqualToString:@"Keeper"]) [kept addObject:catalog.UUIDString];
        }
    }];
    [kept unionOrderedSet:managed];
    NSMutableDictionary *claims = [principal.claims mutableCopy] ?: [NSMutableDictionary dictionary];
    claims[@"manager"] = managed.array;
    claims[@"keeper"] = kept.array;
    claims[@"keeperAt"] = keptAt.array;
    NSMutableSet *scopes = [principal.scopes mutableCopy];
    [scopes addObject:WFODataScopeWork];
    [claims removeObjectForKey:@"scp"];
    claims[@"scope"] = [scopes.allObjects componentsJoinedByString:@" "];
    [reply finishWithPrincipal:[[HSPrincipal alloc] initWithSubject:principal.subject claims:claims]];
}

@end

NSNotificationName const LBWorkflowDidSettleNotification = @"LBWorkflowDidSettle";

@implementation LBWorkflow {
    NSPersistentStoreCoordinator *_coordinator;
    /* The engine's work after the logbook's saves, one at a time. */
    dispatch_queue_t _queue;
}

/* A setting's file, beside the logbook's store or the server. */
static NSURL *LBWorkflowURL(HSConfiguration *c, NSString *setting, NSURL *beside, NSString *name) {
    id value = [c setting:setting];
    if ([value isKindOfClass:[NSString class]] && [value length]) {
        return [value containsString:@"://"] ? [NSURL URLWithString:value] : [NSURL fileURLWithPath:value];
    }
    return [beside URLByAppendingPathComponent:name];
}

- (instancetype)initWithConfiguration:(HSConfiguration *)c
                          coordinator:(NSPersistentStoreCoordinator *)coordinator
                       temporaryStore:(BOOL)temporary
                                error:(NSError **)error {
    if (!(self = [super init])) return nil;
    _coordinator = coordinator;
    _queue = dispatch_queue_create("logbook.workflow", DISPATCH_QUEUE_SERIAL);
    NSPersistentStore *logbook = coordinator.persistentStores.firstObject;
    NSURL *storeURL = logbook.URL;
    NSURL *beside = storeURL.isFileURL ? [storeURL URLByDeletingLastPathComponent]
                                       : [NSURL fileURLWithPath:[NSFileManager defaultManager].currentDirectoryPath];
    BOOL inMemory = temporary || [[c setting:@"Workflow"] isEqual:@"Temporary"];
    WFStore *store = inMemory ? [WFStore inMemoryStore:error]
                              : [WFStore SQLiteStoreAtURL:LBWorkflowURL(c, @"Workflow", beside, @"Workflow.sqlite") error:error];
    if (!store) return nil;
    _engine = [[WFProcessEngine alloc] initWithStore:store];
    [self registerTasks];
    if (![_engine openWithError:error]) return nil;
    NSURL *serverDirectory = [[NSURL fileURLWithPath:[NSProcessInfo processInfo].arguments.firstObject] URLByDeletingLastPathComponent];
    NSURL *processes = LBWorkflowURL(c, @"Processes", serverDirectory, @"Logbook.wfdeployment");
    WFBuiltDeployment *deployment = [WFBuiltDeployment deploymentWithContentsOfURL:processes error:error];
    if (!deployment || ![_engine.repositoryService deployBuiltDeployment:deployment error:error]) {
        if (error && !*error) *error = LBWorkflowError([NSString stringWithFormat:@"The processes at %@ are not deployed.", processes.path]);
        return nil;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(logbookDidSave:)
                                                 name:NSManagedObjectContextDidSaveNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* A save of the logbook's, done: a purchase order made a draft starts
   procure to receipt, a sale order made a draft order to cash (not a
   service's sale of its parts, shipped as it is saved), whoever saved it.
   Their people's tasks are done with their flows' forms (Purchasing,
   Selling): their submissions complete them (WorkflowKit's SubmitForm),
   not the facts they save. In the saving context's queue, as the
   notification is, what changed is read; the engine's work is done on its
   own queue, after the save. */
- (void)logbookDidSave:(NSNotification *)notification {
    NSManagedObjectContext *context = notification.object;
    if (context.persistentStoreCoordinator != _coordinator) return;
    NSMutableArray<NSArray<NSString *> *> *drafted = [NSMutableArray array];
    for (NSManagedObject *object in notification.userInfo[NSInsertedObjectsKey]) {
        /* A return asked for: received back, or sent back, by a keeper of
           its order's catalog. */
        if ([object isKindOfClass:[CustomerReturn class]] || [object isKindOfClass:[SupplierReturn class]]) {
            BOOL customer = [object isKindOfClass:[CustomerReturn class]];
            NSUUID *backId = [object valueForKey:@"id"];
            NSManagedObject *order = [object valueForKey:customer ? @"saleOrder" : @"purchaseOrder"];
            NSUUID *catalog = [[order valueForKey:@"catalog"] valueForKey:@"id"];
            if (backId && [[object valueForKey:@"returnState"] isEqual:@"Requested"]) {
                [drafted addObject:@[ customer ? @"customerReturn" : @"supplierReturn", customer ? @"customerReturn" : @"supplierReturn",
                                      backId.UUIDString, catalog.UUIDString ?: @"" ]];
            }
            continue;
        }
        /* A transfer asked for: moved by a keeper of where it goes from. */
        if ([object isKindOfClass:[StockTransfer class]]) {
            StockTransfer *transfer = (StockTransfer *)object;
            if (transfer.id && [transfer.transferState isEqualToString:@"Requested"]) {
                [drafted addObject:@[ @"transferStock", @"stockTransfer", transfer.id.UUIDString,
                                      transfer.transferFrom.warehouse.id.UUIDString ?: @"", @"fromWarehouse" ]];
            }
            continue;
        }
        /* A count taken: its review, by its catalog's managers. */
        if ([object isKindOfClass:[StockCount class]]) {
            StockCount *count = (StockCount *)object;
            if (count.id && [count.countState isEqualToString:@"Counted"]) {
                [drafted addObject:@[ @"countReview", @"stockCount", count.id.UUIDString, count.warehouse.catalog.id.UUIDString ?: @"" ]];
            }
            continue;
        }
        BOOL sale = [object isKindOfClass:[SaleOrder class]];
        if (!sale && ![object isKindOfClass:[PurchaseOrder class]]) continue;
        if (sale && (((SaleOrder *)object).serviceAsPartsSale || ((SaleOrder *)object).tyreChangeAsPartsSale)) continue;
        NSUUID *orderId = [object valueForKey:@"id"];
        NSString *state = [object valueForKey:@"orderState"];
        NSUUID *catalog = [[object valueForKey:@"catalog"] valueForKey:@"id"];
        if (orderId && (!state.length || [state isEqualToString:@"Draft"])) {
            [drafted addObject:@[ sale ? @"orderToCash" : @"procureToReceipt", sale ? @"saleOrder" : @"purchaseOrder", orderId.UUIDString,
                                  catalog.UUIDString ?: @"" ]];
        }
    }
    if (!drafted.count) return;
    dispatch_async(_queue, ^{
        for (NSArray<NSString *> *each in drafted) {
            NSString *orderId = each[2];
            NSError *error = nil;
            /* Its catalog, whose managers and keepers its tasks are offered to. */
            if (![self->_engine.runtimeService startProcessInstanceByKey:each[0] businessKey:orderId
                                                               variables:@{ each[1] : orderId, (each.count > 4 ? each[4] : @"catalog") : each[3] }
                                                                   error:&error]) {
                NSLog(@"Logbook: %@ not started for %@: %@", each[0], orderId, error.localizedDescription);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:LBWorkflowDidSettleNotification object:self];
        });
    });
}

- (void)registerTasks {
    LBOrderTask *received = [[LBOrderTask alloc] init];
    received.coordinator = _coordinator;
    received.orderClass = [PurchaseOrder class];
    received.work = ^BOOL(PurchaseOrder *order, WFDelegateExecution *execution, NSError **error) {
        return [execution setVariable:@"fullyReceived" value:@(order.isFullyReceived) error:error];
    };
    [_engine registerDelegate:received forName:@"orderReceived"];
    LBOrderTask *close = [[LBOrderTask alloc] init];
    close.coordinator = _coordinator;
    close.orderClass = [PurchaseOrder class];
    close.work = ^BOOL(PurchaseOrder *order, WFDelegateExecution *execution, NSError **error) {
        return [order lb_close:error];
    };
    [_engine registerDelegate:close forName:@"closeOrder"];
    LBOrderTask *shipped = [[LBOrderTask alloc] init];
    shipped.coordinator = _coordinator;
    shipped.orderClass = [SaleOrder class];
    shipped.work = ^BOOL(SaleOrder *order, WFDelegateExecution *execution, NSError **error) {
        return [execution setVariable:@"fullyShipped" value:@(order.isFullyShipped) error:error];
    };
    [_engine registerDelegate:shipped forName:@"orderShipped"];
    LBOrderTask *closeSale = [[LBOrderTask alloc] init];
    closeSale.coordinator = _coordinator;
    closeSale.orderClass = [SaleOrder class];
    closeSale.work = ^BOOL(SaleOrder *order, WFDelegateExecution *execution, NSError **error) {
        return [order lb_close:error];
    };
    [_engine registerDelegate:closeSale forName:@"closeSaleOrder"];
}

- (ODataService *)serviceAtRoot:(NSURL *)root signedIn:(BOOL)signedIn {
    ODataService *service = [WFODataService serviceForEngine:_engine serviceRoot:root];
    if (!signedIn) service.authenticator = [[LBTrialAuthenticator alloc] init];
    return service;
}

- (id<HSAuthenticator>)rolesAuthenticatorOver:(id<HSAuthenticator>)authenticator {
    return [[LBRolesAuthenticator alloc] initWithAuthenticator:authenticator coordinator:_coordinator];
}


@end
