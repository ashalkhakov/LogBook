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
        /* Of it now: one moved to another vehicle may still be among its
           records until the save (FreeCoreData keeps inverses so). */
        if ([record isKindOfClass:[Event class]] && !record.isDeleted && record.vehicle == vehicle && ((Event *)record).timestamp) {
            [events addObject:record];
        }
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

/* What closing a schedule's reminder by the event makes due next: the day
   plus its months; the event's distance plus its interval, in the event's
   unit. NO, and nothing is made, for a schedule that recurs after a
   distance and an event at none. */
static BOOL LBNextDue(Schedule *schedule, Event *event, NSDate **dueDate, NSDecimalNumber **dueMileage, DistanceUnit **dueUnit) {
    *dueDate = schedule.duration > 0 ? LBAddMonths(LBDay(event.timestamp), schedule.duration) : nil;
    *dueMileage = nil;
    *dueUnit = nil;
    if (schedule.intervalQuantity && schedule.intervalDistanceUnit) {
        if (!event.mileageQuantity || !event.mileageDistanceUnit) return NO;
        *dueMileage = [event.mileageQuantity
            decimalNumberByAdding:LBInUnit(schedule.intervalQuantity, schedule.intervalDistanceUnit, event.mileageDistanceUnit)];
        *dueUnit = event.mileageDistanceUnit;
    }
    return *dueDate || *dueMileage;
}

static NSUUID *LBNextIDOf(NSUUID *uuid) {
    return uuid ? LBNamedUUID([@"next of " stringByAppendingString:LBIDText(uuid)]) : nil;
}

/* Whether the reminder is done as the event would do it (nil: open). */
static BOOL LBDoneAsBy(Reminder *reminder, Event *event) {
    if (!event) return !reminder.doneAt && !reminder.event;
    NSDecimalNumber *mileage = event.mileageDistanceUnit ? event.mileageQuantity : nil;
    return reminder.event == event && LBSameDate(reminder.doneAt, event.timestamp)
        && LBSameDistance(reminder.doneMileageQuantity, reminder.doneMileageDistanceUnit, mileage, mileage ? event.mileageDistanceUnit : nil);
}

static void LBDoneBy(Reminder *reminder, Event *event) {
    BOOL measured = event.mileageQuantity && event.mileageDistanceUnit;
    reminder.event = event;
    reminder.doneAt = event.timestamp;
    reminder.doneMileageQuantity = measured ? event.mileageQuantity : nil;
    reminder.doneMileageDistanceUnit = measured ? event.mileageDistanceUnit : nil;
}

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

- (Reminder *)lb_nextReminder {
    NSUUID *next = LBNextIDOf(self.id);
    if (!next || !self.schedule) return nil;
    for (Reminder *reminder in self.schedule.reminders) {
        if (!reminder.isDeleted && [reminder.id isEqual:next]) return reminder;
    }
    return nil;
}

- (BOOL)lb_isTouched {
    for (Rescheduling *moved in self.reschedulings) {
        if (!moved.isDeleted) return YES;
    }
    for (Attachment *attached in self.attachments) {
        if (!attached.isDeleted) return YES;
    }
    return self.note.length || self.cancelDate || (self.replaced && !self.replaced.isDeleted)
        || (self.replacement && !self.replacement.isDeleted);
}

- (BOOL)lb_completeByEvent:(Event *)event next:(Reminder **)next error:(NSError **)error {
    if (next) *next = nil;
    if (self.doneAt) return LBFail(error, @"The reminder is done already");
    if (self.cancelDate) return LBFail(error, @"A cancelled reminder is not done");
    if (!event) return LBFail(error, @"A reminder is done by an event: say which");
    if (![event lb_mayCloseReminder:self]) {
        return LBFail(error, @"That event does not do the reminder's work, of its vehicle, on or after the day it was set");
    }
    if (![self.managedObjectContext lb_settleVehicles:[NSSet setWithObject:self.vehicle] without:nil force:NO error:error]) return NO;
    if (!self.event) return LBFail(error, @"The reminder is not closed by that event: an earlier one of its schedule is open");
    if (next) *next = self.lb_nextReminder;
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

#pragma mark Settling: what a vehicle's events close

/* A reminder deleted, with what is of it (its moves, its attachments),
   taken out of its schedule and vehicle first: the rules, checked before
   the save propagates a deletion, see the schedule without it. */
static void LBDeleteReminder(Reminder *reminder) {
    NSManagedObjectContext *context = reminder.managedObjectContext;
    for (Rescheduling *moved in [reminder.reschedulings copy]) {
        moved.reminder = nil;
        [context deleteObject:moved];
    }
    for (Attachment *attached in [reminder.attachments copy]) {
        attached.record = nil;
        [context deleteObject:attached];
    }
    reminder.schedule = nil;
    reminder.vehicle = nil;
    reminder.replaced = nil;
    reminder.replacement = nil;
    [context deleteObject:reminder];
}

/* A place in a schedule's run of reminders: a reminder there, or the next
   one that closing the one before makes, not made yet. */
@interface LBSlot : NSObject
@property (nonatomic, strong) Reminder *reminder;
@property (nonatomic, strong) NSUUID *uuid;
// Whose closing makes it (a next one); nil for a first reminder, a
// replacement, or one left as it is.
@property (nonatomic, strong) LBSlot *source;
// What closes it; nil: open.
@property (nonatomic, strong) Event *event;
// Left as it is: cancelled, or done with no event.
@property (nonatomic) BOOL fixed;
// Its source closed otherwise than it is: it is due anew.
@property (nonatomic) BOOL dueAnew;
@end

@implementation LBSlot
@end

/* A schedule's run: its reminders and events, as entering its vehicle's
   events afresh, in order, leaves them. */
@interface LBRun : NSObject
@property (nonatomic, strong) Schedule *schedule;
@property (nonatomic, strong) NSMutableArray<LBSlot *> *slots;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, Reminder *> *byID;
@property (nonatomic, strong) NSMutableSet<NSUUID *> *nextIDs;
@property (nonatomic, strong) NSArray<Reminder *> *roots;
@property (nonatomic) NSUInteger nextRoot;
@end

@implementation LBRun

- (LBSlot *)slotOf:(Reminder *)reminder uuid:(NSUUID *)uuid source:(LBSlot *)source {
    for (LBSlot *slot in _slots) {
        if (reminder && slot.reminder == reminder) return nil;   /* no reminder twice: a cycle */
    }
    LBSlot *slot = [[LBSlot alloc] init];
    slot.reminder = reminder;
    slot.uuid = reminder.id ?: uuid;
    slot.source = source;
    slot.fixed = reminder && (reminder.cancelDate || (reminder.doneAt && !reminder.event));
    [_slots addObject:slot];
    return slot;
}

- (LBSlot *)takeRoot {
    while (_nextRoot < _roots.count) {
        LBSlot *slot = [self slotOf:_roots[_nextRoot++] uuid:nil source:nil];
        if (slot) return slot;
    }
    return nil;
}

/* From the slot, the first that an event may close: past a cancelled one
   to its replacement, past one done with no event to its next, as they
   are; else the next first reminder. */
- (LBSlot *)openFrom:(LBSlot *)slot {
    while (slot && slot.fixed) {
        Reminder *reminder = slot.reminder;
        Reminder *after = reminder.cancelDate ? reminder.replacement : _byID[LBNextIDOf(reminder.id) ?: [NSUUID UUID]];
        slot = after && !after.isDeleted ? [self slotOf:after uuid:nil source:nil] : [self takeRoot];
    }
    return slot;
}

- (instancetype)initWithSchedule:(Schedule *)schedule events:(NSArray<Event *> *)events {
    if (!(self = [super init])) return nil;
    _schedule = schedule;
    _slots = [NSMutableArray array];
    _byID = [NSMutableDictionary dictionary];
    _nextIDs = [NSMutableSet set];
    NSMutableArray *reminders = [NSMutableArray array];
    for (Reminder *reminder in schedule.reminders) {
        if (reminder.isDeleted) continue;
        [reminders addObject:reminder];
        if (reminder.id) {
            _byID[reminder.id] = reminder;
            [_nextIDs addObject:LBNextIDOf(reminder.id)];
        }
    }
    [reminders sortUsingFunction:LBReminderOrder context:NULL];
    NSMutableArray *roots = [NSMutableArray array];
    for (Reminder *reminder in reminders) {
        BOOL replaces = reminder.replaced && !reminder.replaced.isDeleted;
        if (![_nextIDs containsObject:reminder.id ?: [NSUUID UUID]] && !replaces) [roots addObject:reminder];
    }
    _roots = roots;
    LBSlot *slot = [self takeRoot];
    for (Event *event in events) {
        slot = [self openFrom:slot];
        if (!slot) break;
        if (!LBDoesWork(event, schedule.task, schedule.expenseKind, schedule.checklist)) continue;
        NSDate *setAt = slot.reminder ? slot.reminder.setAt : slot.source.event.timestamp;
        if (!setAt || [LBDay(setAt) compare:LBDay(event.timestamp)] == NSOrderedDescending) continue;
        slot.event = event;
        NSDate *dueDate;
        NSDecimalNumber *dueMileage;
        DistanceUnit *dueUnit;
        if (LBNextDue(schedule, event, &dueDate, &dueMileage, &dueUnit)) {
            NSUUID *next = LBNextIDOf(slot.uuid);
            LBSlot *made = [self slotOf:_byID[next] uuid:next source:slot];
            slot = made ?: [self takeRoot];
        } else {
            slot = [self takeRoot];
        }
    }
    /* A next whose source closes otherwise than it is now is due anew. */
    for (LBSlot *each in _slots) {
        each.dueAnew = each.source && (!each.reminder || !each.source.reminder || !LBDoneAsBy(each.source.reminder, each.source.event));
    }
    return self;
}

/* The schedule's reminders that the run leaves out: the next ones of
   reminders it does not close. */
- (NSArray<Reminder *> *)left {
    NSMutableSet *run = [NSMutableSet set];
    for (LBSlot *slot in _slots) {
        if (slot.reminder) [run addObject:slot.reminder];
    }
    NSMutableArray *left = [NSMutableArray array];
    for (Reminder *reminder in [_byID.allValues sortedArrayUsingFunction:LBReminderOrder context:NULL]) {
        if (![run containsObject:reminder] && [_nextIDs containsObject:reminder.id]) [left addObject:reminder];
    }
    return left;
}

/* The reminders the user changed that the run would change. */
- (void)addTouchedTo:(NSMutableArray<Reminder *> *)touched {
    for (LBSlot *slot in _slots) {
        if (slot.reminder && slot.dueAnew && slot.reminder.lb_isTouched) [touched addObject:slot.reminder];
    }
    for (Reminder *reminder in [self left]) {
        if (reminder.lb_isTouched) [touched addObject:reminder];
    }
}

- (void)apply {
    Vehicle *vehicle = _schedule.vehicle;
    for (LBSlot *slot in _slots) {
        Reminder *reminder = slot.reminder;
        if (slot.dueAnew) {
            Event *source = slot.source.event;
            if (!reminder) {
                reminder = LBNewReminder(vehicle, slot.uuid, _schedule.managedObjectContext);
                if (!reminder) continue;
                reminder.schedule = _schedule;
                reminder.enteredBy = LBActorOf(source);
                slot.reminder = reminder;
            }
            NSDate *dueDate;
            NSDecimalNumber *dueMileage;
            DistanceUnit *dueUnit;
            LBNextDue(_schedule, source, &dueDate, &dueMileage, &dueUnit);
            reminder.setAt = source.timestamp;
            reminder.dueDate = dueDate;
            reminder.dueMileageQuantity = dueMileage;
            reminder.dueMileageDistanceUnit = dueUnit;
        }
        if (slot.fixed || !reminder || LBDoneAsBy(reminder, slot.event)) continue;
        if (slot.event) {
            LBDoneBy(reminder, slot.event);
        } else {
            reminder.event = nil;
            reminder.doneAt = nil;
            reminder.doneMileageQuantity = nil;
            reminder.doneMileageDistanceUnit = nil;
        }
    }
    for (Reminder *reminder in [self left]) LBDeleteReminder(reminder);
    /* Done by an event no longer of the run (a first reminder past where
       the run ended): open. */
    for (Reminder *reminder in _byID.allValues) {
        if (reminder.isDeleted || !reminder.event) continue;
        BOOL inRun = NO;
        for (LBSlot *slot in _slots) {
            if (slot.reminder == reminder) inRun = YES;
        }
        if (!inRun) {
            reminder.event = nil;
            reminder.doneAt = nil;
            reminder.doneMileageQuantity = nil;
            reminder.doneMileageDistanceUnit = nil;
        }
    }
}

@end

/* A one-off reminder: closed by the first of the events that may close it;
   one cancelled, or done with no event, as it is. */
static Event *LBFirstCloser(Reminder *reminder, NSArray<Event *> *events) {
    for (Event *event in events) {
        if (!reminder.setAt || [LBDay(reminder.setAt) compare:LBDay(event.timestamp)] == NSOrderedDescending) continue;
        if (LBDoesWork(event, reminder.task, reminder.expenseKind, reminder.checklist)) return event;
    }
    return nil;
}

@implementation NSManagedObjectContext (LBSettling)

- (BOOL)lb_settleVehicles:(NSSet<Vehicle *> *)vehicles without:(Event *)without force:(BOOL)force error:(NSError **)error {
    NSMutableArray<LBRun *> *runs = [NSMutableArray array];
    NSMutableArray<NSArray *> *oneOffs = [NSMutableArray array];   /* reminder, its closer (or NSNull) */
    NSMutableArray<Reminder *> *touched = [NSMutableArray array];
    for (Vehicle *vehicle in [vehicles.allObjects sortedArrayUsingFunction:LBIDOrder context:NULL]) {
        if (vehicle.isDeleted) continue;
        NSMutableArray<Event *> *events = [NSMutableArray array];
        for (Event *event in LBEventsOf(vehicle)) {
            if (event != without) [events addObject:event];
        }
        [events sortUsingFunction:LBEventOrder context:NULL];
        NSArray *records = [vehicle.records.allObjects sortedArrayUsingFunction:LBIDOrder context:NULL];
        for (Record *record in records) {
            if (record.isDeleted || record.vehicle != vehicle) continue;
            if ([record isKindOfClass:[Schedule class]]) {
                LBRun *run = [[LBRun alloc] initWithSchedule:(Schedule *)record events:events];
                [run addTouchedTo:touched];
                [runs addObject:run];
            } else if ([record isKindOfClass:[Reminder class]] && !((Reminder *)record).schedule) {
                Reminder *reminder = (Reminder *)record;
                if (reminder.cancelDate || (reminder.doneAt && !reminder.event)) continue;
                [oneOffs addObject:@[ reminder, LBFirstCloser(reminder, events) ?: [NSNull null] ]];
            }
        }
    }
    if (touched.count && !force) {
        if (error) {
            NSString *what = touched.count == 1 ? @"A reminder made next has been changed since, and would have to change"
                                                : @"Reminders made next have been changed since, and would have to change";
            *error = [NSError errorWithDomain:LBProceduresErrorDomain code:LBProceduresErrorNextReminderTouched
                                     userInfo:@{ NSLocalizedDescriptionKey: [what stringByAppendingString:@": delete them too?"],
                                                 LBNextRemindersErrorKey: touched }];
        }
        return NO;
    }
    for (LBRun *run in runs) [run apply];
    for (NSArray *oneOff in oneOffs) {
        Reminder *reminder = oneOff[0];
        Event *closer = oneOff[1] == [NSNull null] ? nil : oneOff[1];
        if (LBDoneAsBy(reminder, closer)) continue;
        if (closer) {
            LBDoneBy(reminder, closer);
        } else {
            reminder.event = nil;
            reminder.doneAt = nil;
            reminder.doneMileageQuantity = nil;
            reminder.doneMileageDistanceUnit = nil;
        }
    }
    return YES;
}

@end

@implementation Record (LBProcedures)

- (BOOL)lb_discardKeepingNextReminders:(NSNumber *)keep error:(NSError **)error {
    if (keep.boolValue) {
        return LBFail(error, @"A reminder is done only by an event: the next one is kept only if the record is; delete it too, or keep "
                             @"the record");
    }
    if ([self isKindOfClass:[Event class]] && self.vehicle) {
        if (![self.managedObjectContext lb_settleVehicles:[NSSet setWithObject:self.vehicle] without:(Event *)self force:keep != nil
                                                    error:error]) {
            return NO;
        }
    }
    [self.managedObjectContext deleteObject:self];
    return YES;
}

@end

#pragma mark Automatic completion

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
    NSMutableSet<Vehicle *> *vehicles = [NSMutableSet set];
    NSString *vehicleKey = NSStringFromSelector(@selector(vehicle));
    NSMutableSet *objects = [NSMutableSet setWithSet:self.insertedObjects];
    [objects unionSet:self.updatedObjects];
    for (NSManagedObject *object in objects) {
        Event *event = nil;
        if ([object isKindOfClass:[Event class]] && LBChangesWork((Event *)object)) event = (Event *)object;
        /* A service's item added, or changed to another task. */
        if ([object isKindOfClass:[ServiceItem class]]) {
            ServiceItem *item = (ServiceItem *)object;
            NSDictionary *changes = item.changedValues;
            if (item.isInserted || changes[NSStringFromSelector(@selector(task))] || changes[NSStringFromSelector(@selector(service))]) {
                event = item.service;
            }
        }
        if (!event || event.isDeleted) continue;
        if (event.vehicle) [vehicles addObject:event.vehicle];
        /* Moved from another vehicle: that one's too, and those of the
           reminders it closed. */
        id before = event.isInserted ? nil : [event committedValuesForKeys:@[ vehicleKey ]][vehicleKey];
        if ([before isKindOfClass:[NSManagedObjectID class]]) before = [self objectWithID:before];
        if ([before isKindOfClass:[Vehicle class]]) [vehicles addObject:before];
        for (Reminder *reminder in event.reminders) {
            if (reminder.vehicle) [vehicles addObject:reminder.vehicle];
        }
    }
    return [self lb_settleVehicles:vehicles without:nil force:NO error:error];
}

@end
