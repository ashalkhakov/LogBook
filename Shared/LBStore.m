#import "LBStore.h"
#import <ODataIncrementalStore/ODataIncrementalStore.h>
#import <ODataIncrementalStore/ODataOperationCall.h>
#import "LogbookValidation.h"
#import "LBStockProcedures.h"
#import "LBLocalStore.h"
#import "LBLocalActions.h"
#import "User+CoreDataClass.h"

/* What a generated class says of an object's deontic rules. */
@protocol LBWarned <NSObject>
- (NSArray<NSError *> *)orm_deonticViolations;
@end

@implementation LBStore {
    NSPersistentStoreCoordinator *_coordinator;
    User *_user;
    NSURL *_directory;
}

+ (NSManagedObjectModel *)model {
    static NSManagedObjectModel *model;
    if (!model) {
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"Logbook" withExtension:@"momd"];
        model = url ? [[NSManagedObjectModel alloc] initWithContentsOfURL:url] : nil;
    }
    return model;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithServiceRoot:(NSURL *)serviceRoot signIn:(ODataSignIn *)signIn {
    if ((self = [super init])) {
        _serviceRoot = [serviceRoot copy];
        _signIn = signIn;
    }
    return self;
}

- (instancetype)initOfflineFirstWithServiceRoot:(NSURL *)serviceRoot signIn:(ODataSignIn *)signIn directory:(NSURL *)directory {
    if ((self = [self initWithServiceRoot:serviceRoot signIn:signIn])) _directory = [directory copy];
    return self;
}

+ (NSURL *)directoryForServiceRoot:(NSURL *)serviceRoot {
    NSString *name = [NSString stringWithFormat:@"%@-%@%@", serviceRoot.host ?: @"local", serviceRoot.port ?: @"",
                                                           [serviceRoot.path stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];
    return [[LBLocalStore defaultDirectory] URLByAppendingPathComponent:name isDirectory:YES];
}

- (BOOL)open:(NSError **)error {
    if (_directory) {
        _local = [[LBLocalStore alloc] initWithDirectory:_directory modelURL:nil error:error];
        if (!_local) return NO;
        _local.signIn = _signIn;
        _local.email = [self email];
        _local.serviceRoot = _serviceRoot;
        _local.syncInterval = 60;
        _context = _local.context;
        _context.undoManager = [[NSUndoManager alloc] init];
        /* What the server has, once, where it answers; else what was kept. */
        NSError *unsynced = nil;
        if (![_local syncAndWait:&unsynced]) NSLog(@"Logbook: working offline: %@", unsynced.localizedDescription);
        return YES;
    }
    NSManagedObjectModel *model = [LBStore model];
    if (!model) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                            userInfo:@{ NSLocalizedDescriptionKey: @"The app has no Logbook.momd" }];
        return NO;
    }
    [ODataIncrementalStore registerStore];
    _coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    /* New objects' keys are ours (LBIdentified): a save's inserts go in its
       change set, which the server checks whole. */
    NSMutableDictionary *options = [@{ ODataIncrementalStorePostOnObtainPermanentIDsOption: @NO } mutableCopy];
    if (_signIn) options[ODataIncrementalStoreCredentialProviderOption] = _signIn;
    if (![_coordinator addPersistentStoreWithType:[ODataIncrementalStore storeType] configuration:nil URL:_serviceRoot
                                          options:options error:error]) {
        _coordinator = nil;
        return NO;
    }
    _context = [self newContext];
    return YES;
}

- (NSManagedObjectContext *)newContext {
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    /* Offline first, the main one's child: saved into it, then as it is. */
    if (_local) context.parentContext = _context;
    else context.persistentStoreCoordinator = _coordinator;
    context.undoManager = [[NSUndoManager alloc] init];
    /* What the server stamps as it saves (the sync's bookkeeping: a
       version, a last change), and what it settles (a reminder an event
       closed), comes back newer than the context read it: kept, beside
       what the context changed, which goes over it. */
    context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    return context;
}

/* The email the logbook knows the user by: the sign-in's, else the LBUser
   default (a server with no sign-in, for trying it out). */
- (NSString *)email {
    NSString *named = _signIn.isSignedIn ? _signIn.userName : nil;
    return named.length ? named : [[NSUserDefaults standardUserDefaults] stringForKey:@"LBUser"];
}

- (User *)user {
    if (_local) return _local.user;
    if (_user || !_context) return _user;
    NSString *email = [self email];
    if (!email.length) return nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([User class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(email)), email];
    _user = [[_context executeFetchRequest:fetch error:NULL] firstObject];
    if (!_user) {
        _user = (User *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([User class]) inManagedObjectContext:_context];
        _user.email = email;
    }
    return _user;
}

- (BOOL)save:(NSError **)error {
    if (_local) return [_local save:error];
    return [self saveContext:_context error:error];
}

- (void)identifyInserted {
    for (NSManagedObject *object in _context.insertedObjects) {
        if ([object respondsToSelector:@selector(setId:)] && !((id<LBIdentified>)object).id) {
            ((id<LBIdentified>)object).id = [NSUUID UUID];
        }
    }
}

- (BOOL)saveContext:(NSManagedObjectContext *)context error:(NSError **)error {
    if (_local && context == _context) return [_local save:error];
    if (!context.hasChanges) return YES;
    for (NSManagedObject *object in context.insertedObjects) {
        if ([object respondsToSelector:@selector(setId:)] && !((id<LBIdentified>)object).id) {
            ((id<LBIdentified>)object).id = [NSUUID UUID];
        }
    }
    /* Offline first, a window's (a child of the main one): its new
       objects' IDs the store's before they go into the main one, so that
       another window finds them by them. */
    if (_local && context.insertedObjects.count && ![context obtainPermanentIDsForObjects:context.insertedObjects.allObjects error:error])
        return NO;
    if (![context lb_confirmChangedOrders:error] || ![context lb_completeShippedMoves:error] || ![context lb_holdMovedItems:error]
        || ![context orm_prepareForSave:error] || ![context save:error])
        return NO;
    /* Offline first, a window's: into the main one, then saved as it is. */
    return _local ? [_local save:error] : YES;
}

- (BOOL)syncAndWait:(NSError **)error {
    return _local ? [_local syncAndWait:error] : YES;
}

- (id)performAction:(NSString *)name on:(NSManagedObject *)object parameters:(NSDictionary *)parameters error:(NSError **)error {
    if (_local) {
        User *user = self.user;
        /* The user as the object's context has them (a window's child). */
        User *actor = user ? (User *)[object.managedObjectContext objectWithID:user.objectID] : nil;
        if (!actor) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError
                                                userInfo:@{ NSLocalizedDescriptionKey: @"No one is signed in to do that." }];
            return nil;
        }
        return [LBLocalActions performAction:name on:object parameters:parameters by:actor error:error];
    }
    ODataOperationCall *call = [ODataOperationCall callOfOperation:name onObject:object];
    call.parameters = parameters;
    return [call invoke:error];
}

- (NSArray<NSError *> *)warnings {
    if (_local) return [_local warnings];
    NSMutableArray *warnings = [NSMutableArray array];
    NSMutableSet *changed = [NSMutableSet setWithSet:_context.insertedObjects];
    [changed unionSet:_context.updatedObjects];
    for (NSManagedObject *object in changed) {
        if ([object respondsToSelector:@selector(orm_deonticViolations)]) {
            [warnings addObjectsFromArray:[(id<LBWarned>)object orm_deonticViolations]];
        }
    }
    return warnings;
}

@end
