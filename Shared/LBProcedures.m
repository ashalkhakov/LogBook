#import "LBProcedures.h"
#import "Vehicle+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "Expense+CoreDataClass.h"
#import "Inspection+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"
#include <stdlib.h>
#include <string.h>

NSErrorDomain const LBProceduresErrorDomain = @"LBProceduresErrorDomain";
NSString * const LBNextRemindersErrorKey = @"LBNextReminders";

#pragma mark Names, days and distances

/* SHA-1 (FIPS 180-4), for name-based UUIDs: Foundation has none of its own
   on every platform. */
static void LBSHA1(const uint8_t *data, size_t length, uint8_t digest[20]) {
    uint32_t h[5] = { 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0 };
    size_t total = ((length + 8) / 64 + 1) * 64;
    uint8_t *message = calloc(total, 1);
    memcpy(message, data, length);
    message[length] = 0x80;
    uint64_t bits = (uint64_t)length * 8;
    for (int i = 0; i < 8; i++) message[total - 1 - i] = (uint8_t)(bits >> (8 * i));
    for (size_t chunk = 0; chunk < total; chunk += 64) {
        uint32_t w[80];
        for (int i = 0; i < 16; i++) {
            const uint8_t *p = message + chunk + 4 * i;
            w[i] = (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | (uint32_t)p[3];
        }
        for (int i = 16; i < 80; i++) {
            uint32_t x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
            w[i] = x << 1 | x >> 31;
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
        for (int i = 0; i < 80; i++) {
            uint32_t f, k;
            if (i < 20) {
                f = (b & c) | (~b & d);
                k = 0x5A827999;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 0x6ED9EBA1;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8F1BBCDC;
            } else {
                f = b ^ c ^ d;
                k = 0xCA62C1D6;
            }
            uint32_t t = (a << 5 | a >> 27) + f + e + k + w[i];
            e = d;
            d = c;
            c = b << 30 | b >> 2;
            b = a;
            a = t;
        }
        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
        h[4] += e;
    }
    free(message);
    for (int i = 0; i < 5; i++) {
        digest[4 * i] = (uint8_t)(h[i] >> 24);
        digest[4 * i + 1] = (uint8_t)(h[i] >> 16);
        digest[4 * i + 2] = (uint8_t)(h[i] >> 8);
        digest[4 * i + 3] = (uint8_t)h[i];
    }
}

NSUUID *LBNamedUUID(NSString *name) {
    static const uint8_t namespace[16] = { 0x3d, 0xfa, 0xb3, 0x4a, 0x71, 0xf4, 0x53, 0x0a,
                                           0x98, 0xa1, 0x5e, 0x67, 0x11, 0xf5, 0x43, 0xa6 };
    NSData *text = [name dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *named = [NSMutableData dataWithBytes:namespace length:sizeof namespace];
    [named appendData:text];
    uint8_t digest[20];
    LBSHA1(named.bytes, named.length, digest);
    digest[6] = (uint8_t)((digest[6] & 0x0F) | 0x50);
    digest[8] = (uint8_t)((digest[8] & 0x3F) | 0x80);
    return [[NSUUID alloc] initWithUUIDBytes:digest];
}

/* An id as a name says it: lower case, as RFC 4122 writes one. */
static NSString *LBIDText(NSUUID *uuid) {
    return uuid.UUIDString.lowercaseString ?: @"";
}

static NSCalendar *LBUTCCalendar(void) {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return calendar;
}

NSDate *LBDay(NSDate *moment) {
    NSCalendar *calendar = LBUTCCalendar();
    NSDateComponents *parts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:moment];
    return [calendar dateFromComponents:parts];
}

NSDate *LBAddMonths(NSDate *day, NSInteger months) {
    NSDateComponents *by = [[NSDateComponents alloc] init];
    by.month = months;
    return [LBUTCCalendar() dateByAddingComponents:by toDate:day options:0];
}

static BOOL LBSameDate(NSDate *a, NSDate *b) {
    return a == b || (a && b && [a isEqualToDate:b]);
}

static BOOL LBSameDistance(NSDecimalNumber *q1, DistanceUnit *u1, NSDecimalNumber *q2, DistanceUnit *u2) {
    if (!q1 || !q2) return !q1 && !q2 && u1 == u2;
    return u1 == u2 && [q1 compare:q2] == NSOrderedSame;
}

/* A quantity in one unit said in another: through what each is worth in
   kilometres, to the metre (Quantity is Decimal(15, 3)). */
static NSDecimalNumber *LBInUnit(NSDecimalNumber *quantity, DistanceUnit *from, DistanceUnit *to) {
    if (from == to || !from.factor || !to.factor || [from.factor compare:to.factor] == NSOrderedSame) return quantity;
    NSDecimalNumberHandler *metres = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:3 raiseOnExactness:NO
                                                                                  raiseOnOverflow:NO raiseOnUnderflow:NO
                                                                               raiseOnDivideByZero:NO];
    return [[quantity decimalNumberByMultiplyingBy:from.factor] decimalNumberByDividingBy:to.factor withBehavior:metres];
}

static NSError *LBRefusal(NSString *message) {
    return [NSError errorWithDomain:LBProceduresErrorDomain code:LBProceduresErrorRefused
                           userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static BOOL LBFail(NSError **error, NSString *message) {
    if (error) *error = LBRefusal(message);
    return NO;
}

#pragma mark Order

/* Events by moment, then id: which came first, whatever order they were
   fetched in. */
static NSComparisonResult LBCompareEvents(Event *a, Event *b) {
    NSDate *at = a.timestamp ?: [NSDate distantPast], *bt = b.timestamp ?: [NSDate distantPast];
    NSComparisonResult order = [at compare:bt];
    return order != NSOrderedSame ? order : [LBIDText(a.id) compare:LBIDText(b.id)];
}

static NSInteger LBEventOrder(id a, id b, void *context) {
    return LBCompareEvents(a, b);
}

/* Reminders by when they were set, then id. */
static NSInteger LBReminderOrder(id a, id b, void *context) {
    Reminder *ra = a, *rb = b;
    NSDate *at = ra.setAt ?: [NSDate distantPast], *bt = rb.setAt ?: [NSDate distantPast];
    NSComparisonResult order = [at compare:bt];
    return order != NSOrderedSame ? order : [LBIDText(ra.id) compare:LBIDText(rb.id)];
}

/* Records (or anything with an id) by id. */
static NSInteger LBIDOrder(id a, id b, void *context) {
    return [LBIDText([(Record *)a id]) compare:LBIDText([(Record *)b id])];
}

#pragma mark What a vehicle had done

/* Whether the event does the work: a service with an item of the task, an
   expense of the kind, an inspection through the checklist. */
static BOOL LBDoesWork(Event *event, NSString *task, ExpenseKind *kind, Checklist *checklist) {
    if (task) {
        if (![event isKindOfClass:[Service class]]) return NO;
        for (ServiceItem *item in ((Service *)event).serviceItems) {
            if (!item.isDeleted && [item.task isEqualToString:task]) return YES;
        }
        return NO;
    }
    if (kind) return [event isKindOfClass:[Expense class]] && ((Expense *)event).expenseKind == kind;
    if (checklist) return [event isKindOfClass:[Inspection class]] && ((Inspection *)event).checklist == checklist;
    return NO;
}

/* The vehicle's events, as they are now. */
static NSArray<Event *> *LBEventsOf(Vehicle *vehicle) {
    NSMutableArray *events = [NSMutableArray array];
    for (Record *record in vehicle.records) {
        if ([record isKindOfClass:[Event class]] && !record.isDeleted && ((Event *)record).timestamp) [events addObject:record];
    }
    return events;
}

/* The vehicle's latest event at a distance, at or before the moment. */
static Event *LBLatestMetered(Vehicle *vehicle, NSDate *moment) {
    Event *latest = nil;
    for (Event *event in LBEventsOf(vehicle)) {
        if (!event.mileageQuantity || !event.mileageDistanceUnit || [event.timestamp compare:moment] == NSOrderedDescending) continue;
        if (!latest || LBCompareEvents(latest, event) == NSOrderedAscending) latest = event;
    }
    return latest;
}

/* Where a schedule's reminder counted from the moment and distance is due:
   the day plus its months, where it recurs after some; the distance (else
   the vehicle's latest at the moment) plus its interval, in that distance's
   unit, where it recurs after one and a distance is known. */
static void LBDueAfter(Schedule *schedule, Vehicle *vehicle, NSDate *moment, NSDecimalNumber *mileage, DistanceUnit *unit,
                       NSDate **dueDate, NSDecimalNumber **dueMileage, DistanceUnit **dueUnit) {
    *dueDate = schedule.duration > 0 ? LBAddMonths(LBDay(moment), schedule.duration) : nil;
    *dueMileage = nil;
    *dueUnit = nil;
    if (!schedule.intervalQuantity || !schedule.intervalDistanceUnit) return;
    if (!mileage || !unit) {
        Event *latest = LBLatestMetered(vehicle, moment);
        mileage = latest.mileageQuantity;
        unit = latest.mileageDistanceUnit;
    }
    if (!mileage || !unit) return;
    *dueMileage = [mileage decimalNumberByAdding:LBInUnit(schedule.intervalQuantity, schedule.intervalDistanceUnit, unit)];
    *dueUnit = unit;
}

/* A reminder of the id, made; nil when the vehicle has one of it already
   (made by this procedure before). */
static Reminder *LBNewReminder(Vehicle *vehicle, NSUUID *uuid, NSManagedObjectContext *context) {
    for (Record *record in vehicle.records) {
        if (!record.isDeleted && [record.id isEqual:uuid]) return nil;
    }
    Reminder *reminder = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Reminder class])
                                                       inManagedObjectContext:context];
    reminder.id = uuid;
    reminder.vehicle = vehicle;
    return reminder;
}

/* Who carries out what an event does on its own: who entered it. */
static User *LBActorOf(Event *event) {
    return event.enteredBy ?: event.driver ?: event.vehicle.owner;
}

#pragma mark Events

@implementation Event (LBProcedures)

- (BOOL)lb_doesWorkOfReminder:(Reminder *)reminder {
    return LBDoesWork(self, reminder.lb_task, reminder.lb_expenseKind, reminder.lb_checklist);
}

- (BOOL)lb_mayCloseReminder:(Reminder *)reminder {
    if (self.isDeleted || reminder.isDeleted || !self.vehicle || self.vehicle != reminder.vehicle || reminder.cancelDate) return NO;
    if (!self.timestamp || !reminder.setAt || [LBDay(reminder.setAt) compare:LBDay(self.timestamp)] == NSOrderedDescending) return NO;
    return [self lb_doesWorkOfReminder:reminder];
}

- (BOOL)lb_isBeforeEvent:(Event *)other {
    return LBCompareEvents(self, other) == NSOrderedAscending;
}

@end

#pragma mark Schedules

@implementation Schedule (LBProcedures)

- (Reminder *)lb_openReminder {
    NSArray *reminders = [self.reminders.allObjects sortedArrayUsingFunction:LBReminderOrder context:NULL];
    for (Reminder *reminder in reminders) {
        if (!reminder.isDeleted && reminder.lb_isOpen) return reminder;
    }
    return nil;
}

- (Event *)lb_lastDoneBy {
    Event *last = nil;
    for (Event *event in LBEventsOf(self.vehicle)) {
        if (!LBDoesWork(event, self.task, self.expenseKind, self.checklist)) continue;
        if (!last || LBCompareEvents(last, event) == NSOrderedAscending) last = event;
    }
    return last;
}

- (Reminder *)lb_startFrom:(NSDate *)lastDone mileage:(NSDecimalNumber *)mileage unit:(DistanceUnit *)unit by:(User *)user at:(NSDate *)now
                     error:(NSError **)error {
    if (!self.vehicle || !self.id) {
        LBFail(error, @"The schedule is not of a vehicle yet");
        return nil;
    }
    if (self.lb_openReminder) {
        LBFail(error, @"The schedule has an open reminder already");
        return nil;
    }
    if ((mileage == nil) != (unit == nil)) {
        LBFail(error, @"A distance is a quantity and its unit");
        return nil;
    }
    NSDate *from = lastDone;
    if (!from) {
        Event *last = self.lb_lastDoneBy;
        from = last.timestamp;
        if (last && !mileage && last.mileageQuantity && last.mileageDistanceUnit) {
            mileage = last.mileageQuantity;
            unit = last.mileageDistanceUnit;
        }
    }
    if (!from) from = now;
    NSDate *dueDate;
    NSDecimalNumber *dueMileage;
    DistanceUnit *dueUnit;
    LBDueAfter(self, self.vehicle, from, mileage, unit, &dueDate, &dueMileage, &dueUnit);
    if (!dueDate && !dueMileage) {
        LBFail(error, @"There is no distance to count the schedule from: say the distance it was last done at");
        return nil;
    }
    NSUInteger before = 0;
    for (Reminder *reminder in self.reminders) {
        if (!reminder.isDeleted) before++;
    }
    NSString *name = [@"start of " stringByAppendingString:LBIDText(self.id)];
    if (before) name = [name stringByAppendingFormat:@" after %lu", (unsigned long)before];
    Reminder *first = LBNewReminder(self.vehicle, LBNamedUUID(name), self.managedObjectContext);
    if (!first) {
        LBFail(error, @"The schedule was started so already");
        return nil;
    }
    first.schedule = self;
    first.enteredBy = user;
    first.setAt = now;
    first.dueDate = dueDate;
    first.dueMileageQuantity = dueMileage;
    first.dueMileageDistanceUnit = dueUnit;
    return first;
}

@end

#pragma mark Reminders

@implementation Reminder (LBProcedures)

- (BOOL)lb_isOpen {
    return !self.doneAt && !self.cancelDate;
}

- (NSString *)lb_task {
    return self.schedule ? self.schedule.task : self.task;
}

- (ExpenseKind *)lb_expenseKind {
    return self.schedule ? self.schedule.expenseKind : self.expenseKind;
}

- (Checklist *)lb_checklist {
    return self.schedule ? self.schedule.checklist : self.checklist;
}

- (NSUUID *)lb_nextID {
    return self.id ? LBNamedUUID([@"next of " stringByAppendingString:LBIDText(self.id)]) : nil;
}

- (Reminder *)lb_nextReminder {
    NSUUID *next = [self lb_nextID];
    if (!next || !self.schedule) return nil;
    for (Reminder *reminder in self.schedule.reminders) {
        if (!reminder.isDeleted && [reminder.id isEqual:next]) return reminder;
    }
    return nil;
}

/* Whether the next reminder is as closing this one, at what it was done
   at now, made it. */
- (BOOL)lb_isUntouchedNext:(Reminder *)next {
    for (Rescheduling *moved in next.reschedulings) {
        if (!moved.isDeleted) return NO;
    }
    for (Attachment *attached in next.attachments) {
        if (!attached.isDeleted) return NO;
    }
    if (next.doneAt || next.cancelDate || next.replaced || next.replacement || next.note.length || !self.doneAt) return NO;
    NSDate *dueDate;
    NSDecimalNumber *dueMileage;
    DistanceUnit *dueUnit;
    LBDueAfter(next.schedule, self.vehicle, self.doneAt, self.doneMileageQuantity, self.doneMileageDistanceUnit, &dueDate, &dueMileage,
               &dueUnit);
    return LBSameDate(next.dueDate, dueDate) && LBSameDistance(next.dueMileageQuantity, next.dueMileageDistanceUnit, dueMileage, dueUnit);
}

- (BOOL)lb_nextReminderUntouched {
    Reminder *next = self.lb_nextReminder;
    return next && [self lb_isUntouchedNext:next];
}

/* Done at the moment and distance, by the event (nil: by hand). */
- (void)lb_doneBy:(Event *)event at:(NSDate *)moment mileage:(NSDecimalNumber *)mileage unit:(DistanceUnit *)unit {
    self.event = event;
    self.doneAt = moment;
    self.doneMileageQuantity = mileage && unit ? mileage : nil;
    self.doneMileageDistanceUnit = mileage && unit ? unit : nil;
}

/* The next reminder due again from what this one was done at now. */
- (void)lb_dueNext:(Reminder *)next {
    NSDate *dueDate;
    NSDecimalNumber *dueMileage;
    DistanceUnit *dueUnit;
    LBDueAfter(next.schedule, self.vehicle, self.doneAt, self.doneMileageQuantity, self.doneMileageDistanceUnit, &dueDate, &dueMileage,
               &dueUnit);
    next.setAt = self.doneAt;
    next.dueDate = dueDate;
    next.dueMileageQuantity = dueMileage;
    next.dueMileageDistanceUnit = dueUnit;
}

/* Reopened, as before it was done. */
- (void)lb_reopen {
    [self lb_doneBy:nil at:nil mileage:nil unit:nil];
}

- (BOOL)lb_completeByEvent:(Event *)event at:(NSDate *)moment mileage:(NSDecimalNumber *)mileage unit:(DistanceUnit *)unit by:(User *)user
                      next:(Reminder **)next error:(NSError **)error {
    if (next) *next = nil;
    if (self.doneAt) return LBFail(error, @"The reminder is done already");
    if (self.cancelDate) return LBFail(error, @"A cancelled reminder is not done");
    if (event) {
        if (![event lb_mayCloseReminder:self]) {
            return LBFail(error, @"That event does not do the reminder's work, of its vehicle, on or after the day it was set");
        }
        moment = event.timestamp;
        mileage = event.mileageQuantity;
        unit = event.mileageDistanceUnit;
    } else if ((mileage == nil) != (unit == nil)) {
        return LBFail(error, @"A distance is a quantity and its unit");
    }
    if (!moment) moment = [NSDate date];
    Schedule *schedule = self.schedule;
    NSDate *dueDate = nil;
    NSDecimalNumber *dueMileage = nil;
    DistanceUnit *dueUnit = nil;
    if (schedule) {
        if (!self.id) return LBFail(error, @"The reminder has no id yet");
        LBDueAfter(schedule, self.vehicle, moment, mileage && unit ? mileage : nil, mileage && unit ? unit : nil, &dueDate, &dueMileage,
                   &dueUnit);
        if (!dueDate && !dueMileage) {
            return LBFail(error, @"There is no distance to count the next reminder from: say the distance it was done at");
        }
    }
    Reminder *made = nil;
    if (schedule) {
        made = LBNewReminder(self.vehicle, [self lb_nextID], self.managedObjectContext);
        if (!made) return LBFail(error, @"The reminder's next was made already");
        made.schedule = schedule;
        made.enteredBy = user;
        made.setAt = moment;
        made.dueDate = dueDate;
        made.dueMileageQuantity = dueMileage;
        made.dueMileageDistanceUnit = dueUnit;
    }
    [self lb_doneBy:event at:moment mileage:mileage unit:unit];
    if (next) *next = made;
    return YES;
}

- (Rescheduling *)lb_rescheduleToDate:(NSDate *)date mileage:(NSDecimalNumber *)mileage unit:(DistanceUnit *)unit note:(NSString *)note
                                   by:(User *)user at:(NSDate *)now error:(NSError **)error {
    if (!self.lb_isOpen) {
        LBFail(error, @"Only an open reminder is moved");
        return nil;
    }
    if (!self.id) {
        LBFail(error, @"The reminder has no id yet");
        return nil;
    }
    if (mileage && !unit) unit = self.dueMileageDistanceUnit;
    if ((mileage == nil) != (unit == nil)) {
        LBFail(error, @"A distance is a quantity and its unit");
        return nil;
    }
    NSDate *day = date ? LBDay(date) : nil;
    BOOL dateMoves = day && !LBSameDate(day, self.dueDate);
    BOOL mileageMoves = mileage && !LBSameDistance(mileage, unit, self.dueMileageQuantity, self.dueMileageDistanceUnit);
    if (!dateMoves && !mileageMoves) {
        LBFail(error, @"The reminder is due there already");
        return nil;
    }
    NSUInteger before = 0;
    for (Rescheduling *moved in self.reschedulings) {
        if (!moved.isDeleted) before++;
    }
    Rescheduling *move = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Rescheduling class])
                                                       inManagedObjectContext:self.managedObjectContext];
    move.id = LBNamedUUID([NSString stringWithFormat:@"%@ rescheduled %lu", LBIDText(self.id), (unsigned long)before + 1]);
    move.reminder = self;
    move.madeAt = now;
    move.madeBy = user;
    move.note = note.length ? note : nil;
    if (dateMoves) move.fromDate = self.dueDate;
    if (mileageMoves) {
        move.fromMileageQuantity = self.dueMileageQuantity;
        move.fromMileageDistanceUnit = self.dueMileageDistanceUnit;
    }
    /* Due on a day, or at a distance, where it was due at none: what it was
       due at, the other, is what it moved from. */
    if (!move.fromDate && !move.fromMileageQuantity) {
        move.fromDate = self.dueDate;
        move.fromMileageQuantity = self.dueMileageQuantity;
        move.fromMileageDistanceUnit = self.dueMileageDistanceUnit;
    }
    if (dateMoves) self.dueDate = day;
    if (mileageMoves) {
        self.dueMileageQuantity = mileage;
        self.dueMileageDistanceUnit = unit;
    }
    return move;
}

- (BOOL)lb_cancelOn:(NSDate *)day replacementDueDate:(NSDate *)dueDate mileage:(NSDecimalNumber *)mileage unit:(DistanceUnit *)unit
                 by:(User *)user at:(NSDate *)now replacement:(Reminder **)replacement error:(NSError **)error {
    if (replacement) *replacement = nil;
    if (!self.lb_isOpen) return LBFail(error, @"Only an open reminder is cancelled");
    if (mileage && !unit) unit = self.dueMileageDistanceUnit;
    if ((mileage == nil) != (unit == nil)) return LBFail(error, @"A distance is a quantity and its unit");
    Reminder *made = nil;
    if (dueDate || mileage) {
        if (!self.id) return LBFail(error, @"The reminder has no id yet");
        made = LBNewReminder(self.vehicle, LBNamedUUID([@"replacement of " stringByAppendingString:LBIDText(self.id)]),
                             self.managedObjectContext);
        if (!made) return LBFail(error, @"The reminder's replacement was made already");
        if (self.schedule) {
            made.schedule = self.schedule;
        } else {
            made.task = self.task;
            made.expenseKind = self.expenseKind;
            made.checklist = self.checklist;
        }
        made.enteredBy = user;
        made.setAt = now;
        made.dueDate = dueDate ? LBDay(dueDate) : nil;
        made.dueMileageQuantity = mileage;
        made.dueMileageDistanceUnit = mileage ? unit : nil;
        made.replaced = self;
    }
    self.cancelDate = LBDay(day ?: now);
    if (replacement) *replacement = made;
    return YES;
}

@end

#pragma mark Undoing what an event closed

/* Each reminder reopened, and the next its closing made deleted, where
   untouched; where touched, as keep says (nil: refused, before anything is
   changed). */
static BOOL LBUndoClosing(NSArray<Reminder *> *reminders, NSNumber *keep, NSError **error) {
    NSMutableArray<Reminder *> *touched = [NSMutableArray array];
    for (Reminder *reminder in reminders) {
        Reminder *next = reminder.lb_nextReminder;
        if (next && ![reminder lb_isUntouchedNext:next]) [touched addObject:next];
    }
    if (touched.count && !keep) {
        if (error) {
            NSString *what = touched.count == 1 ? @"The reminder it made next has been changed since"
                                                : @"The reminders it made next have been changed since";
            *error = [NSError errorWithDomain:LBProceduresErrorDomain code:LBProceduresErrorNextReminderTouched
                                     userInfo:@{ NSLocalizedDescriptionKey: [what stringByAppendingString:@": keep it, or delete it too?"],
                                                 LBNextRemindersErrorKey: touched }];
        }
        return NO;
    }
    for (Reminder *reminder in reminders) {
        Reminder *next = reminder.lb_nextReminder;
        if (next && [touched containsObject:next] && keep.boolValue) {
            /* The next kept: this one stays done, by hand. */
            reminder.event = nil;
            continue;
        }
        if (next) {
            for (Rescheduling *moved in [next.reschedulings copy]) [next.managedObjectContext deleteObject:moved];
            for (Attachment *attached in [next.attachments copy]) [next.managedObjectContext deleteObject:attached];
            [next.managedObjectContext deleteObject:next];
        }
        [reminder lb_reopen];
    }
    /* What was deleted taken out of what it was in (its schedule's
       reminders), as a save would: the rules are checked before it. */
    [reminders.firstObject.managedObjectContext processPendingChanges];
    return YES;
}

@implementation Record (LBProcedures)

- (BOOL)lb_discardKeepingNextReminders:(NSNumber *)keep error:(NSError **)error {
    if ([self isKindOfClass:[Event class]]) {
        NSArray *closed = [((Event *)self).reminders.allObjects sortedArrayUsingFunction:LBIDOrder context:NULL];
        NSMutableArray *kept = [NSMutableArray array];
        for (Reminder *reminder in closed) {
            if (!reminder.isDeleted) [kept addObject:reminder];
        }
        if (!LBUndoClosing(kept, keep, error)) return NO;
    }
    [self.managedObjectContext deleteObject:self];
    return YES;
}

@end

#pragma mark Automatic completion

/* What an event closed and can no longer, undone; what it still does, at
   its moment and distance now. */
static BOOL LBFollowEvent(Event *event, NSError **error) {
    NSArray *closed = [event.reminders.allObjects sortedArrayUsingFunction:LBIDOrder context:NULL];
    NSMutableArray *undone = [NSMutableArray array];
    for (Reminder *reminder in closed) {
        if (reminder.isDeleted) continue;
        if (![event lb_mayCloseReminder:reminder]) {
            [undone addObject:reminder];
            continue;
        }
        NSDecimalNumber *mileage = event.mileageDistanceUnit ? event.mileageQuantity : nil;
        if (LBSameDate(reminder.doneAt, event.timestamp)
            && LBSameDistance(reminder.doneMileageQuantity, reminder.doneMileageDistanceUnit, mileage, mileage ? event.mileageDistanceUnit : nil)) {
            continue;
        }
        Reminder *next = reminder.lb_nextReminder;
        BOOL untouched = next && [reminder lb_isUntouchedNext:next];
        [reminder lb_doneBy:event at:event.timestamp mileage:mileage unit:event.mileageDistanceUnit];
        if (untouched) [reminder lb_dueNext:next];
    }
    return LBUndoClosing(undone, nil, error);
}

/* For each schedule of the event's work, and each one-off reminder of it,
   the reminder it closes: of those it may close, open or done by a later
   event, the one set first. */
static void LBCloseByEvent(Event *event) {
    if (event.isDeleted || !event.vehicle || !event.timestamp) return;
    NSMutableDictionary<NSString *, NSMutableArray<Reminder *> *> *lines = [NSMutableDictionary dictionary];
    for (Record *record in event.vehicle.records) {
        if (![record isKindOfClass:[Reminder class]] || ![event lb_mayCloseReminder:(Reminder *)record]) continue;
        Reminder *reminder = (Reminder *)record;
        NSString *line = LBIDText(reminder.schedule ? reminder.schedule.id : reminder.id);
        if (!lines[line]) lines[line] = [NSMutableArray array];
        [lines[line] addObject:reminder];
    }
    for (NSString *line in [lines.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray *reminders = [lines[line] sortedArrayUsingFunction:LBReminderOrder context:NULL];
        Reminder *chosen = nil;
        BOOL closesOne = NO;
        for (Reminder *reminder in reminders) {
            if (reminder.event == event) closesOne = YES;
            BOOL takes = reminder.lb_isOpen || (reminder.event && [event lb_isBeforeEvent:reminder.event]);
            if (takes && !chosen) chosen = reminder;
        }
        if (closesOne || !chosen) continue;
        if (chosen.lb_isOpen) {
            /* One that cannot be closed so (its next due at nothing) stays
               open, for the owner to close by hand. */
            [chosen lb_completeByEvent:event at:nil mileage:nil unit:nil by:LBActorOf(event) next:NULL error:NULL];
            continue;
        }
        /* Taken from the later event that closed it, with its next as it was
           made, due from this one now; the later one then closes what it
           may, in turn. */
        Event *later = chosen.event;
        Reminder *next = chosen.lb_nextReminder;
        if (next && ![chosen lb_isUntouchedNext:next]) continue;
        [chosen lb_doneBy:event at:event.timestamp mileage:event.mileageQuantity unit:event.mileageDistanceUnit];
        if (next) [chosen lb_dueNext:next];
        LBCloseByEvent(later);
    }
}

/* Whether an event saved changes what it does: new, or changed in its
   moment, vehicle, distance, kind, checklist or items. */
static BOOL LBChangesWork(Event *event) {
    if (event.isInserted) return YES;
    NSSet<NSString *> *keys = [NSSet setWithObjects:NSStringFromSelector(@selector(timestamp)), NSStringFromSelector(@selector(vehicle)),
                                                    NSStringFromSelector(@selector(mileageQuantity)),
                                                    NSStringFromSelector(@selector(mileageDistanceUnit)), NSStringFromSelector(@selector(expenseKind)),
                                                    NSStringFromSelector(@selector(checklist)), NSStringFromSelector(@selector(serviceItems)), nil];
    return [keys intersectsSet:[NSSet setWithArray:event.changedValues.allKeys]];
}

@implementation NSManagedObjectContext (LBProcedures)

- (BOOL)lb_completeRemindersOfChangedEvents:(NSError **)error {
    NSMutableSet<Event *> *changed = [NSMutableSet set];
    NSMutableSet *objects = [NSMutableSet setWithSet:self.insertedObjects];
    [objects unionSet:self.updatedObjects];
    for (NSManagedObject *object in objects) {
        if ([object isKindOfClass:[Event class]] && LBChangesWork((Event *)object)) [changed addObject:(Event *)object];
        /* A service's item added, or changed to another task. */
        if ([object isKindOfClass:[ServiceItem class]]) {
            ServiceItem *item = (ServiceItem *)object;
            NSDictionary *changes = item.changedValues;
            if (item.service && (item.isInserted || changes[NSStringFromSelector(@selector(task))]
                                 || changes[NSStringFromSelector(@selector(service))])) {
                [changed addObject:item.service];
            }
        }
    }
    NSMutableArray<Event *> *events = [NSMutableArray array];
    for (Event *event in changed) {
        if (!event.isDeleted && event.timestamp) [events addObject:event];
    }
    [events sortUsingFunction:LBEventOrder context:NULL];
    for (Event *event in events) {
        if (!LBFollowEvent(event, error)) return NO;
    }
    for (Event *event in events) LBCloseByEvent(event);
    return YES;
}

@end
