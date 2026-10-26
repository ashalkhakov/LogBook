// logbook-server: Logbook's OData service, where every device's logbook
// meets. ODataKit's server (HTTPServerKit, ODataService), with ODataSync's
// part of it (deletions remembered, for the devices' delta links), and the
// model's rules kept as it writes: before it saves a request, or a change
// set at its end, the stored derivations are worked out and every rule
// checked for what the change reaches (the generated orm_prepareForSave:,
// build/Model/Constraints, generated); a change that breaks one is refused (400), and
// nothing of it saved.
//
//   logbook-server -StoreURL logbook.sqlite -Port 8080 -Localhost NO
//   logbook-server -StoreURL Temporary -Port 0
//
// Settings (and LB_ variables: LB_PORT, LB_STORE_URL):
//
//   Model        the compiled model (default: Logbook.momd beside the server)
//   Plans        the model's tables (default: Logbook.ormplans beside it)
//   StoreType    SQLite (the default); PostgreSQL or MySQL: FreeCoreData's
//                SQL stores, loaded as lib<type> when not linked. A store
//                keeps persistent history (delta links are read from it):
//                FreeCoreData's SQL stores do on GNUstep, not Apple's
//   StoreURL     a SQLite file (default Logbook.sqlite here; Temporary: one
//                removed when the server stops), or the database's URL
//   ServiceRoot  the public URL the service is reached at (default
//                http://<host>:<Port>/odata/)
//   Port, Localhost, AccessLog, and every other HTTPServerKit setting
//                (HSApplication.h)
//   AllowAnonymous  NO: a request that names no one is refused (default
//                YES, for trying it out)
//   Permissions  who may see and change the stock, as relations (default
//                Logbook.permissions.plist here; ODataKit's
//                docs/permissions.md): read once a sign-in is set, and one
//                that does not fit the model stops the server
//
// Once a sign-in is set (TrustedUserHeader, JWTIssuer or
// IntrospectionEndpoint), who may see and change what is kept as the model
// says (LBPermissions.h): a user sees the vehicles they drive, and only a
// vehicle's owner changes what is recorded of it.
//
// The procedures on schedules and reminders are its actions (LBActions.h):
// started, closed, moved, cancelled, discarded, each saved whole. An event
// saved, whoever sent it, closes the reminders it does the work of
// (automatic completion, LBProcedures.h), in the same save.

#import <ODataService/ODataServer.h>
#import <ODataSync/ODataSyncService.h>
#import "LogbookValidation.h"
#import "LBPermissions.h"
#import "LBActions.h"
#import "LBProcedures.h"
#import "LBStockProcedures.h"
#include <dlfcn.h>
#include <stdlib.h>

@interface LBServerConfiguration : HSConfiguration
@end

@implementation LBServerConfiguration
+ (NSString *)environmentPrefix { return @"LB_"; }
+ (NSArray<NSString *> *)knownSettings {
    return [[super knownSettings] arrayByAddingObjectsFromArray:@[ @"Model", @"Plans", @"StoreType", @"StoreURL", @"ServiceRoot",
                                                                   @"AllowAnonymous", @"Permissions" ]];
}
@end

@interface LBServer : HSApplication
@property (nonatomic, strong) ODataService *service;
@property (nonatomic, strong) ODataSyncService *histories;
@end

@implementation LBServer

+ (Class)configurationClass { return [LBServerConfiguration class]; }

static NSString *LBTemporaryStore;

static void LBRemoveTemporaryStore(void) {
    for (NSString *suffix in @[ @"", @"-wal", @"-shm" ])
        [[NSFileManager defaultManager] removeItemAtPath:[LBTemporaryStore stringByAppendingString:suffix] error:NULL];
}

static NSError *LBError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: message }];
}

/* A store type by its short name; one nothing registered, its library
   loaded by name (libCDPostgreSQLStore), which registers it as it loads. */
static NSString *LBStoreType(NSString *name) {
    NSDictionary *known = @{ @"SQLite": NSSQLiteStoreType, @"PostgreSQL": @"CDPostgreSQLStore", @"MySQL": @"CDMySQLStore",
                             @"MariaDB": @"CDMySQLStore" };
    NSString *type = known[name ?: @"SQLite"] ?: name;
    if (![NSPersistentStoreCoordinator registeredStoreTypes][type] &&
        [type rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location == NSNotFound) {
#if defined(__APPLE__)
        NSString *library = [NSString stringWithFormat:@"lib%@.dylib", type];
#else
        NSString *library = [NSString stringWithFormat:@"lib%@.so", type];
#endif
        dlopen(library.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    }
    return type;
}

/* A save's failure, each of its errors said: Core Data's own message
   names none. */
static void LBFlatten(NSError *error, NSMutableArray *into) {
    NSArray *each = error.userInfo[NSDetailedErrorsKey];
    if (!each.count) {
        [into addObject:error];
        return;
    }
    for (NSError *e in each) LBFlatten(e, into);
}

static NSError *LBDetailed(NSError *error, NSString *what) {
    NSMutableArray *each = [NSMutableArray array];
    LBFlatten(error, each);
    NSMutableArray *said = [NSMutableArray array];
    for (NSError *e in each) {
        NSManagedObject *object = e.userInfo[NSValidationObjectErrorKey];
        NSString *key = e.userInfo[NSValidationKeyErrorKey];
        [said addObject:[NSString stringWithFormat:@"%@%@%@: %@", object.entity.name ?: @"", key ? @"." : @"", key ?: @"",
                                                   e.localizedDescription]];
    }
    return LBError(error.code, [NSString stringWithFormat:@"%@: %@", what, [said componentsJoinedByString:@"; "]]);
}

static NSURL *LBURL(id value) {
    if (![value isKindOfClass:[NSString class]] || ![value length]) return nil;
    NSURL *url = [NSURL URLWithString:value];
    return url.scheme ? url : [NSURL fileURLWithPath:value];
}

/* A file beside the server, unless the setting names one. */
static NSURL *LBBeside(HSConfiguration *c, NSString *setting, NSString *name) {
    NSString *executable = [NSBundle mainBundle].executablePath.stringByDeletingLastPathComponent;
    return LBURL([c setting:setting]) ?: [NSURL fileURLWithPath:[executable stringByAppendingPathComponent:name]];
}

- (BOOL)makeService:(NSError **)error {
    HSConfiguration *c = self.configuration;
    NSURL *modelURL = LBBeside(c, @"Model", @"Logbook.momd");
    /* Read from its file with the service's part of ODataSync added
       (tombstones), before the store opens: a model Apple's Core Data
       loads takes no more entities. */
    NSError *unread = nil;
    NSManagedObjectModel *model = [ODataSyncService modelWithBookkeepingAtURL:modelURL configuration:nil error:&unread];
    if (!model.entities.count) {
        if (error) *error = LBDetailed(unread ?: LBError(NSFileReadNoSuchFileError, @""),
                                       [NSString stringWithFormat:@"no model at %@ (-Model)", modelURL.path]);
        return NO;
    }
    /* The model's tables, as the generated code asks for them by name. */
    NSURL *plansURL = LBBeside(c, @"Plans", @"Logbook.ormplans");
    NSData *plans = [NSData dataWithContentsOfURL:plansURL];
    id list = plans ? [NSPropertyListSerialization propertyListWithData:plans options:0 format:NULL error:error] : nil;
    ORMTables *tables = list ? [ORMTables tablesWithPropertyList:list error:error] : nil;
    if (!tables) {
        if (error && !plans) *error = LBError(NSFileReadNoSuchFileError, [NSString stringWithFormat:@"no tables at %@ (-Plans)", plansURL.path]);
        return NO;
    }
    [ORMTables registerTables:tables named:@"Logbook"];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSString *type = LBStoreType([c setting:@"StoreType"]);
    BOOL sqlite = [type isEqual:NSSQLiteStoreType];
    NSString *where = [c setting:@"StoreURL"];
    NSURL *url = LBURL(where) ?: (sqlite ? [NSURL fileURLWithPath:@"Logbook.sqlite"] : nil);
    /* A store in memory keeps no history (Apple's): a temporary SQLite one
       instead, gone when the server stops. */
    if (sqlite && [where isEqual:@"Temporary"]) {
        LBTemporaryStore = [NSTemporaryDirectory() stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"logbook-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
        url = [NSURL fileURLWithPath:LBTemporaryStore];
        atexit(LBRemoveTemporaryStore);
    }
    NSMutableDictionary *options = [@{ NSPersistentHistoryTrackingKey: @YES } mutableCopy];
    if (!sqlite) {
        options[@"CDSQLStoreMigrateSchema"] = @YES;
        options[NSIgnorePersistentStoreVersioningOption] = @YES;
    }
    __block NSError *failure = nil;
    if (![coordinator addPersistentStoreWithType:type configuration:nil URL:url options:options error:&failure]) {
        if (error) *error = LBError(NSPersistentStoreOpenError, [NSString stringWithFormat:@"the %@ store at %@ does not open: %@",
                                                                                         type, url ?: @"(none)", failure.localizedDescription]);
        return NO;
    }
    /* The units every store starts with, the app's own. */
    NSManagedObjectContext *seeding = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    seeding.persistentStoreCoordinator = coordinator;
    __block BOOL seeded = NO;
    [seeding performBlockAndWait:^{
        NSError *e = nil;
        seeded = [LogbookReferenceData seedContext:seeding error:&e] && (!seeding.hasChanges || [seeding save:&e]);
        if (!seeded) failure = e;
    }];
    if (!seeded) {
        if (error) *error = LBDetailed(failure, @"the reference data was not seeded");
        return NO;
    }
    NSURL *root = LBURL([c setting:@"ServiceRoot"])
        ?: [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%lu/odata/", c.bindToLocalhost ? @"127.0.0.1" : [NSProcessInfo processInfo].hostName,
                                                            (unsigned long)c.port]];
    _service = [[ODataService alloc] initWithPersistentStoreCoordinator:coordinator serviceRoot:root];
    _service.allowsAnonymousRequests = [c flag:@"AllowAnonymous" otherwise:YES];
    _service.allowsAnonymousMetadata = YES;
    /* Before each save of what clients write: the reminders the events in
       it do the work of closed (automatic completion, LBProcedures.h),
       whichever device sent them; then the model's rules. */
    _service.willSave = ^BOOL(NSManagedObjectContext *context, NSError **refused) {
        NSError *why = nil;
        if (![context lb_completeRemindersOfChangedEvents:&why] || ![context lb_shipPartsOfChangedEvents:&why]) {
            if (refused) *refused = why;
            return NO;
        }
        if ([context orm_prepareForSave:&why]) return YES;
        /* Each violation said, for whoever runs it: a batch's answer has
           the message alone. */
        NSLog(@"a change refused: %@", LBDetailed(why, @"broken").localizedDescription);
        if (refused) *refused = why;
        return NO;
    };
    /* Who may see and change what, once someone is signed in: before
       ODataSync's, which keeps the handlers (they are its kind). */
    if ([c setting:@"TrustedUserHeader"] || [c setting:@"JWTIssuer"] || [c setting:@"IntrospectionEndpoint"]) {
        /* The stock's as relations (Logbook.permissions.plist): one that
           does not fit the model serves no one. */
        NSURL *permissionsURL = LBBeside(c, @"Permissions", @"Logbook.permissions.plist");
        NSError *unreadable = nil;
        ODataPermissions *permissions = [ODataPermissions permissionsWithContentsOfURL:permissionsURL error:&unreadable];
        NSArray *problems = permissions ? [permissions problemsWithModel:model] : nil;
        if (!permissions || problems.count) {
            if (error) *error = LBError(NSFileReadCorruptFileError, [NSString stringWithFormat:@"%@ (-Permissions): %@", permissionsURL.path,
                                                                                               unreadable.localizedDescription
                                                                                                   ?: [problems componentsJoinedByString:@"; "]]);
            return NO;
        }
        _service.permissions = permissions;
        LBServePermissions(_service);
    }
    _histories = [[ODataSyncService alloc] initWithService:_service];
    /* The procedures, as actions (LBActions.h): each declared, or the
       server does not start. */
    if (_service.operationProblems.count) {
        if (error) *error = LBError(NSFeatureUnsupportedError, [NSString stringWithFormat:@"actions not declared: %@",
                                                                                         [_service.operationProblems componentsJoinedByString:@"; "]]);
        return NO;
    }
    return YES;
}

- (BOOL)prepare:(NSError **)error {
    if (!_service && ![self makeService:error]) return NO;
    return [super prepare:error];
}

- (void)configureModules:(NSMutableArray<id<HSModule>> *)modules {
    [super configureModules:modules];
    [modules addObject:[[ODataServiceModule alloc] initWithService:_service]];
}

@end

int main(int argc, const char *argv[]) {
    return HSMain(argc, argv, [LBServer class]);
}
