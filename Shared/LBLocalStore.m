#import "LBLocalStore.h"
#import "LogbookValidation.h"
#import "LBProcedures.h"
#import "LBStore.h"
#import "LBDisplay.h"
#import "User+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "Vehicle+CoreDataClass.h"

NSNotificationName const LBLocalStoreDidChangeNotification = @"LBLocalStoreDidChangeNotification";

NSDate *LBNow(void) {
    return [NSDate dateWithTimeIntervalSinceReferenceDate:floor([NSDate timeIntervalSinceReferenceDate])];
}

/* What a generated class says of an object's deontic rules. */
@protocol LBLocalWarned <NSObject>
- (NSArray<NSError *> *)orm_deonticViolations;
@end

/* What the sync's progress is said as, on the main thread. */
static NSString *LBCount(NSUInteger n) {
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    return [f stringFromNumber:@(n)] ?: [NSString stringWithFormat:@"%lu", (unsigned long)n];
}

@implementation LBLocalStore {
    NSPersistentStoreCoordinator *_coordinator;
    ODataSyncRemote *_remote;
    NSTimer *_timer;
    BOOL _syncAgain;
    /* A save of the store's own that waits for the next sync. */
    BOOL _savingQuietly;
    /* Changes refused in the sync running (told on the engine's thread),
       and whether this sync is the one sending them again. */
    NSUInteger _setAside;
    BOOL _retrying;
    BOOL _waitedFor;
    BOOL _lastOK;
    NSError *_lastFailure;
    User *_user;
    NSMutableSet<NSString *> *_accepted;
}

+ (NSURL *)defaultDirectory {
    NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [support URLByAppendingPathComponent:@"Logbook" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    return directory;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithDirectory:(NSURL *)directory modelURL:(NSURL *)modelURL error:(NSError **)error {
    if (!(self = [super init])) return nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *momd = modelURL ?: [[NSBundle mainBundle] URLForResource:@"Logbook" withExtension:@"momd"];
    if (!momd) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                            userInfo:@{ NSLocalizedDescriptionKey: @"The app has no Logbook.momd" }];
        return nil;
    }
    /* The model's own, its sync annotations with it (the .orm's mapping),
       and ODataSync's bookkeeping added. */
    NSManagedObjectModel *model = [ODataSyncEngine modelWithBookkeepingAtURL:momd configuration:nil error:error];
    if (!model) return nil;
    _coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    /* History: the outbox is read from it, so no change is missed. */
    NSDictionary *options = @{ NSPersistentHistoryTrackingKey: @YES, NSMigratePersistentStoresAutomaticallyOption: @YES,
                               NSInferMappingModelAutomaticallyOption: @YES };
    if (![_coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
                                              URL:[directory URLByAppendingPathComponent:@"Logbook.sqlite"]
                                          options:options error:error])
        return nil;
    _appState = [[LBAppState alloc] initWithStoreURL:[directory URLByAppendingPathComponent:@"AppState.sqlite"] error:error];
    if (!_appState) return nil;
    _context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    _context.persistentStoreCoordinator = _coordinator;
    /* What a sync brought meanwhile is kept beside what the context
       changed, which goes over it. */
    _context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    _engine = [[ODataSyncEngine alloc] initWithCoordinator:_coordinator];
    _engine.delegate = self;
    _engine.resolver = [[LBConflictResolver alloc] initWithAppState:_appState];
    _syncEnabled = YES;
    _status = @"Not synced yet.";
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#pragma mark The server

- (void)setServiceRoot:(NSURL *)serviceRoot {
    _serviceRoot = [serviceRoot copy];
    for (ODataSyncRemote *remote in _engine.remotes) [_engine removeRemote:remote];
    _remote = nil;
    if (_serviceRoot) {
        _remote = [ODataSyncRemote remoteWithServiceRoot:_serviceRoot];
        if (_signIn) _remote.configuration = _signIn.configuration;
        [_engine addRemote:_remote];
    }
}

- (void)setSignIn:(ODataSignIn *)signIn {
    _signIn = signIn;
    _user = nil;
    if (_remote && signIn) _remote.configuration = signIn.configuration;
}

- (void)setEmail:(NSString *)email {
    _email = [email copy];
    _user = nil;
}

- (void)setSyncEnabled:(BOOL)syncEnabled {
    _syncEnabled = syncEnabled;
    [self say:syncEnabled ? [self syncedStatus] : @"Sync is off: changes wait here."];
    if (syncEnabled && _serviceRoot) [self sync];
}

- (void)setSyncInterval:(NSTimeInterval)syncInterval {
    _syncInterval = syncInterval;
    [_timer invalidate];
    _timer = syncInterval > 0 ? [NSTimer scheduledTimerWithTimeInterval:syncInterval target:self selector:@selector(tick:)
                                                               userInfo:nil repeats:YES]
                              : nil;
}

- (void)tick:(NSTimer *)timer {
    [self sync];
}

- (void)say:(NSString *)status {
    _status = [status copy];
    [[NSNotificationCenter defaultCenter] postNotificationName:LBLocalStoreDidChangeNotification object:self
                                                      userInfo:@{ @"status": _status }];
}

- (NSUInteger)pendingCount {
    return _engine.pendingChanges.count;
}

- (NSUInteger)changesLostOnSignOut {
    return [self pendingCount] + [self pendingConflicts].count;
}

- (NSError *)lastSyncError {
    return _lastFailure;
}

- (NSArray<ODataSyncIssue *> *)issues {
    return _engine.issues;
}

- (NSString *)syncedStatus {
    if (!_lastSync) return @"Not synced yet.";
    NSDateFormatter *said = [[NSDateFormatter alloc] init];
    said.dateStyle = NSDateFormatterNoStyle;
    said.timeStyle = NSDateFormatterShortStyle;
    NSMutableString *status = [NSMutableString stringWithFormat:@"Synced %@.", [said stringFromDate:_lastSync]];
    NSUInteger waiting = [self pendingCount], refused = _engine.issues.count;
    if (waiting > refused) [status appendFormat:@" %lu change%@ waiting.", (unsigned long)(waiting - refused), waiting - refused == 1 ? @"" : @"s"];
    if (refused) [status appendFormat:@" %lu refused.", (unsigned long)refused];
    return status;
}

- (void)sync {
    if (!_serviceRoot || !_syncEnabled) return;
    if (_syncing) {
        _syncAgain = YES;
        return;
    }
    _syncing = YES;
    [self say:@"Syncing…"];
    [NSThread detachNewThreadSelector:@selector(runSync:) toTarget:self withObject:_engine];
}

/* On a thread of its own, as the engine wants; done told on the main
   thread through its run loop (no queue of the main thread's waited on). */
- (void)runSync:(ODataSyncEngine *)engine {
    @autoreleasepool {
        NSError *error = nil;
        BOOL ok = [engine syncWithError:&error];
        NSError *failure = ok ? nil : error ?: [NSError errorWithDomain:ODataSyncErrorDomain code:0
                                                              userInfo:@{ NSLocalizedDescriptionKey: @"The sync failed." }];
        [self performSelectorOnMainThread:@selector(syncDidFinish:) withObject:failure ?: [NSNull null] waitUntilDone:NO];
    }
}

/* On the main thread: the context's objects read again (keeping what it
   changed meanwhile), and said. */
- (void)syncDidFinish:(id)failure {
    NSError *error = [failure isKindOfClass:[NSError class]] ? failure : nil;
    _syncing = NO;
    _waitedFor = YES;
    _lastOK = error == nil;
    _lastFailure = error;
    for (NSManagedObject *object in _context.registeredObjects.allObjects) [_context refreshObject:object mergeChanges:YES];
    if (_user.isDeleted || _user.managedObjectContext == nil) _user = nil;
    if (error) {
        [self say:[NSString stringWithFormat:@"Not synced: %@ Changes wait here.", error.localizedDescription ?: @"no answer."]];
    } else {
        _lastSync = [NSDate date];
        [self say:[self syncedStatus]];
        /* A user who prefers no currency takes this phone's, once the
           server's say has come down: what their costs by month are
           reported in. It waits for the next sync, as a sync of its own
           would still be going when the user next saves. */
        NSError *saveError = nil;
        _savingQuietly = YES;
        if ([[self user] lbTakeLocaleCurrency] && ![self save:&saveError]) NSLog(@"Logbook: the currency not kept: %@", saveError.localizedDescription);
        _savingQuietly = NO;
    }
    /* A change refused while what came with it was still on its way (a
       reminder's next, sent before the reminder it follows was closed
       there): sent again, once, after the rest. What is refused for good
       stays refused. */
    NSUInteger setAside;
    @synchronized (self) {
        setAside = _setAside;
        _setAside = 0;
    }
    if (!error && setAside && !_retrying) {
        _retrying = YES;
        for (ODataSyncIssue *issue in _engine.issues) [_engine retryIssue:issue];
        _syncAgain = NO;
        [self sync];
        return;
    }
    _retrying = NO;
    if (_syncAgain) {
        _syncAgain = NO;
        [self sync];
    }
}

- (BOOL)syncAndWait:(NSError **)error {
    if (!_serviceRoot) return NO;
    while (_syncing) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    BOOL enabled = _syncEnabled;
    _syncEnabled = YES;
    _waitedFor = NO;
    [self sync];
    _syncEnabled = enabled;
    while (!_waitedFor || _syncing || _retrying) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    if (error) *error = _lastFailure;
    return _lastOK;
}

- (void)syncNow {
    BOOL enabled = _syncEnabled;
    _syncEnabled = YES;
    [self sync];
    _syncEnabled = enabled;
}

/* How far it is: told on the engine's thread, said on the main one. */
- (void)syncEngine:(ODataSyncEngine *)engine didProgress:(ODataSyncProgress *)progress {
    NSString *what = nil;
    if (progress.phase == ODataSyncPhaseReceiving && progress.completed)
        what = [NSString stringWithFormat:@"Receiving changes: %@ so far…", LBCount(progress.completed)];
    else if (progress.phase == ODataSyncPhaseSending && progress.total)
        what = [NSString stringWithFormat:@"Sending %@ of %@ changes…", LBCount(progress.completed), LBCount(progress.total)];
    if (what) [self performSelectorOnMainThread:@selector(sayWhileSyncing:) withObject:what waitUntilDone:NO];
}

- (void)syncEngine:(ODataSyncEngine *)engine didSetAside:(ODataSyncIssue *)issue {
    @synchronized (self) {
        _setAside++;
    }
}

- (void)sayWhileSyncing:(NSString *)what {
    if (_syncing) [self say:what];
}

#pragma mark The logbook

/* The email the logbook knows the user by: the sign-in's, else the one
   given (a server that asks for no one). */
- (NSString *)userEmail {
    NSString *named = _signIn.isSignedIn ? _signIn.userName : nil;
    return named.length ? named : _email;
}

- (User *)user {
    if (_user && !_user.isDeleted && _user.managedObjectContext) return _user;
    NSString *email = [[self userEmail] lowercaseString];
    if (!email.length) return nil;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([User class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K ==[c] %@", NSStringFromSelector(@selector(email)), email];
    _user = [[_context executeFetchRequest:fetch error:NULL] firstObject];
    if (!_user) {
        _user = (User *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([User class]) inManagedObjectContext:_context];
        _user.email = email;
    }
    return _user;
}

- (BOOL)save:(NSError **)error {
    if (!_context.hasChanges) return YES;
    for (NSManagedObject *object in _context.insertedObjects) {
        if ([object respondsToSelector:@selector(setId:)] && !((id<LBIdentified>)object).id) {
            ((id<LBIdentified>)object).id = [NSUUID UUID];
        }
    }
    /* What the server does before it saves: the same procedures, the same
       rules. */
    if (![_context lb_completeRemindersOfChangedEvents:error] || ![_context orm_prepareForSave:error] || ![_context save:error]) {
        return NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:LBLocalStoreDidChangeNotification object:self
                                                      userInfo:@{ @"status": _status ?: @"" }];
    if (_serviceRoot && _syncEnabled && !_savingQuietly) {
        /* Once for saves close together. */
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sync) object:nil];
        [self performSelector:@selector(sync) withObject:nil afterDelay:2];
    }
    return YES;
}

- (NSArray<NSError *> *)warnings {
    NSMutableArray *warnings = [NSMutableArray array];
    NSMutableSet *changed = [NSMutableSet setWithSet:_context.insertedObjects];
    [changed unionSet:_context.updatedObjects];
    /* A rule over a vehicle's records (the meter goes up) may say so of
       another of them than the one changed: each asked. */
    for (NSManagedObject *object in [changed allObjects]) {
        if ([object isKindOfClass:[Record class]] && ((Record *)object).vehicle) [changed unionSet:((Record *)object).vehicle.records];
    }
    NSMutableSet *said = [NSMutableSet setWithSet:_accepted ?: [NSSet set]];
    for (NSManagedObject *object in changed) {
        if (object.isDeleted) continue;
        if ([object respondsToSelector:@selector(orm_deonticViolations)]) {
            for (NSError *warning in [(id<LBLocalWarned>)object orm_deonticViolations]) {
                if ([said containsObject:warning.localizedDescription ?: @""]) continue;
                [said addObject:warning.localizedDescription ?: @""];
                [warnings addObject:warning];
            }
        }
    }
    return warnings;
}

static void LBFlattenInto(NSError *error, NSMutableArray<NSString *> *into) {
    NSArray *each = error.userInfo[NSDetailedErrorsKey];
    if (!each.count) {
        if (error.localizedDescription.length && ![into containsObject:error.localizedDescription]) [into addObject:error.localizedDescription];
        return;
    }
    for (NSError *e in each) LBFlattenInto(e, into);
}

- (void)acceptWarnings:(NSArray<NSError *> *)warnings {
    if (!_accepted) _accepted = [NSMutableSet set];
    for (NSError *warning in warnings) [_accepted addObject:warning.localizedDescription ?: @""];
}

+ (NSArray<NSString *> *)sentencesOfError:(NSError *)error {
    NSMutableArray *sentences = [NSMutableArray array];
    if (error) LBFlattenInto(error, sentences);
    return sentences;
}

#pragma mark Conflicts

- (NSArray<LBPendingConflict *> *)pendingConflicts {
    return [_appState pendingConflicts];
}

/* The object of an entity whose key is these values; nil: none. */
- (NSManagedObject *)objectOfEntity:(NSString *)name key:(NSDictionary *)key {
    NSEntityDescription *entity = _coordinator.managedObjectModel.entitiesByName[name];
    if (!entity || !key.count) return nil;
    NSMutableArray *conditions = [NSMutableArray array];
    for (NSString *attribute in key) {
        id value = key[attribute];
        [conditions addObject:value == [NSNull null] ? [NSPredicate predicateWithFormat:@"%K == nil", attribute]
                                                     : [NSPredicate predicateWithFormat:@"%K == %@", attribute, value]];
    }
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:name];
    fetch.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:conditions];
    return [[_context executeFetchRequest:fetch error:NULL] firstObject];
}

- (NSManagedObject *)objectOfConflict:(LBPendingConflict *)conflict {
    return [self objectOfEntity:conflict.objectEntityName key:conflict.key];
}

- (void)keepTheirs:(LBPendingConflict *)conflict {
    [_appState removeConflict:conflict];
    [self say:_status];
}

- (void)settleConflict:(LBPendingConflict *)conflict {
    [_appState removeConflict:conflict];
    [self say:_status];
}

/* A value of a conflict's onto the object: an attribute's as it is, a
   to-one's the object its key names. */
- (void)setValue:(id)value named:(NSString *)name of:(NSManagedObject *)object {
    NSPropertyDescription *property = object.entity.propertiesByName[name];
    if ([property isKindOfClass:[NSRelationshipDescription class]]) {
        NSRelationshipDescription *relationship = (NSRelationshipDescription *)property;
        if (relationship.isToMany) return;
        NSManagedObject *related = [value isKindOfClass:[NSDictionary class]]
            ? [self objectOfEntity:relationship.destinationEntity.name key:value] : nil;
        [object setValue:related forKey:name];
    } else if ([property isKindOfClass:[NSAttributeDescription class]]) {
        [object setValue:value == [NSNull null] ? nil : value forKey:name];
    }
}

- (BOOL)keepMine:(LBPendingConflict *)conflict error:(NSError **)error {
    NSManagedObject *object = [self objectOfConflict:conflict];
    if (conflict.deletedHere) {
        if (object) [_context deleteObject:object];
    } else {
        if (!object) {
            if (!conflict.deletedThere) return YES;
            object = [NSEntityDescription insertNewObjectForEntityForName:conflict.objectEntityName inManagedObjectContext:_context];
            NSDictionary *key = conflict.key;
            for (NSString *name in key) [self setValue:key[name] named:name of:object];
        }
        NSDictionary *mine = conflict.mine;
        for (NSString *name in mine) [self setValue:mine[name] named:name of:object];
    }
    if (![self save:error]) {
        [_context rollback];
        return NO;
    }
    [_appState removeConflict:conflict];
    [self say:_status];
    return YES;
}

- (NSString *)textOfValue:(id)value property:(NSString *)name ofConflict:(LBPendingConflict *)conflict {
    if (!value || value == [NSNull null]) return @"none";
    if ([value isKindOfClass:[NSDate class]]) {
        NSDateFormatter *said = [[NSDateFormatter alloc] init];
        said.dateStyle = NSDateFormatterMediumStyle;
        said.timeStyle = NSDateFormatterShortStyle;
        return [said stringFromDate:value];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        NSNumberFormatter *number = [[NSNumberFormatter alloc] init];
        number.numberStyle = NSNumberFormatterDecimalStyle;
        number.maximumFractionDigits = 3;
        return [number stringFromNumber:value] ?: [value description];
    }
    if ([value isKindOfClass:[NSUUID class]]) return [value UUIDString];
    if ([value isKindOfClass:[NSData class]])
        return [NSString stringWithFormat:@"a file of %lu KB", (unsigned long)(([value length] + 1023) / 1024)];
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSEntityDescription *entity = _coordinator.managedObjectModel.entitiesByName[conflict.objectEntityName];
        NSRelationshipDescription *relationship = entity.relationshipsByName[name];
        NSManagedObject *related = relationship ? [self objectOfEntity:relationship.destinationEntity.name key:value] : nil;
        if ([related respondsToSelector:@selector(lbTitle)]) return [(id<LBTitled>)related lbTitle];
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *part in [[value allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            id v = value[part];
            [parts addObject:[v isKindOfClass:[NSUUID class]] ? [v UUIDString] : [v description]];
        }
        return [parts componentsJoinedByString:@", "];
    }
    return [value description];
}

#pragma mark Attachments

- (Attachment *)attachImage:(NSData *)jpeg toRecord:(Record *)record {
    Attachment *attachment = (Attachment *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Attachment class])
                                                                         inManagedObjectContext:_context];
    attachment.id = [NSUUID UUID];
    attachment.fileName = [[attachment.id.UUIDString lowercaseString] stringByAppendingPathExtension:@"jpg"];
    attachment.content = jpeg;
    attachment.record = record;
    return attachment;
}

@end
