#import "LBPermissions.h"
#import <ODataKit/ODataError.h>
#import "Vehicle+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "Checklist+CoreDataClass.h"
#import "Rescheduling+CoreDataClass.h"
#import "LBStockProcedures.h"

/* The name of a property as a write's values and a predicate have it: the
   generated class's, so that the compiler knows it. */
#define LBKey(property) NSStringFromSelector(@selector(property))
/* An entity's name, by its class (the model's representedClassName): not
   +entity, which cannot tell the model loaded from the copy the server
   runs on (LBServer.m keeps both). */
#define LBEntity(cls) NSStringFromClass([cls class])

/* The signed-in user's email: nil for no one (an anonymous request). */
NSString *LBEmailOf(ODataRequest *request) {
    HSPrincipal *principal = request.principal;
    if (!principal) return nil;
    id email = principal.claims[@"email"];
    return [email isKindOfClass:[NSString class]] && [email length] ? email : principal.subject;
}

/* The user of the email, made when there is none and make says so. */
User *LBUserNamed(NSManagedObjectContext *context, NSString *email, BOOL make) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:LBEntity(User)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", LBKey(email), email];
    User *user = [[context executeFetchRequest:fetch error:NULL] firstObject];
    if (!user && make) {
        user = [NSEntityDescription insertNewObjectForEntityForName:LBEntity(User) inManagedObjectContext:context];
        user.email = email;
    }
    return user;
}

BOOL LBHolds(ODataRequest *request, NSString *relation, NSManagedObject *object) {
    ODataService *service = request.service;
    if (!service.permissions) return YES;
    return object && [service request:request holds:relation onObject:object];
}

#pragma mark The handlers

/* What every set's handler does: what a signed-in user writes is theirs
   (made:), and what is said once is left out of a change (changeable:).
   Who may is the permissions'. */
@interface LBPermissionHandler : ODataSyncSetHandler
/* What of the set they see: nil for all of it the permissions let them. */
- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request;
/* Why not, when the permissions cannot say: nil when they may. */
- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email;
- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email;
- (void)made:(NSManagedObject *)made by:(NSString *)email;
- (NSDictionary<NSString *, id> *)changeable:(NSDictionary<NSString *, id> *)values;
@end

@implementation LBPermissionHandler

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request { return nil; }
- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email { return nil; }
- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email { return nil; }
- (void)made:(NSManagedObject *)made by:(NSString *)email {}
- (NSDictionary<NSString *, id> *)changeable:(NSDictionary<NSString *, id> *)values { return values; }

- (NSPredicate *)predicateForVisibleObjectsInRequest:(ODataRequest *)request {
    NSPredicate *theirs = [super predicateForVisibleObjectsInRequest:request];
    NSString *email = LBEmailOf(request);
    NSPredicate *mine = email ? [self visibleTo:email request:request] : nil;
    if (!mine) return theirs;
    return theirs ? [NSCompoundPredicate andPredicateWithSubpredicates:@[ theirs, mine ]] : mine;
}

- (NSManagedObject *)insertObjectWithValues:(NSDictionary<NSString *, id> *)values request:(ODataRequest *)request reply:(ODataReply *)reply {
    NSString *email = LBEmailOf(request);
    if (!email) return [super insertObjectWithValues:values request:request reply:reply];
    NSString *why = [self whyNotAdd:values email:email];
    if (why) {
        [reply failWithError:ODataServiceError(403, why)];
        return nil;
    }
    NSManagedObject *made = [super insertObjectWithValues:values request:request reply:reply];
    if (made) [self made:made by:email];
    return made;
}

- (NSManagedObject *)updateObject:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values request:(ODataRequest *)request
                            reply:(ODataReply *)reply {
    NSString *email = LBEmailOf(request);
    if (!email) return [super updateObject:object values:values request:request reply:reply];
    NSString *why = [self whyNotChange:object values:values email:email];
    if (why) {
        [reply failWithError:ODataServiceError(403, why)];
        return nil;
    }
    return [super updateObject:object values:[self changeable:values] request:request reply:reply];
}

- (void)deleteObject:(NSManagedObject *)object request:(ODataRequest *)request reply:(ODataReply *)reply {
    NSString *email = LBEmailOf(request);
    NSString *why = email ? [self whyNotChange:object values:@{} email:email] : nil;
    if (why) {
        [reply failWithError:ODataServiceError(403, why)];
        return;
    }
    [super deleteObject:object request:request reply:reply];
}

@end

/* A vehicle: its maker's. */
@interface LBVehicleHandler : LBPermissionHandler
@end

@implementation LBVehicleHandler

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    ((Vehicle *)made).owner = LBUserNamed(made.managedObjectContext, email, YES);
}

@end

/* A record: entered by whoever adds it, said once. */
@interface LBRecordHandler : LBPermissionHandler
@end

@implementation LBRecordHandler

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    ((Record *)made).enteredBy = LBUserNamed(made.managedObjectContext, email, YES);
}

- (NSDictionary<NSString *, id> *)changeable:(NSDictionary<NSString *, id> *)values {
    NSMutableDictionary *kept = [values mutableCopy];
    [kept removeObjectForKey:LBKey(enteredBy)];
    return kept;
}

@end

/* A reminder's rescheduling: made by whoever adds it, said once. */
@interface LBReschedulingHandler : LBPermissionHandler
@end

@implementation LBReschedulingHandler

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    ((Rescheduling *)made).madeBy = LBUserNamed(made.managedObjectContext, email, YES);
}

- (NSDictionary<NSString *, id> *)changeable:(NSDictionary<NSString *, id> *)values {
    NSMutableDictionary *kept = [values mutableCopy];
    [kept removeObjectForKey:LBKey(madeBy)];
    return kept;
}

@end

/* A user: named by their email, which whoever names them knows. A write
   finds anyone by it, which no relation can say: what a read sees is
   here. Changed only by themselves: the permissions'. */
@interface LBUserHandler : LBPermissionHandler
@end

@implementation LBUserHandler

/* The users one sees: themselves, and whoever they share a vehicle with. */
static NSPredicate *LBUsersSeenBy(NSString *email) {
    return [NSPredicate predicateWithFormat:@"email == %@"
                                             " OR SUBQUERY(vehicleDrivers, $d, $d.vehicle.owner.email == %@"
                                             " OR ANY $d.vehicle.vehicleDrivers.user.email == %@).@count > 0"
                                             " OR SUBQUERY(ownedVehicles, $v, ANY $v.vehicleDrivers.user.email == %@).@count > 0",
                                             email, email, email, email];
}

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    /* A write names a user by their email (sharing a vehicle with them). */
    return [request.method isEqualToString:@"GET"] ? LBUsersSeenBy(email) : nil;
}

/* Which users one sees changes with no user changed (a vehicle shared):
   a version of them, which a delta link of the set carries, so that a
   device reads the set again once it does (410). Their emails, digested
   (FNV-1a: the same from one run of the server to the next). */
- (NSString *)scopeVersionForRequest:(ODataRequest *)request {
    NSString *email = LBEmailOf(request);
    if (!email || !request.context) return [super scopeVersionForRequest:request];
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:LBEntity(User)];
    fetch.predicate = LBUsersSeenBy(email);
    NSArray *seen = [[[request.context executeFetchRequest:fetch error:NULL] valueForKey:LBKey(email)]
        sortedArrayUsingSelector:@selector(compare:)];
    uint64_t digest = 14695981039346656037ULL;
    for (NSString *each in seen) {
        const char *bytes = [[each description] UTF8String];
        for (; *bytes; bytes++) digest = (digest ^ (uint8_t)*bytes) * 1099511628211ULL;
        digest = (digest ^ 0) * 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"users-%016llx", (unsigned long long)digest];
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    /* Another, by their email alone: to share a vehicle with them before
       they first sign in. A device sends the rest as nothing (null), and
       ODataSync's own (its versions) with any row. */
    id named = values[LBKey(email)];
    if (!named || [named isEqual:email]) return nil;
    for (NSString *key in values) {
        if ([key isEqualToString:LBKey(email)] || [key isEqualToString:LBKey(syncModified)] || [key isEqualToString:LBKey(syncVersions)]) continue;
        if (values[key] != [NSNull null]) return @"A user says only the email of another";
    }
    return nil;
}

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    User *user = (User *)made;
    if (!user.email) user.email = email;
}

@end

/* A checklist: its maker keeps it. */
@interface LBChecklistHandler : LBPermissionHandler
@end

@implementation LBChecklistHandler

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    ((Checklist *)made).user = LBUserNamed(made.managedObjectContext, email, YES);
}

@end

/* A set the permissions do not name: read only. */
@interface LBReadOnlyHandler : LBPermissionHandler
@end

@implementation LBReadOnlyHandler

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return @"It is read only";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return @"It is read only";
}

@end

#pragma mark Stock

/* A stock set: a catalog is its maker's; an item with no SKU, an order or
   count with no number, is given the next of its kind. */
@interface LBStockHandler : LBPermissionHandler
@end

@implementation LBStockHandler

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    if ([made isKindOfClass:[Catalog class]]) ((Catalog *)made).catalogOwner = LBUserNamed(made.managedObjectContext, email, YES);
}

- (NSManagedObject *)insertObjectWithValues:(NSDictionary<NSString *, id> *)values request:(ODataRequest *)request reply:(ODataReply *)reply {
    NSManagedObject *made = [super insertObjectWithValues:values request:request reply:reply];
    if ([made isKindOfClass:[StockItem class]] && !((StockItem *)made).sku.length) {
        StockItem *item = (StockItem *)made;
        item.sku = [item.catalog lb_nextSKU];
    } else if ([made isKindOfClass:[SaleOrder class]] && ((SaleOrder *)made).runningNumber == 0) {
        SaleOrder *order = (SaleOrder *)made;
        order.runningNumber = [order.catalog lb_nextNumberOf:order.catalog.saleOrders];
    } else if ([made isKindOfClass:[PurchaseOrder class]] && ((PurchaseOrder *)made).runningNumber == 0) {
        PurchaseOrder *order = (PurchaseOrder *)made;
        order.runningNumber = [order.catalog lb_nextNumberOf:order.catalog.purchaseOrders];
    } else if ([made isKindOfClass:[StockCount class]] && ((StockCount *)made).runningNumber == 0) {
        StockCount *count = (StockCount *)made;
        count.runningNumber = [count.warehouse.catalog lb_nextNumberOf:count.warehouse.stockCounts];
    }
    return made;
}

@end

/* Whether the permissions name the entity, or one it is a kind of. */
static BOOL LBNamed(ODataService *service, NSEntityDescription *entity) {
    NSDictionary *entities = service.permissions.propertyList[@"Entities"];
    for (NSEntityDescription *at = entity; at; at = at.superentity) {
        if ([entities isKindOfClass:[NSDictionary class]] && entities[at.name]) return YES;
    }
    return NO;
}

void LBServePermissions(ODataService *service) {
    /* Each root entity's set, by what is said of its rows that no
       permission says. */
    NSDictionary<NSString *, Class> *kinds = @{
        LBEntity(Vehicle): [LBVehicleHandler class],
        LBEntity(Record): [LBRecordHandler class],
        LBEntity(Rescheduling): [LBReschedulingHandler class],
        LBEntity(User): [LBUserHandler class],
        LBEntity(Checklist): [LBChecklistHandler class],
        LBEntity(Catalog): [LBStockHandler class],
        LBEntity(StockItem): [LBStockHandler class],
        LBEntity(SaleOrder): [LBStockHandler class],
        LBEntity(PurchaseOrder): [LBStockHandler class],
        LBEntity(StockCount): [LBStockHandler class],
    };
    for (NSEntityDescription *entity in service.model.entities) {
        NSString *set = entity.userInfo[@"OData.entitySet"];
        if (entity.superentity || !set.length) continue;
        Class kind = kinds[entity.name];
        if (!kind && !LBNamed(service, entity)) {
            NSLog(@"permissions: %@ (%@) is not in the permissions: read only", entity.name, set);
            kind = [LBReadOnlyHandler class];
        }
        [service setHandler:[[kind ?: [LBPermissionHandler class] alloc] initWithEntity:entity] forEntitySet:set];
    }
}
