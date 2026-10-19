#import "LBPermissions.h"
#import <ODataKit/ODataError.h>

/* What a set is, as far as who may change it goes. */
typedef NS_ENUM(NSInteger, LBKind) {
    LBVehicleKind,     // a vehicle: its owner's
    LBRecordKind,      // a record: added by who drives its vehicle, else the owner's
    LBOfVehicleKind,   // of a vehicle (path): its owner's
    LBOfRecordKind,    // of a record (path): added with a new one of one's own, else the owner's
    LBUserKind,        // a user: their own
    LBChecklistKind,   // a checklist, or of one (path): its keeper's
    LBReferenceKind,   // the app's: read only
    LBAddOnlyKind      // added by anyone, changed by no one
};

@interface LBPermissionHandler : ODataSyncSetHandler
@property (nonatomic) LBKind kind;
/* The key path to what it is of: the vehicle, the record, the checklist;
   nil for itself. */
@property (nonatomic, copy) NSString *path;
@end

/* The signed-in user's email: nil for no one (an anonymous request). */
static NSString *LBEmailOf(ODataRequest *request) {
    HSPrincipal *principal = request.principal;
    if (!principal) return nil;
    id email = principal.claims[@"email"];
    return [email isKindOfClass:[NSString class]] && [email length] ? email : principal.subject;
}

/* The user of the email, made when there is none and make says so. */
static NSManagedObject *LBUserNamed(NSManagedObjectContext *context, NSString *email, BOOL make) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"email == %@", email];
    NSManagedObject *user = [[context executeFetchRequest:fetch error:NULL] firstObject];
    if (!user && make) {
        user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [user setValue:email forKey:@"email"];
    }
    return user;
}

static BOOL LBOwns(NSManagedObject *vehicle, NSString *email) {
    return vehicle && [[vehicle valueForKeyPath:@"owner.email"] isEqual:email];
}

/* Owns it, or is entered as a driver of it (OwnerDrives, and the rows). */
static BOOL LBDrives(NSManagedObject *vehicle, NSString *email) {
    return LBOwns(vehicle, email) || [[vehicle valueForKeyPath:@"vehicleDrivers.user.email"] containsObject:email];
}

/* The vehicles one drives, from where the key path goes to one. */
static NSPredicate *LBDriven(NSString *path, NSString *email) {
    NSString *at = path.length ? [path stringByAppendingString:@"."] : @"";
    return [NSPredicate predicateWithFormat:[NSString stringWithFormat:@"%@owner.email == %%@ OR ANY %@vehicleDrivers.user.email == %%@", at, at],
                                            email, email];
}

static NSError *LBRefusal(NSString *why) {
    return ODataServiceError(403, why);
}

@implementation LBPermissionHandler

- (NSPredicate *)predicateForVisibleObjectsInRequest:(ODataRequest *)request {
    NSPredicate *theirs = [super predicateForVisibleObjectsInRequest:request];
    NSString *email = LBEmailOf(request);
    NSPredicate *mine = email ? [self visibleTo:email request:request] : nil;
    if (!mine) return theirs;
    return theirs ? [NSCompoundPredicate andPredicateWithSubpredicates:@[ theirs, mine ]] : mine;
}

- (NSPredicate *)visibleTo:(NSString *)email request:(ODataRequest *)request {
    switch (_kind) {
    case LBVehicleKind:
        return LBDriven(nil, email);
    case LBRecordKind:
        return LBDriven(@"vehicle", email);
    case LBOfVehicleKind:
        return LBDriven(_path, email);
    case LBOfRecordKind:
        return LBDriven([_path stringByAppendingString:@".vehicle"], email);
    case LBUserKind:
        /* A write names a user by their email, which whoever names them
           knows (sharing a vehicle with them). Read: themselves, and
           whoever they share a vehicle with. */
        if (![request.method isEqualToString:@"GET"]) return nil;
        return [NSPredicate predicateWithFormat:@"email == %@"
                                                 " OR SUBQUERY(vehicleDrivers, $d, $d.vehicle.owner.email == %@"
                                                 " OR ANY $d.vehicle.vehicleDrivers.user.email == %@).@count > 0"
                                                 " OR SUBQUERY(ownedVehicles, $v, ANY $v.vehicleDrivers.user.email == %@).@count > 0",
                                                 email, email, email, email];
    case LBChecklistKind: {
        /* Its keeper's, and those an inspection of a vehicle of theirs went through. */
        NSString *at = _path.length ? [_path stringByAppendingString:@"."] : @"";
        NSString *format = [NSString stringWithFormat:@"%@user.email == %%@ OR SUBQUERY(%@inspections, $i, $i.vehicle.owner.email == %%@"
                                                      " OR ANY $i.vehicle.vehicleDrivers.user.email == %%@).@count > 0", at, at];
        return [NSPredicate predicateWithFormat:format, email, email, email];
    }
    case LBReferenceKind:
    case LBAddOnlyKind:
        return nil;
    }
    return nil;
}

/* Why the user may not add a row of these values; nil when they may. */
- (NSString *)whyNotAdd:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    switch (_kind) {
    case LBVehicleKind:
    case LBAddOnlyKind:
        return nil;
    case LBRecordKind: {
        NSManagedObject *vehicle = values[@"vehicle"];
        if (![vehicle isKindOfClass:[NSManagedObject class]]) return @"A record names its vehicle";
        return LBDrives(vehicle, email) ? nil : @"Only who drives a vehicle adds records to it";
    }
    case LBOfVehicleKind: {
        NSManagedObject *vehicle = values[_path];
        return LBOwns([vehicle isKindOfClass:[NSManagedObject class]] ? vehicle : nil, email) ? nil
            : @"Only a vehicle's owner shares it and values it";
    }
    case LBOfRecordKind: {
        NSManagedObject *record = values[_path];
        if (![record isKindOfClass:[NSManagedObject class]]) return [NSString stringWithFormat:@"It names its %@", _path];
        BOOL theirsNew = record.isInserted && [[record valueForKeyPath:@"enteredBy.email"] isEqual:email];
        return theirsNew || LBOwns([record valueForKey:@"vehicle"], email) ? nil
            : @"Only a vehicle's owner adds to a record of it, but to a new one of one's own";
    }
    case LBUserKind: {
        /* Another, by their email alone: to share a vehicle with them
           before they first sign in. What else is said of them is theirs. */
        id named = values[@"email"];
        if (!named || [named isEqual:email]) return nil;
        return values.count == 1 ? nil : @"A user says only the email of another";
    }
    case LBChecklistKind: {
        if (!_path.length) return nil;
        NSArray *keys = [_path componentsSeparatedByString:@"."];
        NSManagedObject *above = values[keys.firstObject];
        NSString *rest = [[keys subarrayWithRange:NSMakeRange(1, keys.count - 1)] componentsJoinedByString:@"."];
        NSManagedObject *checklist = [above isKindOfClass:[NSManagedObject class]] && rest.length ? [above valueForKeyPath:rest] : above;
        return [[checklist valueForKeyPath:@"user.email"] isEqual:email] ? nil : @"A checklist is its keeper's";
    }
    case LBReferenceKind:
        return @"Units and kinds of cost are the app's";
    }
    return nil;
}

/* Why the user may not change or remove the row (to these values, for a
   change); nil when they may. */
- (NSString *)whyNotChange:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values email:(NSString *)email {
    switch (_kind) {
    case LBVehicleKind:
        return LBOwns(object, email) ? nil : @"Only a vehicle's owner changes it";
    case LBRecordKind:
    case LBOfVehicleKind: {
        NSString *key = _kind == LBRecordKind ? @"vehicle" : _path;
        NSManagedObject *moved = values[key];
        if (!LBOwns([object valueForKey:key], email)) return @"Only a vehicle's owner changes what is recorded of it";
        return !moved || LBOwns(moved, email) ? nil : @"Only a vehicle's owner records to it";
    }
    case LBOfRecordKind:
        return LBOwns([object valueForKeyPath:[_path stringByAppendingString:@".vehicle"]], email) ? nil
            : @"Only a vehicle's owner changes what is recorded of it";
    case LBUserKind:
        return [[object valueForKey:@"email"] isEqual:email] ? nil : @"A user changes only themselves";
    case LBChecklistKind: {
        NSString *keeper = _path.length ? [_path stringByAppendingString:@".user.email"] : @"user.email";
        return [[object valueForKeyPath:keeper] isEqual:email] ? nil : @"A checklist is its keeper's";
    }
    case LBReferenceKind:
        return @"Units and kinds of cost are the app's";
    case LBAddOnlyKind:
        return @"An exchange rate is added, not changed";
    }
    return nil;
}

- (NSManagedObject *)insertObjectWithValues:(NSDictionary<NSString *, id> *)values request:(ODataRequest *)request reply:(ODataReply *)reply {
    NSString *email = LBEmailOf(request);
    if (!email) return [super insertObjectWithValues:values request:request reply:reply];
    NSString *why = [self whyNotAdd:values email:email];
    if (why) {
        [reply failWithError:LBRefusal(why)];
        return nil;
    }
    NSManagedObject *made = [super insertObjectWithValues:values request:request reply:reply];
    if (!made) return nil;
    switch (_kind) {
    case LBVehicleKind:
        [made setValue:LBUserNamed(request.context, email, YES) forKey:@"owner"];
        break;
    case LBRecordKind:
        [made setValue:LBUserNamed(request.context, email, YES) forKey:@"enteredBy"];
        break;
    case LBUserKind:
        if (!values[@"email"]) [made setValue:email forKey:@"email"];
        break;
    case LBChecklistKind:
        if (!_path.length) [made setValue:LBUserNamed(request.context, email, YES) forKey:@"user"];
        break;
    default:
        break;
    }
    return made;
}

- (NSManagedObject *)updateObject:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values request:(ODataRequest *)request
                            reply:(ODataReply *)reply {
    NSString *email = LBEmailOf(request);
    if (!email) return [super updateObject:object values:values request:request reply:reply];
    NSString *why = [self whyNotChange:object values:values email:email];
    if (why) {
        [reply failWithError:LBRefusal(why)];
        return nil;
    }
    /* Who entered a record is said once, by the server. */
    NSMutableDictionary *kept = [values mutableCopy];
    if (_kind == LBRecordKind) [kept removeObjectForKey:@"enteredBy"];
    return [super updateObject:object values:kept request:request reply:reply];
}

- (void)deleteObject:(NSManagedObject *)object request:(ODataRequest *)request reply:(ODataReply *)reply {
    NSString *email = LBEmailOf(request);
    NSString *why = email ? [self whyNotChange:object values:@{} email:email] : nil;
    if (why) {
        [reply failWithError:LBRefusal(why)];
        return;
    }
    [super deleteObject:object request:request reply:reply];
}

@end

void LBServePermissions(ODataService *service) {
    /* Each root entity, by what it is: what a set's rows are of. */
    NSDictionary<NSString *, NSArray *> *kinds = @{
        @"Vehicle": @[ @(LBVehicleKind) ],
        @"Record": @[ @(LBRecordKind) ],
        @"VehicleDriver": @[ @(LBOfVehicleKind), @"vehicle" ],
        @"VehicleWasValuedOnDateAtMoney": @[ @(LBOfVehicleKind), @"vehicle" ],
        @"ServiceItem": @[ @(LBOfRecordKind), @"service" ],
        @"Attachment": @[ @(LBOfRecordKind), @"record" ],
        @"Answer": @[ @(LBOfRecordKind), @"inspection" ],
        @"User": @[ @(LBUserKind) ],
        @"Checklist": @[ @(LBChecklistKind) ],
        @"Question": @[ @(LBChecklistKind), @"checklist" ],
        @"Option": @[ @(LBChecklistKind), @"question.checklist" ],
        @"DistanceUnit": @[ @(LBReferenceKind) ],
        @"VolumeUnit": @[ @(LBReferenceKind) ],
        @"CostKind": @[ @(LBReferenceKind) ],
        @"ExchangeRate": @[ @(LBAddOnlyKind) ],
    };
    for (NSEntityDescription *entity in service.model.entities) {
        NSString *set = entity.userInfo[@"OData.entitySet"];
        NSArray *kind = kinds[entity.name];
        if (entity.superentity || !set.length) continue;
        if (!kind) {
            NSLog(@"permissions: %@ (%@) is no one's: read only to anyone signed in", entity.name, set);
            kind = @[ @(LBReferenceKind) ];
        }
        LBPermissionHandler *handler = [[LBPermissionHandler alloc] initWithEntity:entity];
        handler.kind = (LBKind)[kind[0] integerValue];
        handler.path = kind.count > 1 ? kind[1] : nil;
        [service setHandler:handler forEntitySet:set];
    }
}
