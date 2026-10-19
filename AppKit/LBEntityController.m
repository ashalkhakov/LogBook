#import "LBEntityController.h"

static NSString * const LBContextBinding = @"context";

@implementation LBEntityController

@synthesize modelEntityName = _modelEntityName;

+ (void)initialize {
    if (self == [LBEntityController class]) [self exposeBinding:LBContextBinding];
}

/* Arranged as they change (a vehicle renamed takes its place), and
   never lazily: gnustep-gui otherwise arranges inside -arrangedObjects,
   telling observers from within a notification, which crashes its KVO. */
- (void)awakeFromNib {
    [super awakeFromNib];
    self.automaticallyRearrangesObjects = YES;
    /* What is added is chosen here (addObject:), not by selectsInserted-
       Objects: gnustep-base's KVO takes the -addSelectedObjects: that does
       it for a set mutator of a key "selected", and fails. */
    self.selectsInsertedObjects = NO;
}

- (void)addObject:(id)object {
    [super addObject:object];
    [self setSelectedObjects:@[ object ]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* Whether its content is a binding's, which keeps it. */
- (BOOL)contentIsBound {
    return [self infoForBinding:NSContentSetBinding] != nil || [self infoForBinding:NSContentArrayBinding] != nil;
}

- (void)setParentKey:(NSString *)parentKey {
    _parentKey = [parentKey copy];
    [self refetch];
}

- (void)setParentObject:(NSManagedObject *)parentObject {
    if (parentObject == _parentObject) return;
    _parentObject = parentObject;
    [self refetch];
}

/* The relationship from one of the parent's objects back to it. */
- (NSString *)inverseKey {
    return [[_parentObject.entity.relationshipsByName[_parentKey] inverseRelationship] name];
}

- (void)setContext:(NSManagedObjectContext *)context {
    if (context == _context) return;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_context) [center removeObserver:self name:NSManagedObjectContextObjectsDidChangeNotification object:_context];
    _context = context;
    if (_context) {
        [center addObserver:self selector:@selector(contextDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification
                     object:_context];
    }
    [self refetch];
}

- (NSString *)modelEntityName {
    if (_modelEntityName) return _modelEntityName;
    Class objectClass = [self objectClass];
    return [objectClass isSubclassOfClass:[NSManagedObject class]] && objectClass != [NSManagedObject class]
        ? NSStringFromClass(objectClass) : nil;
}

/* What it is said to be of, and its context, come in either order. */
- (void)setObjectClass:(Class)objectClass {
    [super setObjectClass:objectClass];
    [self refetch];
}

- (void)setModelEntityName:(NSString *)modelEntityName {
    _modelEntityName = [modelEntityName copy];
    [self refetch];
}

- (void)setContentPredicate:(NSPredicate *)predicate {
    _contentPredicate = [predicate copy];
    [self refetch];
}

- (NSEntityDescription *)entity {
    NSString *name = [self modelEntityName];
    return name && _context ? [NSEntityDescription entityForName:name inManagedObjectContext:_context] : nil;
}

- (void)refetch {
    if ([self contentIsBound]) return;
    if (_parentKey) {
        [self setContent:[self parentsObjects]];
        return;
    }
    NSEntityDescription *entity = [self entity];
    if (!entity) {
        [self setContent:[NSMutableArray array]];
        return;
    }
    NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
    fetch.entity = entity;
    fetch.predicate = _contentPredicate;
    NSError *error = nil;
    NSArray *found = [_context executeFetchRequest:fetch error:&error];
    if (!found) NSLog(@"%@: %@ not fetched: %@", NSStringFromClass([self class]), _modelEntityName, error.localizedDescription);
    [self setContent:[NSMutableArray arrayWithArray:found ?: @[]]];
}

- (NSMutableArray *)parentsObjects {
    NSMutableArray *objects = [NSMutableArray array];
    if (!_parentObject) return objects;
    for (NSManagedObject *object in [_parentObject valueForKey:_parentKey]) {
        if ([self controls:object]) [objects addObject:object];
    }
    return objects;
}

/* Whether an object is one it controls: of the entity, the parent's when
   it has one, and the predicate's. */
- (BOOL)controls:(NSManagedObject *)object {
    NSEntityDescription *entity = [self entity];
    if (!entity || ![object.entity isKindOfEntity:entity] || object.isDeleted) return NO;
    if (_parentKey && (!_parentObject || [object valueForKey:[self inverseKey]] != _parentObject)) return NO;
    return !_contentPredicate || [_contentPredicate evaluateWithObject:object];
}

- (void)contextDidChange:(NSNotification *)notification {
    if ([self contentIsBound]) return;
    NSMutableArray *content = [NSMutableArray arrayWithArray:[self content] ?: @[]];
    NSUInteger before = content.count;
    BOOL changed = NO;
    for (NSManagedObject *object in notification.userInfo[NSDeletedObjectsKey]) {
        if ([content containsObject:object]) {
            [content removeObject:object];
            changed = YES;
        }
    }
    for (NSString *key in @[ NSInsertedObjectsKey, NSUpdatedObjectsKey, NSRefreshedObjectsKey ]) {
        for (NSManagedObject *object in notification.userInfo[key]) {
            BOOL has = [content containsObject:object];
            BOOL should = [self controls:object];
            if (should && !has) [content addObject:object];
            if (!should && has) [content removeObject:object];
            changed = changed || should != has;
        }
    }
    /* A rollback, a refetch elsewhere: what it has, asked again. */
    if (notification.userInfo[NSInvalidatedAllObjectsKey]) {
        [self refetch];
        return;
    }
    if (changed || content.count != before) {
        NSArray *selected = [self selectedObjects];
        [self setContent:content];
        [self setSelectedObjects:selected];
    }
}

- (id)newObject {
    NSEntityDescription *entity = [self entity];
    if (!entity) return [super newObject];
    return [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:_context];
}

/* What it removes is deleted: the user removed it from the logbook. */
- (void)removeObjects:(NSArray *)objects {
    NSArray *gone = [objects copy];
    [super removeObjects:objects];
    for (NSManagedObject *object in gone) {
        if ([object isKindOfClass:[NSManagedObject class]] && object.managedObjectContext == _context) [_context deleteObject:object];
    }
}

- (void)removeObjectsAtArrangedObjectIndexes:(NSIndexSet *)indexes {
    NSArray *gone = [[self arrangedObjects] objectsAtIndexes:indexes];
    [super removeObjectsAtArrangedObjectIndexes:indexes];
    for (NSManagedObject *object in gone) {
        if ([object isKindOfClass:[NSManagedObject class]] && object.managedObjectContext == _context) [_context deleteObject:object];
    }
}

@end
