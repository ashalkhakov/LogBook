#import "LBStore.h"
#import <ODataIncrementalStore/ODataIncrementalStore.h>
#import "LogbookValidation.h"
#import "User+CoreDataClass.h"

/* What a generated class says of an object's deontic rules. */
@protocol LBWarned <NSObject>
- (NSArray<NSError *> *)orm_deonticViolations;
@end

@implementation LBStore {
    NSPersistentStoreCoordinator *_coordinator;
    User *_user;
}

+ (NSManagedObjectModel *)model {
    static NSManagedObjectModel *model;
    if (!model) {
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"Logbook" withExtension:@"momd"];
        model = url ? [[NSManagedObjectModel alloc] initWithContentsOfURL:url] : nil;
    }
    return model;
}

- (instancetype)initWithServiceRoot:(NSURL *)serviceRoot signIn:(ODataSignIn *)signIn {
    if ((self = [super init])) {
        _serviceRoot = [serviceRoot copy];
        _signIn = signIn;
    }
    return self;
}

- (BOOL)open:(NSError **)error {
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
    NSMutableDictionary *options = [@{ ODataIncrementalStorePostOnObtainPermanentIDsOption: @NO,
                                       /* Users('anna@example.org'), not Users/anna@example.org, which the
                                          service reads otherwise (ODataKit#47). */
                                       ODataIncrementalStoreKeyAsSegmentOption: @NO } mutableCopy];
    if (_signIn) options[ODataIncrementalStoreCredentialProviderOption] = _signIn;
    if (![_coordinator addPersistentStoreWithType:[ODataIncrementalStore storeType] configuration:nil URL:_serviceRoot
                                          options:options error:error]) {
        _coordinator = nil;
        return NO;
    }
    _context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    _context.persistentStoreCoordinator = _coordinator;
    _context.undoManager = [[NSUndoManager alloc] init];
    return YES;
}

/* The email the logbook knows the user by: the sign-in's, else the LBUser
   default (a server with no sign-in, for trying it out). */
- (NSString *)email {
    NSString *named = _signIn.isSignedIn ? _signIn.userName : nil;
    return named.length ? named : [[NSUserDefaults standardUserDefaults] stringForKey:@"LBUser"];
}

- (User *)user {
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
    if (!_context.hasChanges) return YES;
    for (NSManagedObject *object in _context.insertedObjects) {
        if ([object respondsToSelector:@selector(setId:)] && !((id<LBIdentified>)object).id) {
            ((id<LBIdentified>)object).id = [NSUUID UUID];
        }
    }
    return [_context orm_prepareForSave:error] && [_context save:error];
}

- (NSArray<NSError *> *)warnings {
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
