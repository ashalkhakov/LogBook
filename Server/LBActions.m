#import "LBActions.h"
#import "LBPermissions.h"
#import <ODataKit/ODataError.h>
#import "Vehicle+CoreDataClass.h"

NSString * const LBNextReminderTouchedCode = @"NextReminderTouched";

/* Who carries out the procedure on the vehicle's behalf: the signed-in
   user (who may call it is the permissions', call.<Name>); for an
   anonymous request, with no sign-in, the vehicle's owner. nil, the reply
   failed, when there is no one. */
static User *LBActorFor(ODataReply *reply, Vehicle *vehicle) {
    NSString *email = LBEmailOf(reply.request);
    if (!email) {
        if (!vehicle.owner) [reply failWithError:ODataServiceError(400, @"The vehicle has no owner to act for")];
        return vehicle.owner;
    }
    return LBUserNamed(reply.request.context, email, YES);
}

/* A unit by its code; NO, the reply failed, for a code of none. */
static BOOL LBUnitCoded(ODataReply *reply, NSString *code, DistanceUnit **unit) {
    *unit = nil;
    if (!code.length) return YES;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([DistanceUnit class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(code)), code];
    *unit = [[reply.request.context executeFetchRequest:fetch error:NULL] firstObject];
    if (!*unit) [reply failWithError:ODataServiceError(400, [NSString stringWithFormat:@"No distance unit is '%@'", code])];
    return *unit != nil;
}

/* A procedure's refusal, answered: 400, or 409 for a touched next reminder
   (its code, and the reminder's id as its target). */
static void LBRefuse(ODataReply *reply, NSError *error) {
    if (error.code == LBProceduresErrorNextReminderTouched) {
        Reminder *next = [error.userInfo[LBNextRemindersErrorKey] firstObject];
        NSMutableDictionary *said = [@{ NSLocalizedDescriptionKey: error.localizedDescription ?: @"",
                                        ODataErrorCodeKey: LBNextReminderTouchedCode } mutableCopy];
        if (next.id) said[ODataErrorTargetKey] = next.id.UUIDString.lowercaseString;
        [reply failWithError:[NSError errorWithDomain:ODataServiceErrorDomain code:409 userInfo:said]];
        return;
    }
    [reply failWithError:ODataServiceError(400, error.localizedDescription ?: @"Refused")];
}

@implementation Schedule (LBActions)

- (Reminder *)startWithLastDoneAt:(NSDate *)lastDoneAt lastDoneMileage:(NSDecimalNumber *)lastDoneMileage
              lastDoneMileageUnit:(NSString *)lastDoneMileageUnit reply:(ODataReply *)reply {
    User *user = LBActorFor(reply, self.vehicle);
    DistanceUnit *unit;
    if (!user || !LBUnitCoded(reply, lastDoneMileageUnit, &unit)) return nil;
    NSError *error = nil;
    Reminder *first = [self lb_startFrom:lastDoneAt mileage:lastDoneMileage unit:unit by:user at:[NSDate date] error:&error];
    if (!first) LBRefuse(reply, error);
    return first;
}

+ (NSDictionary<NSString *, NSString *> *)ODataOperationTypes {
    return @{ @"continueWithTask:expenseKind:checklist:interval:intervalUnit:months:note:reply:.months": @"Edm.Int32" };
}

- (Schedule *)continueWithTask:(NSString *)task expenseKind:(ExpenseKind *)expenseKind checklist:(Checklist *)checklist
                      interval:(NSDecimalNumber *)interval intervalUnit:(NSString *)intervalUnit months:(NSNumber *)months
                          note:(NSString *)note reply:(ODataReply *)reply {
    User *user = LBActorFor(reply, self.vehicle);
    DistanceUnit *unit;
    if (!user || !LBUnitCoded(reply, intervalUnit, &unit)) return nil;
    NSError *error = nil;
    Schedule *next = [self lb_continueWithTask:task expenseKind:expenseKind checklist:checklist interval:interval unit:unit
                                        months:(int32_t)months.integerValue note:note by:user at:[NSDate date] cancelled:NULL
                                         error:&error];
    if (!next) LBRefuse(reply, error);
    return next;
}

@end

@implementation Reminder (LBActions)

- (Reminder *)completeWithEvent:(Event *)event reply:(ODataReply *)reply {
    User *user = LBActorFor(reply, self.vehicle);
    if (!user) return nil;
    NSError *error = nil;
    Reminder *next = nil;
    if (![self lb_completeByEvent:event next:&next error:&error]) LBRefuse(reply, error);
    return next;
}

- (Rescheduling *)rescheduleWithDueDate:(NSDate *)dueDate dueMileage:(NSDecimalNumber *)dueMileage dueMileageUnit:(NSString *)dueMileageUnit
                                   note:(NSString *)note reply:(ODataReply *)reply {
    User *user = LBActorFor(reply, self.vehicle);
    DistanceUnit *unit;
    if (!user || !LBUnitCoded(reply, dueMileageUnit, &unit)) return nil;
    NSError *error = nil;
    Rescheduling *move = [self lb_rescheduleToDate:dueDate mileage:dueMileage unit:unit note:note by:user at:[NSDate date] error:&error];
    if (!move) LBRefuse(reply, error);
    return move;
}

- (Reminder *)cancelWithCancelDate:(NSDate *)cancelDate replacementDueDate:(NSDate *)replacementDueDate
             replacementDueMileage:(NSDecimalNumber *)replacementDueMileage replacementDueMileageUnit:(NSString *)replacementDueMileageUnit
                             reply:(ODataReply *)reply {
    User *user = LBActorFor(reply, self.vehicle);
    DistanceUnit *unit;
    if (!user || !LBUnitCoded(reply, replacementDueMileageUnit, &unit)) return nil;
    NSError *error = nil;
    Reminder *replacement = nil;
    if (![self lb_cancelOn:cancelDate replacementDueDate:replacementDueDate mileage:replacementDueMileage unit:unit by:user at:[NSDate date]
               replacement:&replacement error:&error]) {
        LBRefuse(reply, error);
    }
    return replacement;
}

@end

@implementation Record (LBActions)

+ (NSDictionary<NSString *, NSString *> *)ODataOperationTypes {
    return @{ @"discardWithKeepNextReminder:reply:.keepNextReminder": @"Edm.Boolean" };
}

- (void)discardWithKeepNextReminder:(NSNumber *)keepNextReminder reply:(ODataReply *)reply {
    if (!LBActorFor(reply, self.vehicle)) return;
    NSError *error = nil;
    if (![self lb_discardKeepingNextReminders:keepNextReminder error:&error]) LBRefuse(reply, error);
}

@end
