#import "LBPermissions.h"
#import <ODataKit/ODataError.h>
#import "Vehicle+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "VehicleDriver+CoreDataClass.h"
#import "VehicleWasValuedOnDateAtMoney+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"
#import "Inspection+CoreDataClass.h"
#import "Answer+CoreDataClass.h"
#import "Checklist+CoreDataClass.h"
#import "Question+CoreDataClass.h"
#import "Option+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"
#import "Rescheduling+CoreDataClass.h"
#import "LBStockProcedures.h"
#import "WarehouseStaff+CoreDataClass.h"

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

BOOL LBOwns(Vehicle *vehicle, NSString *email) {
    return [vehicle isKindOfClass:[Vehicle class]] && [vehicle.owner.email isEqualToString:email];
}

/* Owns it, or is entered as a driver of it (OwnerDrives, and the rows). */
BOOL LBDrives(Vehicle *vehicle, NSString *email) {
    if (LBOwns(vehicle, email)) return YES;
    for (VehicleDriver *driver in [vehicle isKindOfClass:[Vehicle class]] ? vehicle.vehicleDrivers : nil) {
        if ([driver.user.email isEqualToString:email]) return YES;
    }
    return NO;
}

#pragma mark Catalogs

BOOL LBOwnsCatalog(Catalog *catalog, NSString *email) {
    return [catalog isKindOfClass:[Catalog class]] && [catalog.catalogOwner.email isEqualToString:email];
}

/* The user's role at the warehouse: nil for none. */
static NSString *LBRoleAt(Warehouse *warehouse, NSString *email) {
    for (WarehouseStaff *staff in [warehouse isKindOfClass:[Warehouse class]] ? warehouse.warehouseStaffs : nil) {
        if ([staff.user.email isEqualToString:email]) return staff.staffRole;
    }
    return nil;
}

BOOL LBSeesCatalog(Catalog *catalog, NSString *email) {
    if (LBOwnsCatalog(catalog, email)) return YES;
    for (Warehouse *warehouse in [catalog isKindOfClass:[Catalog class]] ? catalog.warehouses : nil) {
        if (LBRoleAt(warehouse, email)) return YES;
    }
    return NO;
}

BOOL LBManagesIn(Catalog *catalog, NSString *email) {
    if (LBOwnsCatalog(catalog, email)) return YES;
    for (Warehouse *warehouse in [catalog isKindOfClass:[Catalog class]] ? catalog.warehouses : nil) {
        if ([LBRoleAt(warehouse, email) isEqualToString:@"Manager"]) return YES;
    }
    return NO;
}

BOOL LBManages(Warehouse *warehouse, NSString *email) {
    if (![warehouse isKindOfClass:[Warehouse class]]) return NO;
    return LBOwnsCatalog(warehouse.catalog, email) || [LBRoleAt(warehouse, email) isEqualToString:@"Manager"];
}

BOOL LBKeeps(Warehouse *warehouse, NSString *email) {
    if (![warehouse isKindOfClass:[Warehouse class]]) return NO;
    return LBOwnsCatalog(warehouse.catalog, email) || LBRoleAt(warehouse, email) != nil;
}

/* The catalogs one sees, from where the key path goes to one (nil: the
   catalogs themselves). */
static NSPredicate *LBCatalogSeen(NSString *path, NSString *email) {
    NSString *at = path.length ? [path stringByAppendingString:@"."] : @"";
    NSString *owner = [NSString stringWithFormat:@"%@%@.%@", at, LBKey(catalogOwner), LBKey(email)];
    /* Two to-many steps, warehouses then their staff: a subquery each,
       as the store takes no key path through both. */
    NSString *format = [NSString stringWithFormat:@"%%K == %%@ OR SUBQUERY(%@%@, $w, ANY $w.%@.%@.%@ == %%@).@count > 0", at,
                                                  LBKey(warehouses), LBKey(warehouseStaffs), LBKey(user), LBKey(email)];
    return [NSPredicate predicateWithFormat:format, owner, email, email];
}

/* The vehicles one drives, from where the key path goes to one (nil: the
   vehicles themselves). */
static NSPredicate *LBDriven(NSString *path, NSString *email) {
    NSString *at = path.length ? [path stringByAppendingString:@"."] : @"";
    NSString *owner = [NSString stringWithFormat:@"%@%@.%@", at, LBKey(owner), LBKey(email)];
    NSString *drivers = [NSString stringWithFormat:@"%@%@.%@.%@", at, LBKey(vehicleDrivers), LBKey(user), LBKey(email)];
    return [NSPredicate predicateWithFormat:@"%K == %@ OR ANY %K == %@", owner, email, drivers, email];
}

#pragma mark The handlers

/* What every set's handler does: a request of someone signed in asked
   what they may see, add and change; an anonymous one let do anything.
   Each kind of set says the rest. */
@interface LBPermissionHandler : ODataSyncSetHandler
/* What of the set they see: nil for all of it. */
- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request;
/* Why they may not add a row of these values; nil when they may. */
- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email;
/* Why they may not change or remove the row (to these values, for a
   change); nil when they may. */
- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email;
/* What the server says of a row they added, whatever the request did. */
- (void)made:(NSManagedObject *)made by:(NSString *)email;
/* What of a change they may make. */
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

/* A vehicle: its maker's; its owner's to change. */
@interface LBVehicleHandler : LBPermissionHandler
@end

@implementation LBVehicleHandler

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    return LBDriven(nil, email);
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return LBOwns((Vehicle *)object, email) ? nil : @"Only a vehicle's owner changes it";
}

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    ((Vehicle *)made).owner = LBUserNamed(made.managedObjectContext, email, YES);
}

@end

/* A record: added by whoever drives its vehicle, entered by them; the
   owner's to change. */
@interface LBRecordHandler : LBPermissionHandler
@end

@implementation LBRecordHandler

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    return LBDriven(LBKey(vehicle), email);
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    Vehicle *vehicle = values[LBKey(vehicle)];
    if (![vehicle isKindOfClass:[Vehicle class]]) return @"A record names its vehicle";
    return LBDrives(vehicle, email) ? nil : @"Only who drives a vehicle adds records to it";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    Vehicle *moved = values[LBKey(vehicle)];
    if (!LBOwns(((Record *)object).vehicle, email)) return @"Only a vehicle's owner changes what is recorded of it";
    return !moved || LBOwns(moved, email) ? nil : @"Only a vehicle's owner records to it";
}

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    ((Record *)made).enteredBy = LBUserNamed(made.managedObjectContext, email, YES);
}

/* Who entered a record is said once, by the server. */
- (NSDictionary<NSString *, id> *)changeable:(NSDictionary<NSString *, id> *)values {
    NSMutableDictionary *kept = [values mutableCopy];
    [kept removeObjectForKey:LBKey(enteredBy)];
    return kept;
}

@end

/* Of a vehicle (who drives it, what it was valued at): its owner's. */
@interface LBOfVehicleHandler : LBPermissionHandler
@end

@implementation LBOfVehicleHandler

/* The vehicle a row is of. */
static Vehicle *LBVehicleOf(NSManagedObject *object) {
    if ([object isKindOfClass:[VehicleDriver class]]) return ((VehicleDriver *)object).vehicle;
    if ([object isKindOfClass:[VehicleWasValuedOnDateAtMoney class]]) return ((VehicleWasValuedOnDateAtMoney *)object).vehicle;
    return nil;
}

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    return LBDriven(LBKey(vehicle), email);
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return LBOwns(values[LBKey(vehicle)], email) ? nil : @"Only a vehicle's owner shares it and values it";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    Vehicle *moved = values[LBKey(vehicle)];
    return LBOwns(LBVehicleOf(object), email) && (!moved || LBOwns(moved, email)) ? nil
        : @"Only a vehicle's owner shares it and values it";
}

@end

/* Of a record (a service's items, an attachment, an inspection's answers):
   added with a new record of one's own, else the owner's. */
@interface LBOfRecordHandler : LBPermissionHandler
@end

@implementation LBOfRecordHandler

/* The record a row is of. */
static Record *LBRecordOf(NSManagedObject *object) {
    if ([object isKindOfClass:[ServiceItem class]]) return ((ServiceItem *)object).service;
    if ([object isKindOfClass:[Attachment class]]) return ((Attachment *)object).record;
    if ([object isKindOfClass:[Answer class]]) return ((Answer *)object).inspection;
    return nil;
}

/* The relationship from a row of the set to its record. */
- (NSString *)recordKey {
    if ([self.entity.name isEqualToString:LBEntity(ServiceItem)]) return LBKey(service);
    if ([self.entity.name isEqualToString:LBEntity(Attachment)]) return LBKey(record);
    return LBKey(inspection);
}

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    NSPredicate *driven = LBDriven([[self recordKey] stringByAppendingFormat:@".%@", LBKey(vehicle)], email);
    if (![self.entity.name isEqualToString:LBEntity(Attachment)]) return driven;
    /* A photo of a stock item: whoever sees its catalog. */
    NSPredicate *pictured = LBCatalogSeen([LBKey(stockItem) stringByAppendingFormat:@".%@", LBKey(catalog)], email);
    return [NSCompoundPredicate orPredicateWithSubpredicates:@[ driven, pictured ]];
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    StockItem *pictured = values[LBKey(stockItem)];
    if ([pictured isKindOfClass:[StockItem class]] && !values[[self recordKey]]) {
        return LBOwnsCatalog(pictured.catalog, email) ? nil : @"Only a catalog's owner adds photos of its items";
    }
    Record *record = values[[self recordKey]];
    if (![record isKindOfClass:[Record class]]) return [NSString stringWithFormat:@"It names its %@", [self recordKey]];
    BOOL theirsNew = record.isInserted && [record.enteredBy.email isEqualToString:email];
    return theirsNew || LBOwns(record.vehicle, email) ? nil
        : @"Only a vehicle's owner adds to a record of it, but to a new one of one's own";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    StockItem *pictured = [object isKindOfClass:[Attachment class]] ? ((Attachment *)object).stockItem : nil;
    if (pictured && !LBRecordOf(object)) {
        return LBOwnsCatalog(pictured.catalog, email) ? nil : @"Only a catalog's owner changes photos of its items";
    }
    return LBOwns(LBRecordOf(object).vehicle, email) ? nil : @"Only a vehicle's owner changes what is recorded of it";
}

@end

/* A reminder's rescheduling: made by whoever drives its vehicle, made by
   them; the owner's to change. */
@interface LBReschedulingHandler : LBPermissionHandler
@end

@implementation LBReschedulingHandler

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    return LBDriven([LBKey(reminder) stringByAppendingFormat:@".%@", LBKey(vehicle)], email);
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    Reminder *reminder = values[LBKey(reminder)];
    if (![reminder isKindOfClass:[Reminder class]]) return @"A rescheduling names its reminder";
    return LBDrives(reminder.vehicle, email) ? nil : @"Only who drives a vehicle reschedules its reminders";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return LBOwns(((Rescheduling *)object).reminder.vehicle, email) ? nil
        : @"Only a vehicle's owner changes what is recorded of it";
}

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    ((Rescheduling *)made).madeBy = LBUserNamed(made.managedObjectContext, email, YES);
}

/* Who made it is said once, by the server. */
- (NSDictionary<NSString *, id> *)changeable:(NSDictionary<NSString *, id> *)values {
    NSMutableDictionary *kept = [values mutableCopy];
    [kept removeObjectForKey:LBKey(madeBy)];
    return kept;
}

@end

/* A user: named by their email, which whoever names them knows; what else
   is said of them is theirs. */
@interface LBUserHandler : LBPermissionHandler
@end

@implementation LBUserHandler

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    /* A write names a user by their email (sharing a vehicle with them).
       Read: themselves, and whoever they share a vehicle with. */
    if (![request.method isEqualToString:@"GET"]) return nil;
    return [NSPredicate predicateWithFormat:@"email == %@"
                                             " OR SUBQUERY(vehicleDrivers, $d, $d.vehicle.owner.email == %@"
                                             " OR ANY $d.vehicle.vehicleDrivers.user.email == %@).@count > 0"
                                             " OR SUBQUERY(ownedVehicles, $v, ANY $v.vehicleDrivers.user.email == %@).@count > 0",
                                             email, email, email, email];
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    /* Another, by their email alone: to share a vehicle with them before
       they first sign in. */
    id named = values[LBKey(email)];
    if (!named || [named isEqual:email]) return nil;
    return values.count == 1 ? nil : @"A user says only the email of another";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return [((User *)object).email isEqualToString:email] ? nil : @"A user changes only themselves";
}

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    User *user = (User *)made;
    if (!user.email) user.email = email;
}

@end

/* A checklist, its questions and their options: its keeper's. Seen too by
   whoever an inspection of a vehicle of theirs went through it. */
@interface LBChecklistHandler : LBPermissionHandler
@end

@implementation LBChecklistHandler

/* The checklist a row is, or is of. */
static Checklist *LBChecklistOf(id object) {
    if ([object isKindOfClass:[Checklist class]]) return object;
    if ([object isKindOfClass:[Question class]]) return ((Question *)object).checklist;
    if ([object isKindOfClass:[Option class]]) return ((Option *)object).question.checklist;
    return nil;
}

/* The key path from a row of the set to its checklist; nil for one. */
- (NSString *)checklistPath {
    if ([self.entity.name isEqualToString:LBEntity(Question)]) return LBKey(checklist);
    if ([self.entity.name isEqualToString:LBEntity(Option)]) return [LBKey(question) stringByAppendingFormat:@".%@", LBKey(checklist)];
    return nil;
}

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    NSString *path = [self checklistPath];
    NSString *at = path ? [path stringByAppendingString:@"."] : @"";
    NSString *format = [NSString stringWithFormat:@"%@user.email == %%@ OR SUBQUERY(%@inspections, $i, $i.vehicle.owner.email == %%@"
                                                  " OR ANY $i.vehicle.vehicleDrivers.user.email == %%@).@count > 0", at, at];
    return [NSPredicate predicateWithFormat:format, email, email, email];
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    if (![self checklistPath]) return nil;
    /* A question names its checklist; an option its question. */
    id above = values[LBKey(checklist)] ?: values[LBKey(question)];
    return [LBChecklistOf(above).user.email isEqualToString:email] ? nil : @"A checklist is its keeper's";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return [LBChecklistOf(object).user.email isEqualToString:email] ? nil : @"A checklist is its keeper's";
}

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    if ([made isKindOfClass:[Checklist class]]) ((Checklist *)made).user = LBUserNamed(made.managedObjectContext, email, YES);
}

@end

/* The app's (units): read only. */
@interface LBReferenceHandler : LBPermissionHandler
@end

@implementation LBReferenceHandler

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return @"Units are the app's";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return @"Units are the app's";
}

@end

/* An exchange rate, a kind of cost or of expense: added by anyone signed
   in, changed by no one (others' records are of it). */
@interface LBAddOnlyHandler : LBPermissionHandler
@end

@implementation LBAddOnlyHandler

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return @"Exchange rates and kinds of cost are added, not changed";
}

@end


#pragma mark Stock

/* Who writes a stock set's rows: a catalog's owner; a manager, of the
   row's warehouse or (none said) of one of the catalog's; a keeper of the
   row's warehouse, a manager there changing or removing them. */
typedef NS_ENUM(NSInteger, LBStockWriter) {
    LBStockOwner,
    LBStockManager,
    LBStockKeeper,
};

/* A row's, or a write's values': what a key path from it reaches, the
   first key from the values, the rest from what that is. */
static id LBFollow(id from, NSString *path) {
    NSArray *keys = [path componentsSeparatedByString:@"."];
    id at = [from isKindOfClass:[NSDictionary class]] ? from[keys.firstObject] : [from valueForKey:keys.firstObject];
    for (NSUInteger i = 1; i < keys.count && at; i++) {
        at = [at isKindOfClass:[NSManagedObject class]] ? [at valueForKey:keys[i]] : nil;
    }
    return at;
}

/* A stock set: seen by whoever sees its catalog, written as its writer
   says. */
@interface LBStockHandler : LBPermissionHandler
@property (nonatomic, copy) NSString *catalogPath;           /* nil: a catalog */
@property (nonatomic, copy) NSArray<NSString *> *warehousePaths;  /* each must be kept, managed */
@property (nonatomic) LBStockWriter writer;
/* Who may is the service's relations' to decide (its permissions). */
@property (nonatomic) BOOL byRelations;
@end

@implementation LBStockHandler

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    return self.byRelations ? nil : LBCatalogSeen(self.catalogPath, email);
}

- (Catalog *)catalogOf:(id)row {
    return self.catalogPath ? LBFollow(row, self.catalogPath) : ([row isKindOfClass:[Catalog class]] ? row : nil);
}

/* Whether the user keeps a warehouse of the catalog. */
static BOOL LBKeepsIn(Catalog *catalog, NSString *email) {
    for (Warehouse *warehouse in [catalog isKindOfClass:[Catalog class]] ? catalog.warehouses : nil) {
        if (LBKeeps(warehouse, email)) return YES;
    }
    return NO;
}

/* The parts a service or a tyre change used (docs/STOCK.md): their sale,
   and its lines, are written by the staff of the warehouse it ships from,
   keepers too; the vehicle owner's contact and customer it is to are made
   by the catalog's warehouse staff. Until claims (ODataKit#60) say who may
   do what. */
- (BOOL)mayRecordParts:(id)row email:(NSString *)email changing:(BOOL)changing {
    NSString *entity = self.entity.name;
    if ([entity isEqualToString:LBEntity(SaleOrder)] || [entity isEqualToString:LBEntity(SaleLine)]) {
        id sale = [entity isEqualToString:LBEntity(SaleLine)] ? LBFollow(row, @"saleOrder") : row;
        BOOL parts = LBFollow(sale, @"serviceAsPartsSale") || LBFollow(sale, @"tyreChangeAsPartsSale");
        return parts && LBKeeps(LBFollow(sale, @"shipsFrom.warehouse"), email);
    }
    if (changing) return NO;
    if ([entity isEqualToString:LBEntity(Contact)]) {
        return LBFollow(row, @"user") && LBKeepsIn(LBFollow(row, @"catalog"), email);
    }
    if ([entity isEqualToString:LBEntity(Customer)]) {
        return LBFollow(row, @"contact.user") && LBKeepsIn(LBFollow(row, @"catalog"), email);
    }
    return NO;
}

/* Why the user may not write the row (a write's values, or a row): nil
   when they may. Changing, a keeper's row is a manager's. */
- (NSString *)whyNot:(id)row email:(NSString *)email changing:(BOOL)changing {
    if (self.byRelations || [self mayRecordParts:row email:email changing:changing]) return nil;
    Catalog *catalog = [self catalogOf:row];
    if (!catalog) return self.catalogPath ? @"It names what catalog it is of" : nil;
    switch (self.writer) {
    case LBStockOwner:
        return LBOwnsCatalog(catalog, email) ? nil : @"Only a catalog's owner writes that";
    case LBStockManager:
    case LBStockKeeper: {
        BOOL manager = self.writer == LBStockManager || changing;
        if (self.warehousePaths.count == 0) {
            return LBManagesIn(catalog, email) ? nil : @"Only a catalog's owner or managers write that";
        }
        BOOL any = NO;
        for (NSString *path in self.warehousePaths) {
            Warehouse *warehouse = LBFollow(row, path);
            if (!warehouse) continue;
            any = YES;
            if (warehouse.catalog != catalog) return @"That warehouse is of another catalog";
            if (manager ? !LBManages(warehouse, email) : !LBKeeps(warehouse, email)) {
                return manager ? @"Only a warehouse's managers, or its catalog's owner, do that there"
                               : @"Only a warehouse's staff, or its catalog's owner, do that there";
            }
        }
        return any ? nil : @"It names where it is";
    }
    }
    return nil;
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return [self whyNot:values email:email changing:NO];
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    NSString *why = [self whyNot:object email:email changing:YES];
    if (why || values.count == 0) return why;
    /* Moved to another catalog or warehouse: theirs to write there too. */
    NSMutableDictionary *after = [NSMutableDictionary dictionary];
    for (NSPropertyDescription *property in object.entity.properties) {
        id value = values[property.name] ?: [object valueForKey:property.name];
        if (value) after[property.name] = value;
    }
    return [self whyNot:after email:email changing:YES];
}

- (void)made:(NSManagedObject *)made by:(NSString *)email {
    if ([made isKindOfClass:[Catalog class]]) ((Catalog *)made).catalogOwner = LBUserNamed(made.managedObjectContext, email, YES);
}

/* An item with no SKU, an order or count with no number, is given the
   next of its kind. */
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

/* The stock sets: the path to each one's catalog, where its rows are, and
   who writes them. */
static void LBServeStock(ODataService *service, NSMutableDictionary<NSString *, id> *handlers) {
    NSString *catalog = LBKey(catalog);
    NSArray *stock = @[
        @[ LBEntity(Catalog), [NSNull null], @[], @(LBStockOwner) ],
        @[ LBEntity(StockItem), catalog, @[], @(LBStockOwner) ],
        @[ @"Category", catalog, @[], @(LBStockOwner) ],
        @[ LBEntity(Contact), catalog, @[], @(LBStockOwner) ],
        @[ LBEntity(Customer), catalog, @[], @(LBStockOwner) ],
        @[ LBEntity(Supplier), catalog, @[], @(LBStockOwner) ],
        @[ @"Address", @"contact.catalog", @[], @(LBStockOwner) ],
        @[ @"ItemAttribute", catalog, @[], @(LBStockOwner) ],
        @[ @"ItemAttributeValue", @"stockItem.catalog", @[], @(LBStockOwner) ],
        @[ LBEntity(KitLine), @"kit.catalog", @[], @(LBStockOwner) ],
        @[ LBEntity(SupplierItem), @"stockItem.catalog", @[], @(LBStockOwner) ],
        @[ LBEntity(ItemCode), @"stockItem.catalog", @[], @(LBStockOwner) ],
        @[ LBEntity(Warehouse), catalog, @[], @(LBStockOwner) ],
        @[ LBEntity(WarehouseStaff), @"warehouse.catalog", @[], @(LBStockOwner) ],
        @[ LBEntity(Location), @"warehouse.catalog", @[ @"warehouse" ], @(LBStockManager) ],
        @[ LBEntity(ReorderRule), @"warehouse.catalog", @[ @"warehouse" ], @(LBStockManager) ],
        @[ LBEntity(SaleOrder), catalog, @[], @(LBStockManager) ],
        @[ LBEntity(SaleLine), @"saleOrder.catalog", @[], @(LBStockManager) ],
        @[ LBEntity(PurchaseOrder), catalog, @[], @(LBStockManager) ],
        @[ LBEntity(PurchaseLine), @"purchaseOrder.catalog", @[], @(LBStockManager) ],
        @[ LBEntity(Holding), @"stockItem.catalog", @[ @"location.warehouse" ], @(LBStockKeeper) ],
        @[ LBEntity(Move), @"stockItem.catalog", @[ @"source.warehouse", @"destination.warehouse" ], @(LBStockKeeper) ],
        @[ LBEntity(Shipment), @"saleOrder.catalog", @[ @"shippedFrom.warehouse" ], @(LBStockKeeper) ],
        @[ LBEntity(Receipt), @"purchaseOrder.catalog", @[ @"receivedAt.warehouse" ], @(LBStockKeeper) ],
        @[ LBEntity(CustomerReturn), @"saleOrder.catalog", @[ @"returnedTo.warehouse" ], @(LBStockKeeper) ],
        @[ LBEntity(SupplierReturn), @"purchaseOrder.catalog", @[ @"returnedFrom.warehouse" ], @(LBStockKeeper) ],
        @[ LBEntity(Assembly), @"assembled.catalog", @[ @"assembledAt.warehouse" ], @(LBStockKeeper) ],
        @[ LBEntity(StockCount), @"warehouse.catalog", @[ @"warehouse" ], @(LBStockKeeper) ],
    ];
    for (NSArray *each in stock) {
        NSEntityDescription *entity = service.model.entitiesByName[each[0]];
        NSString *set = entity.userInfo[@"OData.entitySet"];
        if (!set.length) continue;
        LBStockHandler *handler = [[LBStockHandler alloc] initWithEntity:entity];
        handler.catalogPath = each[1] == [NSNull null] ? nil : each[1];
        handler.warehousePaths = each[2];
        handler.writer = [each[3] integerValue];
        handler.byRelations = service.permissions != nil;
        handlers[each[0]] = handler;
    }
}

void LBServePermissions(ODataService *service) {
    /* Each root entity's set, by what it is. */
    NSDictionary<NSString *, Class> *kinds = @{
        LBEntity(Vehicle): [LBVehicleHandler class],
        LBEntity(Record): [LBRecordHandler class],
        LBEntity(VehicleDriver): [LBOfVehicleHandler class],
        LBEntity(VehicleWasValuedOnDateAtMoney): [LBOfVehicleHandler class],
        LBEntity(ServiceItem): [LBOfRecordHandler class],
        LBEntity(Attachment): [LBOfRecordHandler class],
        LBEntity(Answer): [LBOfRecordHandler class],
        LBEntity(Rescheduling): [LBReschedulingHandler class],
        LBEntity(User): [LBUserHandler class],
        LBEntity(Checklist): [LBChecklistHandler class],
        LBEntity(Question): [LBChecklistHandler class],
        LBEntity(Option): [LBChecklistHandler class],
        @"DistanceUnit": [LBReferenceHandler class],
        @"VolumeUnit": [LBReferenceHandler class],
        @"CostKind": [LBAddOnlyHandler class],
        @"ExchangeRate": [LBAddOnlyHandler class],
    };
    NSMutableDictionary *stock = [NSMutableDictionary dictionary];
    LBServeStock(service, stock);
    for (NSEntityDescription *entity in service.model.entities) {
        NSString *set = entity.userInfo[@"OData.entitySet"];
        if (entity.superentity || !set.length) continue;
        if (stock[entity.name]) {
            [service setHandler:stock[entity.name] forEntitySet:set];
            continue;
        }
        Class kind = kinds[entity.name];
        if (!kind) {
            NSLog(@"permissions: %@ (%@) is no one's: read only to anyone signed in", entity.name, set);
            kind = [LBReferenceHandler class];
        }
        [service setHandler:[[kind alloc] initWithEntity:entity] forEntitySet:set];
    }
}
