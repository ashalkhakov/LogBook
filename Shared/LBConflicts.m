#import "LBConflicts.h"

/* A value as a property list: a type and its value, so that a UUID, a
   decimal or none come back as they were. */
id LBPropertyListOfValue(id value) {
    if (!value || value == [NSNull null]) return @{ @"t": @"null" };
    if ([value isKindOfClass:[NSUUID class]]) return @{ @"t": @"uuid", @"v": [value UUIDString] };
    if ([value isKindOfClass:[NSDecimalNumber class]]) return @{ @"t": @"decimal", @"v": [value stringValue] };
    if ([value isKindOfClass:[NSNumber class]]) return @{ @"t": @"number", @"v": value };
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSDate class]] || [value isKindOfClass:[NSData class]])
        return @{ @"t": @"plain", @"v": value };
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *each = [NSMutableDictionary dictionary];
        for (NSString *name in value) each[name] = LBPropertyListOfValue(value[name]);
        return @{ @"t": @"key", @"v": each };
    }
    /* A large binary's digest, or what else: said, not kept. */
    return @{ @"t": @"plain", @"v": [value description] };
}

id LBValueOfPropertyList(id plist) {
    if (![plist isKindOfClass:[NSDictionary class]]) return nil;
    NSString *type = plist[@"t"];
    id v = plist[@"v"];
    if ([type isEqual:@"uuid"]) return [[NSUUID alloc] initWithUUIDString:v];
    if ([type isEqual:@"decimal"]) return [NSDecimalNumber decimalNumberWithString:v];
    if ([type isEqual:@"key"]) {
        NSMutableDictionary *each = [NSMutableDictionary dictionary];
        for (NSString *name in v) each[name] = LBValueOfPropertyList(v[name]) ?: [NSNull null];
        return each;
    }
    if ([type isEqual:@"null"]) return [NSNull null];
    return v;
}

static NSData *LBArchived(id plistable) {
    return [NSPropertyListSerialization dataWithPropertyList:plistable format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}

static id LBUnarchived(NSData *data) {
    return data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
}

static NSData *LBArchivedValues(NSDictionary *values) {
    NSMutableDictionary *each = [NSMutableDictionary dictionary];
    for (NSString *name in values) each[name] = LBPropertyListOfValue(values[name]);
    return LBArchived(each);
}

static NSDictionary *LBUnarchivedValues(NSData *data) {
    NSDictionary *each = LBUnarchived(data);
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    if (![each isKindOfClass:[NSDictionary class]]) return values;
    for (NSString *name in each) values[name] = LBValueOfPropertyList(each[name]) ?: [NSNull null];
    return values;
}

@interface LBPendingConflict ()
@property (nonatomic, copy, nullable) NSData *keyData;
@property (nonatomic, copy, nullable) NSData *mineData;
@property (nonatomic, copy, nullable) NSData *theirsData;
@property (nonatomic, copy, nullable) NSString *propertyNames;
/* The key as text, its parts by name: what a later conflict of the same
   object is found by. */
@property (nonatomic, copy, nullable) NSString *keyText;
@end

@implementation LBPendingConflict
@dynamic objectEntityName, deletedThere, deletedHere, when, keyData, mineData, theirsData, propertyNames, keyText;

- (NSDictionary *)key { return LBUnarchivedValues(self.keyData); }
- (NSDictionary *)mine { return LBUnarchivedValues(self.mineData); }
- (NSDictionary *)theirs { return LBUnarchivedValues(self.theirsData); }
- (NSArray<NSString *> *)properties {
    return self.propertyNames.length ? [self.propertyNames componentsSeparatedByString:@","] : @[];
}
@end

/* An attachment's image, kept by its id. */
@interface LBAttachmentImage : NSManagedObject
@property (nonatomic, copy, nullable) NSString *attachmentID;
@property (nonatomic, copy, nullable) NSData *data;
@end

@implementation LBAttachmentImage
@dynamic attachmentID, data;
@end

static NSAttributeDescription *LBAttribute(SEL name, NSAttributeType type, BOOL optional) {
    NSAttributeDescription *attribute = [[NSAttributeDescription alloc] init];
    attribute.name = NSStringFromSelector(name);
    attribute.attributeType = type;
    attribute.optional = optional;
    return attribute;
}

/* The app state's model, made here: no part of the logbook's. */
static NSManagedObjectModel *LBAppStateModel(void) {
    NSEntityDescription *conflict = [[NSEntityDescription alloc] init];
    conflict.name = NSStringFromClass([LBPendingConflict class]);
    conflict.managedObjectClassName = NSStringFromClass([LBPendingConflict class]);
    NSAttributeDescription *deletedThere = LBAttribute(@selector(deletedThere), NSBooleanAttributeType, NO);
    deletedThere.defaultValue = @NO;
    NSAttributeDescription *deletedHere = LBAttribute(@selector(deletedHere), NSBooleanAttributeType, NO);
    deletedHere.defaultValue = @NO;
    conflict.properties = @[ LBAttribute(@selector(objectEntityName), NSStringAttributeType, NO),
                             LBAttribute(@selector(keyData), NSBinaryDataAttributeType, NO),
                             LBAttribute(@selector(keyText), NSStringAttributeType, NO),
                             LBAttribute(@selector(mineData), NSBinaryDataAttributeType, YES),
                             LBAttribute(@selector(theirsData), NSBinaryDataAttributeType, YES),
                             LBAttribute(@selector(propertyNames), NSStringAttributeType, YES),
                             deletedThere, deletedHere,
                             LBAttribute(@selector(when), NSDateAttributeType, YES) ];
    NSEntityDescription *image = [[NSEntityDescription alloc] init];
    image.name = NSStringFromClass([LBAttachmentImage class]);
    image.managedObjectClassName = NSStringFromClass([LBAttachmentImage class]);
    NSAttributeDescription *data = LBAttribute(@selector(data), NSBinaryDataAttributeType, YES);
    data.allowsExternalBinaryDataStorage = YES;
    image.properties = @[ LBAttribute(@selector(attachmentID), NSStringAttributeType, NO), data ];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ conflict, image ];
    return model;
}

@implementation LBAppState {
    NSPersistentStoreCoordinator *_coordinator;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithStoreURL:(NSURL *)url error:(NSError **)error {
    if (!(self = [super init])) return nil;
    _coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:LBAppStateModel()];
    NSDictionary *options = @{ NSMigratePersistentStoresAutomaticallyOption: @YES, NSInferMappingModelAutomaticallyOption: @YES };
    if (![_coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:options error:error]) return nil;
    _context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    _context.persistentStoreCoordinator = _coordinator;
    _context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    return self;
}

- (NSArray<LBPendingConflict *> *)pendingConflicts {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([LBPendingConflict class])];
    fetch.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(when)) ascending:NO] ];
    return [_context executeFetchRequest:fetch error:NULL] ?: @[];
}

- (void)recordConflictOfEntity:(NSString *)entityName key:(NSDictionary *)key properties:(NSArray<NSString *> *)properties
                          mine:(NSDictionary *)mine theirs:(NSDictionary *)theirs deletedThere:(BOOL)deletedThere
                   deletedHere:(BOOL)deletedHere {
    NSManagedObjectContext *writing = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    writing.persistentStoreCoordinator = _coordinator;
    NSData *keyData = LBArchivedValues(key);
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *name in [key.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id value = key[name];
        [parts addObject:[NSString stringWithFormat:@"%@=%@", name, [value isKindOfClass:[NSUUID class]] ? [[value UUIDString] lowercaseString] : value]];
    }
    NSString *keyText = [parts componentsJoinedByString:@"&"];
    [writing performBlockAndWait:^{
        /* One per object: a later conflict of it takes the place of one not
           settled yet, what this side wants is what it changed last. */
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([LBPendingConflict class])];
        fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@ AND %K == %@", NSStringFromSelector(@selector(objectEntityName)), entityName,
                                                           NSStringFromSelector(@selector(keyText)), keyText];
        LBPendingConflict *conflict = [[writing executeFetchRequest:fetch error:NULL] firstObject];
        if (!conflict) {
            conflict = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([LBPendingConflict class])
                                                     inManagedObjectContext:writing];
        }
        conflict.objectEntityName = entityName;
        conflict.keyData = keyData;
        conflict.keyText = keyText;
        conflict.propertyNames = [properties componentsJoinedByString:@","];
        conflict.mineData = LBArchivedValues(mine);
        conflict.theirsData = LBArchivedValues(theirs);
        conflict.deletedThere = deletedThere;
        conflict.deletedHere = deletedHere;
        conflict.when = [NSDate date];
        NSError *error = nil;
        if (![writing save:&error]) NSLog(@"Logbook: a conflict was not kept: %@", error);
    }];
}

- (void)removeConflict:(LBPendingConflict *)conflict {
    if (conflict.managedObjectContext != _context) return;
    [_context deleteObject:conflict];
    [_context save:NULL];
}

- (LBAttachmentImage *)imageOf:(NSUUID *)attachmentID {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([LBAttachmentImage class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(attachmentID)), attachmentID.UUIDString];
    return [[_context executeFetchRequest:fetch error:NULL] firstObject];
}

- (NSData *)dataOfAttachment:(NSUUID *)attachmentID {
    return attachmentID ? [self imageOf:attachmentID].data : nil;
}

- (void)setData:(NSData *)data ofAttachment:(NSUUID *)attachmentID {
    if (!attachmentID) return;
    LBAttachmentImage *image = [self imageOf:attachmentID];
    if (!data) {
        if (image) [_context deleteObject:image];
    } else {
        if (!image) {
            image = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([LBAttachmentImage class])
                                                  inManagedObjectContext:_context];
            image.attachmentID = attachmentID.UUIDString;
        }
        image.data = data;
    }
    [_context save:NULL];
}

@end

@implementation LBConflictResolver {
    LBAppState *_state;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithAppState:(LBAppState *)state {
    if ((self = [super init])) _state = state;
    return self;
}

static BOOL LBIsNone(id value) {
    return !value || value == [NSNull null];
}

+ (BOOL)value:(id)one isSameAs:(id)other {
    if (LBIsNone(one) || LBIsNone(other)) return LBIsNone(one) && LBIsNone(other);
    if ([one isKindOfClass:[NSDate class]] && [other isKindOfClass:[NSDate class]])
        return fabs([one timeIntervalSinceDate:other]) < 0.001;
    if ([one isKindOfClass:[NSNumber class]] && [other isKindOfClass:[NSNumber class]]) {
        /* A decimal comes back through JSON as a double: 68.4 as
           68.40000000000001. The same to a part in 10^12. */
        if ([one compare:other] == NSOrderedSame) return YES;
        double a = [one doubleValue], b = [other doubleValue];
        return fabs(a - b) <= 1e-12 * MAX(fabs(a), fabs(b));
    }
    if ([one isKindOfClass:[NSUUID class]] || [other isKindOfClass:[NSUUID class]]) {
        NSString *a = [one isKindOfClass:[NSUUID class]] ? [one UUIDString] : [one description];
        NSString *b = [other isKindOfClass:[NSUUID class]] ? [other UUIDString] : [other description];
        return [a caseInsensitiveCompare:b] == NSOrderedSame;
    }
    if ([one isKindOfClass:[NSDictionary class]] && [other isKindOfClass:[NSDictionary class]]) {
        if ([one count] != [other count]) return NO;
        for (NSString *name in one) {
            if (![self value:one[name] isSameAs:other[name]]) return NO;
        }
        return YES;
    }
    return [one isEqual:other];
}

/* Its bookkeeping (ODataSync's versions and stamp), by name: no conflict. */
static NSSet<NSString *> *LBBookkeepingOf(NSEntityDescription *entity) {
    NSMutableSet *names = [NSMutableSet set];
    for (NSEntityDescription *e = entity; e; e = e.superentity) {
        for (NSString *key in @[ ODataSyncVersionsKey, ODataSyncModifiedKey ]) {
            NSString *name = e.userInfo[key];
            if (name) [names addObject:name];
        }
    }
    return names;
}

/* In the model's order: the entity's properties, as its description has them. */
static NSArray<NSString *> *LBInModelOrder(NSEntityDescription *entity, NSSet<NSString *> *names) {
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSPropertyDescription *property in entity.properties) {
        if ([names containsObject:property.name]) [ordered addObject:property.name];
    }
    for (NSString *name in [names.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        if (![ordered containsObject:name]) [ordered addObject:name];
    }
    return ordered;
}

- (ODataSyncResolution *)resolveConflict:(ODataSyncConflict *)conflict {
    NSSet<NSString *> *bookkeeping = LBBookkeepingOf(conflict.entity);
    NSDictionary *local = conflict.local, *remote = conflict.remote;
    if (!local && !remote) return [ODataSyncResolution takeRemote];
    NSMutableDictionary *mine = [NSMutableDictionary dictionary];
    NSMutableDictionary *theirs = [NSMutableDictionary dictionary];
    NSMutableSet *differing = [NSMutableSet set];
    if (local && remote) {
        for (NSString *name in conflict.localChanges) {
            if ([bookkeeping containsObject:name]) continue;
            id m = local[name], t = remote[name];
            /* Left unsaid here (an object made on both sides, this one
               knowing less of it): nothing to keep. */
            if (LBIsNone(m) && !conflict.base) continue;
            if ([LBConflictResolver value:m isSameAs:t]) continue;
            [differing addObject:name];
            mine[name] = m ?: [NSNull null];
            theirs[name] = t ?: [NSNull null];
        }
        if (!differing.count) return [ODataSyncResolution takeRemote];
    } else if (!remote) {
        /* Deleted there, changed here: every value of this side's kept, to
           make it again should the user say so. */
        for (NSString *name in local) {
            if (![bookkeeping containsObject:name]) mine[name] = local[name];
        }
        for (NSString *name in conflict.localChanges) {
            if (![bookkeeping containsObject:name]) [differing addObject:name];
        }
    } else {
        /* Deleted here, changed there: theirs is back. */
        for (NSString *name in conflict.remoteChanges) {
            if ([bookkeeping containsObject:name]) continue;
            [differing addObject:name];
            theirs[name] = remote[name] ?: [NSNull null];
        }
    }
    [_state recordConflictOfEntity:conflict.entity.name key:conflict.key properties:LBInModelOrder(conflict.entity, differing)
                              mine:mine theirs:theirs deletedThere:!remote deletedHere:!local];
    return [ODataSyncResolution takeRemote];
}

@end
