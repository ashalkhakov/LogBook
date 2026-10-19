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

/* The name of a property as a write's values and a predicate have it: the
   generated class's, so that the compiler knows it. */
#define LBKey(property) NSStringFromSelector(@selector(property))
/* An entity's name, by its class (the model's representedClassName): not
   +entity, which cannot tell the model loaded from the copy the server
   runs on (LBServer.m keeps both). */
#define LBEntity(cls) NSStringFromClass([cls class])

/* The signed-in user's email: nil for no one (an anonymous request). */
static NSString *LBEmailOf(ODataRequest *request) {
    HSPrincipal *principal = request.principal;
    if (!principal) return nil;
    id email = principal.claims[@"email"];
    return [email isKindOfClass:[NSString class]] && [email length] ? email : principal.subject;
}

/* The user of the email, made when there is none and make says so. */
static User *LBUserNamed(NSManagedObjectContext *context, NSString *email, BOOL make) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:LBEntity(User)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", LBKey(email), email];
    User *user = [[context executeFetchRequest:fetch error:NULL] firstObject];
    if (!user && make) {
        user = [NSEntityDescription insertNewObjectForEntityForName:LBEntity(User) inManagedObjectContext:context];
        user.email = email;
    }
    return user;
}

static BOOL LBOwns(Vehicle *vehicle, NSString *email) {
    return [vehicle isKindOfClass:[Vehicle class]] && [vehicle.owner.email isEqualToString:email];
}

/* Owns it, or is entered as a driver of it (OwnerDrives, and the rows). */
static BOOL LBDrives(Vehicle *vehicle, NSString *email) {
    if (LBOwns(vehicle, email)) return YES;
    for (VehicleDriver *driver in [vehicle isKindOfClass:[Vehicle class]] ? vehicle.vehicleDrivers : nil) {
        if ([driver.user.email isEqualToString:email]) return YES;
    }
    return NO;
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
    return LBDriven([[self recordKey] stringByAppendingFormat:@".%@", LBKey(vehicle)], email);
}

- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    Record *record = values[[self recordKey]];
    if (![record isKindOfClass:[Record class]]) return [NSString stringWithFormat:@"It names its %@", [self recordKey]];
    BOOL theirsNew = record.isInserted && [record.enteredBy.email isEqualToString:email];
    return theirsNew || LBOwns(record.vehicle, email) ? nil
        : @"Only a vehicle's owner adds to a record of it, but to a new one of one's own";
}

- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    return LBOwns(LBRecordOf(object).vehicle, email) ? nil : @"Only a vehicle's owner changes what is recorded of it";
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
        LBEntity(User): [LBUserHandler class],
        LBEntity(Checklist): [LBChecklistHandler class],
        LBEntity(Question): [LBChecklistHandler class],
        LBEntity(Option): [LBChecklistHandler class],
        @"DistanceUnit": [LBReferenceHandler class],
        @"VolumeUnit": [LBReferenceHandler class],
        @"CostKind": [LBAddOnlyHandler class],
        @"ExchangeRate": [LBAddOnlyHandler class],
    };
    for (NSEntityDescription *entity in service.model.entities) {
        NSString *set = entity.userInfo[@"OData.entitySet"];
        if (entity.superentity || !set.length) continue;
        Class kind = kinds[entity.name];
        if (!kind) {
            NSLog(@"permissions: %@ (%@) is no one's: read only to anyone signed in", entity.name, set);
            kind = [LBReferenceHandler class];
        }
        [service setHandler:[[kind alloc] initWithEntity:entity] forEntitySet:set];
    }
}
