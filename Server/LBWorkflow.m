#import "LBWorkflow.h"
#import <WorkflowKitOData/WFODataService.h>
#import "LogbookValidation.h"
#import "LBStockProcedures.h"

static NSError *LBWorkflowError(NSString *message) {
    return [NSError errorWithDomain:@"LBWorkflow" code:1 userInfo:@{ NSLocalizedDescriptionKey : message }];
}

/* A service task over the logbook's store: the order the process is of, in
   a context of its own, done with by the block, and saved as the server
   saves (its rules first). */
@interface LBOrderTask : NSObject <WFActivityDelegate>
@property (nonatomic, strong) NSPersistentStoreCoordinator *coordinator;
@property (nonatomic, copy) BOOL (^work)(PurchaseOrder *order, WFDelegateExecution *execution, NSError **error);
@end

@implementation LBOrderTask

- (BOOL)executeWithExecution:(WFDelegateExecution *)execution error:(NSError **)error {
    NSUUID *orderId = [[NSUUID alloc] initWithUUIDString:[[execution variableNamed:@"purchaseOrder"] description] ?: @""];
    if (!orderId) {
        if (error) *error = LBWorkflowError(@"The process names no purchase order.");
        return NO;
    }
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = self.coordinator;
    __block BOOL done = NO;
    __block NSError *failure = nil;
    [context performBlockAndWait:^{
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([PurchaseOrder class])];
        fetch.predicate = [NSPredicate predicateWithFormat:@"id == %@", orderId];
        PurchaseOrder *order = [[context executeFetchRequest:fetch error:&failure] firstObject];
        if (!order) {
            failure = failure ?: LBWorkflowError([NSString stringWithFormat:@"There is no purchase order %@.", orderId.UUIDString]);
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

@implementation LBWorkflow {
    NSPersistentStoreCoordinator *_coordinator;
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
    NSURL *storeURL = coordinator.persistentStores.firstObject.URL;
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

/* A save of the logbook's, done: its new draft purchase orders start their
   processes. (In the saving context's queue, as the notification is.) */
- (void)logbookDidSave:(NSNotification *)notification {
    NSManagedObjectContext *context = notification.object;
    if (context.persistentStoreCoordinator != _coordinator) return;
    for (NSManagedObject *object in notification.userInfo[NSInsertedObjectsKey]) {
        if (![object isKindOfClass:[PurchaseOrder class]]) continue;
        PurchaseOrder *order = (PurchaseOrder *)object;
        if (!order.id || (order.orderState.length && ![order.orderState isEqualToString:@"Draft"])) continue;
        NSError *error = nil;
        if (![_engine.runtimeService startProcessInstanceByKey:@"procureToReceipt"
                                                   businessKey:order.id.UUIDString
                                                     variables:@{ @"purchaseOrder" : order.id.UUIDString }
                                                         error:&error]) {
            NSLog(@"Logbook: procure to receipt not started for %@: %@", order.id.UUIDString, error.localizedDescription);
        }
    }
}

- (void)registerTasks {
    LBOrderTask *received = [[LBOrderTask alloc] init];
    received.coordinator = _coordinator;
    received.work = ^BOOL(PurchaseOrder *order, WFDelegateExecution *execution, NSError **error) {
        return [execution setVariable:@"fullyReceived" value:@(order.isFullyReceived) error:error];
    };
    [_engine registerDelegate:received forName:@"orderReceived"];
    LBOrderTask *close = [[LBOrderTask alloc] init];
    close.coordinator = _coordinator;
    close.work = ^BOOL(PurchaseOrder *order, WFDelegateExecution *execution, NSError **error) {
        return [order lb_close:error];
    };
    [_engine registerDelegate:close forName:@"closeOrder"];
}

- (ODataService *)serviceAtRoot:(NSURL *)root signedIn:(BOOL)signedIn {
    ODataService *service = [WFODataService serviceForEngine:_engine serviceRoot:root];
    if (!signedIn) service.authenticator = [[LBTrialAuthenticator alloc] init];
    return service;
}


@end
