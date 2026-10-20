// The procedures (Shared/LBProcedures.h) checked over a store of the
// model's own: a SQLite file of the generated Core Data model, the model's
// tables registered, each change saved as the server saves one (automatic
// completion, then the generated orm_prepareForSave:, then save:). Each
// check a line, "ok" or "FAIL"; 1 when one failed.
//
//   lb-procedures-check build/Logbook.momd build/Logbook.ormplans
//
// - names: a name-based id is Python's uuid.uuid5 in Logbook's namespace;
// - determinism: two stores of the same objects, the same procedures run
//   on each, make the same objects, of the same ids;
// - a schedule started from now and the vehicle's latest distance, from the
//   last time its work was done, from what the owner says; an interval in
//   miles from a distance in kilometres;
// - closing by an event and by hand: done at its moment and distance, the
//   next due from them (ReminderNextDue agrees);
// - automatic completion: a service of the task closes the open reminder;
//   one of another vehicle, of another task, or from before the day the
//   reminder was set does not; an expense of the kind does; the earliest
//   event wins, whatever the order events are added in; an event changed
//   to no longer do the work reopens what it closed, one moved takes its
//   reminder's moment with it;
// - moved, cancelled and replaced; a record discarded: what it closed
//   reopened and the untouched next deleted, a touched one refused until
//   the owner says to keep it or delete it.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "LogbookValidation.h"
#import "LBProcedures.h"
#import "Vehicle+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "Expense+CoreDataClass.h"
#import "MeterReading+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"

static NSUInteger LBFailures;
static NSManagedObjectModel *LBModel;

static void LBCheck(NSString *what, BOOL ok, id detail) {
    printf("%s %s%s\n", ok ? "ok  " : "FAIL", what.UTF8String,
           ok || !detail ? "" : [[NSString stringWithFormat:@": %@", detail] UTF8String]);
    fflush(stdout);
    if (!ok) LBFailures++;
}

#pragma mark A store

/* A context over a new SQLite store, its reference data seeded. */
static NSManagedObjectContext *LBNewStore(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"lb-procedures-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:LBModel];
    NSError *error = nil;
    if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[NSURL fileURLWithPath:path] options:nil
                                           error:&error]) {
        printf("FAIL the store at %s: %s\n", path.UTF8String, error.localizedDescription.UTF8String);
        exit(1);
    }
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    if (![LogbookReferenceData seedContext:context error:&error] || ![context save:&error]) {
        printf("FAIL seeded: %s\n", error.localizedDescription.UTF8String);
        exit(1);
    }
    return context;
}

/* A save's failure, each violation said. */
static NSString *LBSaid(NSError *error) {
    NSArray *each = error.userInfo[NSDetailedErrorsKey];
    if (!each.count) return error.localizedDescription;
    NSMutableArray *said = [NSMutableArray array];
    for (NSError *e in each) [said addObject:e.localizedDescription];
    return [said componentsJoinedByString:@"; "];
}

/* Saved as the server saves: automatic completion, the model's rules. */
static BOOL LBSave(NSManagedObjectContext *context, NSString *what) {
    NSError *error = nil;
    BOOL saved = [context lb_completeRemindersOfChangedEvents:&error] && [context orm_prepareForSave:&error] && [context save:&error];
    if (!saved) {
        LBCheck([what stringByAppendingString:@" saved"], NO, LBSaid(error));
        [context rollback];
    }
    return saved;
}

#pragma mark Objects

static id LBInsert(Class cls, NSManagedObjectContext *context) {
    return [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass(cls) inManagedObjectContext:context];
}

static NSUUID *LBID(unsigned n) {
    return [[NSUUID alloc] initWithUUIDString:[NSString stringWithFormat:@"00000000-0000-0000-0000-%012x", n]];
}

static id LBFetchID(Class cls, NSUUID *uuid, NSManagedObjectContext *context) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(id)), uuid];
    return [[context executeFetchRequest:fetch error:NULL] firstObject];
}

static id LBFetchKey(Class cls, NSString *key, id value, NSManagedObjectContext *context) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", key, value];
    return [[context executeFetchRequest:fetch error:NULL] firstObject];
}

static DistanceUnit *LBUnit(NSString *code, NSManagedObjectContext *context) {
    return LBFetchKey([DistanceUnit class], NSStringFromSelector(@selector(code)), code, context);
}

static NSDate *LBMoment(NSString *text) {
    NSDateFormatter *iso = [[NSDateFormatter alloc] init];
    iso.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    iso.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    iso.dateFormat = text.length > 10 ? @"yyyy-MM-dd HH:mm" : @"yyyy-MM-dd";
    return [iso dateFromString:text];
}

static NSString *LBText(NSDate *date) {
    if (!date) return @"(none)";
    NSDateFormatter *iso = [[NSDateFormatter alloc] init];
    iso.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    iso.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    iso.dateFormat = @"yyyy-MM-dd HH:mm";
    return [iso stringFromDate:date];
}

static NSDecimalNumber *LBNumber(NSString *text) {
    return [NSDecimalNumber decimalNumberWithString:text];
}

static BOOL LBIs(NSDecimalNumber *number, NSString *text) {
    return number && [number compare:LBNumber(text)] == NSOrderedSame;
}

/* Anna, her Golf (id 1, or the one given), the kinds of cost a service and
   an expense are of. */
@interface LBWorld : NSObject
@property (nonatomic, strong) NSManagedObjectContext *context;
@property (nonatomic, strong) User *anna;
@property (nonatomic, strong) Vehicle *golf;
@property (nonatomic, strong) DistanceUnit *km;
@property (nonatomic, strong) DistanceUnit *mi;
@property (nonatomic, strong) CostKind *maintenance;
@property (nonatomic, strong) ExpenseKind *parking;
@end

@implementation LBWorld
@end

static Vehicle *LBVehicle(LBWorld *world, unsigned n, NSString *name) {
    Vehicle *vehicle = LBInsert([Vehicle class], world.context);
    vehicle.id = LBID(n);
    vehicle.vehicleName = name;
    vehicle.make = @"Volkswagen";
    vehicle.carModel = @"Golf VII";
    vehicle.manufactureYear = 2016;
    vehicle.fuel = @"Petrol";
    vehicle.owner = world.anna;
    return vehicle;
}

static LBWorld *LBNewWorld(void) {
    LBWorld *world = [[LBWorld alloc] init];
    world.context = LBNewStore();
    world.anna = LBInsert([User class], world.context);
    world.anna.email = @"anna@example.org";
    world.km = LBUnit(@"km", world.context);
    world.mi = LBUnit(@"mi", world.context);
    world.maintenance = LBInsert([CostKind class], world.context);
    world.maintenance.name = @"Maintenance";
    world.parking = LBInsert([ExpenseKind class], world.context);
    world.parking.name = @"Parking";
    world.golf = LBVehicle(world, 1, @"Golf");
    LBSave(world.context, @"the world");
    return world;
}

static void LBEvent(LBWorld *world, Event *event, Vehicle *vehicle, unsigned n, NSString *moment) {
    event.id = LBID(n);
    event.vehicle = vehicle ?: world.golf;
    event.enteredBy = world.anna;
    event.driver = world.anna;
    event.timestamp = LBMoment(moment);
}

/* A service at a moment and a distance, an item of each task. */
static Service *LBService(LBWorld *world, Vehicle *vehicle, unsigned n, NSString *moment, NSString *km, NSArray<NSString *> *tasks) {
    Service *service = LBInsert([Service class], world.context);
    LBEvent(world, service, vehicle, n, moment);
    service.mileageQuantity = LBNumber(km);
    service.mileageDistanceUnit = world.km;
    service.garage = @"Garage Müller";
    service.serviceKind = world.maintenance;
    service.currency = @"EUR";
    unsigned i = 0;
    for (NSString *task in tasks) {
        ServiceItem *item = LBInsert([ServiceItem class], world.context);
        item.id = LBID(n * 100 + ++i);
        item.task = task;
        item.costAmount = LBNumber(@"50");
        item.costCurrency = @"EUR";
        item.service = service;
    }
    return service;
}

static Expense *LBExpense(LBWorld *world, unsigned n, NSString *moment) {
    Expense *expense = LBInsert([Expense class], world.context);
    LBEvent(world, expense, nil, n, moment);
    expense.expenseKind = world.parking;
    expense.totalAmount = LBNumber(@"120");
    expense.totalCurrency = @"EUR";
    return expense;
}

static MeterReading *LBReading(LBWorld *world, unsigned n, NSString *moment, NSString *km) {
    MeterReading *reading = LBInsert([MeterReading class], world.context);
    LBEvent(world, reading, nil, n, moment);
    reading.mileageQuantity = LBNumber(km);
    reading.mileageDistanceUnit = world.km;
    return reading;
}

/* The oil every 15,000 km or 12 months, its id n. */
static Schedule *LBOilSchedule(LBWorld *world, unsigned n) {
    Schedule *schedule = LBInsert([Schedule class], world.context);
    schedule.id = LBID(n);
    schedule.vehicle = world.golf;
    schedule.enteredBy = world.anna;
    schedule.task = @"Oil change";
    schedule.intervalQuantity = LBNumber(@"15000");
    schedule.intervalDistanceUnit = world.km;
    schedule.duration = 12;
    return schedule;
}

static NSString *LBDue(Reminder *reminder) {
    return [NSString stringWithFormat:@"%@ %@ %@", LBText(reminder.dueDate), reminder.dueMileageQuantity ?: @"-",
                                      reminder.dueMileageDistanceUnit.code ?: @""];
}

static Reminder *LBReminder(NSUUID *uuid, LBWorld *world) {
    return LBFetchID([Reminder class], uuid, world.context);
}

static NSString *LBIDText(NSUUID *uuid) {
    return uuid.UUIDString.lowercaseString;
}

#pragma mark The checks

static void LBNames(void) {
    LBCheck(@"a name's id is uuid5 in Logbook's namespace",
            [LBNamedUUID(@"next of 00000000-0000-0000-0000-000000000001")
                isEqual:[[NSUUID alloc] initWithUUIDString:@"6b3d51c2-5387-5dc3-858e-ee27a8f00a28"]],
            LBNamedUUID(@"next of 00000000-0000-0000-0000-000000000001"));
    LBCheck(@"a day is the model's, in UTC", [LBDay(LBMoment(@"2026-06-01 23:30")) isEqualToDate:LBMoment(@"2026-06-01")], nil);
    LBCheck(@"months on: the last day of a shorter month",
            [LBAddMonths(LBMoment(@"2026-01-31"), 1) isEqualToDate:LBMoment(@"2026-02-28")], LBText(LBAddMonths(LBMoment(@"2026-01-31"), 1)));
}

/* The same procedures on two stores of the same objects: the same ids. */
static NSArray *LBRunAll(LBWorld *world) {
    NSMutableArray *made = [NSMutableArray array];
    Schedule *oil = LBOilSchedule(world, 10);
    LBReading(world, 20, @"2026-06-01 09:00", @"148000");
    LBSave(world.context, @"the schedule");
    NSDate *now = LBMoment(@"2026-06-02 10:00");
    Reminder *first = [oil lb_startFrom:nil mileage:nil unit:nil by:world.anna at:now error:NULL];
    LBSave(world.context, @"started");
    [made addObject:first.id ?: [NSNull null]];
    Service *service = LBService(world, nil, 30, @"2027-05-20 11:00", @"162400", @[ @"Oil change" ]);
    LBSave(world.context, @"the service");
    Reminder *next = first.lb_nextReminder;
    [made addObject:next.id ?: [NSNull null]];
    Rescheduling *moved = [next lb_rescheduleToDate:LBMoment(@"2028-07-01") mileage:nil unit:nil note:@"away" by:world.anna
                                                 at:LBMoment(@"2027-06-01 08:00") error:NULL];
    [made addObject:moved.id ?: [NSNull null]];
    Reminder *replacement = nil;
    [next lb_cancelOn:nil replacementDueDate:LBMoment(@"2028-08-01") mileage:nil unit:nil by:world.anna at:LBMoment(@"2027-06-02 08:00")
          replacement:&replacement error:NULL];
    [made addObject:replacement.id ?: [NSNull null]];
    LBSave(world.context, @"moved and cancelled");
    [made addObject:service.id];
    return made;
}

static void LBDeterminism(void) {
    NSArray *one = LBRunAll(LBNewWorld()), *other = LBRunAll(LBNewWorld());
    LBCheck(@"two stores, the same procedures: the same ids", [one isEqualToArray:other] && ![one containsObject:[NSNull null]],
            [NSString stringWithFormat:@"%@ / %@", one, other]);
    NSString *schedule = LBIDText(LBID(10));
    NSUUID *first = LBNamedUUID([@"start of " stringByAppendingString:schedule]);
    NSUUID *next = LBNamedUUID([@"next of " stringByAppendingString:LBIDText(first)]);
    NSArray *named = @[ first, next, LBNamedUUID([LBIDText(next) stringByAppendingString:@" rescheduled 1"]),
                        LBNamedUUID([@"replacement of " stringByAppendingString:LBIDText(next)]) ];
    LBCheck(@"each named by what it is made of", [[one subarrayWithRange:NSMakeRange(0, 4)] isEqualToArray:named], one);
}

static void LBStart(void) {
    LBWorld *world = LBNewWorld();
    Schedule *oil = LBOilSchedule(world, 10);
    LBReading(world, 20, @"2026-09-01 09:00", @"150000");
    LBSave(world.context, @"a schedule");
    NSDate *now = LBMoment(@"2026-10-20 18:00");
    NSError *error = nil;
    Reminder *first = [oil lb_startFrom:nil mileage:nil unit:nil by:world.anna at:now error:&error];
    LBCheck(@"started from now: due in 12 months, the latest distance plus 15000 km",
            [first.dueDate isEqualToDate:LBMoment(@"2027-10-20")] && LBIs(first.dueMileageQuantity, @"165000")
                && first.dueMileageDistanceUnit == world.km && [first.setAt isEqualToDate:now] && first.schedule == oil
                && first.vehicle == world.golf && first.enteredBy == world.anna,
            error ?: LBDue(first));
    LBCheck(@"saved", LBSave(world.context, @"the first reminder"), nil);
    LBCheck(@"the schedule's open reminder", oil.lb_openReminder == first, nil);
    LBCheck(@"started again is refused", ![oil lb_startFrom:nil mileage:nil unit:nil by:world.anna at:now error:&error]
                && error.code == LBProceduresErrorRefused, error);

    /* From the last time the work was done. */
    LBService(world, nil, 30, @"2026-06-01 10:00", @"148000", @[ @"Oil change", @"Air filter" ]);
    LBSave(world.context, @"an oil change before");
    Schedule *again = LBOilSchedule(world, 11);
    LBSave(world.context, @"another schedule");
    Reminder *counted = [again lb_startFrom:nil mileage:nil unit:nil by:world.anna at:now error:&error];
    LBCheck(@"from the last oil change: 2027-06-01, 163000 km",
            [counted.dueDate isEqualToDate:LBMoment(@"2027-06-01")] && LBIs(counted.dueMileageQuantity, @"163000"), error ?: LBDue(counted));
    [world.context rollback];

    /* From what the owner says, an interval in miles. */
    Schedule *miles = LBOilSchedule(world, 12);
    miles.intervalQuantity = LBNumber(@"10000");
    miles.intervalDistanceUnit = world.mi;
    miles.duration = 6;
    LBSave(world.context, @"a schedule in miles");
    Reminder *said = [miles lb_startFrom:LBMoment(@"2026-03-15 08:00") mileage:LBNumber(@"140000") unit:world.km by:world.anna at:now
                                   error:&error];
    LBCheck(@"from what the owner says, 10000 mi in km",
            [said.dueDate isEqualToDate:LBMoment(@"2026-09-15")] && LBIs(said.dueMileageQuantity, @"156093.44")
                && said.dueMileageDistanceUnit == world.km,
            error ?: LBDue(said));
    LBCheck(@"saved", LBSave(world.context, @"the reminder in miles"), nil);
}

static void LBComplete(void) {
    LBWorld *world = LBNewWorld();
    Schedule *oil = LBOilSchedule(world, 10);
    LBSave(world.context, @"a schedule");
    Reminder *first = [oil lb_startFrom:LBMoment(@"2026-06-01 10:00") mileage:LBNumber(@"148000") unit:world.km by:world.anna
                                     at:LBMoment(@"2026-06-02 10:00") error:NULL];
    Service *service = LBService(world, nil, 30, @"2027-05-20 11:00", @"162400", @[ @"Brakes" ]);
    LBSave(world.context, @"a service of the brakes");
    LBCheck(@"a service of another task closes nothing", first.lb_isOpen, nil);
    NSError *error = nil;
    Reminder *next = nil;
    LBCheck(@"nor is it let", ![first lb_completeByEvent:service next:&next error:&error], error);
    LBCheck(@"nor with no event", ![first lb_completeByEvent:nil next:&next error:&error], error);
    ServiceItem *item = LBInsert([ServiceItem class], world.context);
    item.id = LBID(3099);
    item.task = @"Oil change";
    item.costAmount = LBNumber(@"40");
    item.costCurrency = @"EUR";
    item.service = service;
    LBSave(world.context, @"the oil change added to it");
    next = first.lb_nextReminder;
    LBCheck(@"an item of the task added: closed by it, at its moment and distance",
            first.event == service && [first.doneAt isEqualToDate:service.timestamp] && LBIs(first.doneMileageQuantity, @"162400")
                && first.doneMileageDistanceUnit == world.km,
            LBText(first.doneAt));
    LBCheck(@"the next made: due 12 months and 15000 km on, set at the moment done",
            next && [next.dueDate isEqualToDate:LBMoment(@"2028-05-20")] && LBIs(next.dueMileageQuantity, @"177400")
                && [next.setAt isEqualToDate:service.timestamp] && next.schedule == oil && next.vehicle == world.golf && next.lb_isOpen,
            LBDue(next));
    LBCheck(@"untouched", !next.lb_isTouched, nil);
    ORMQueryResult *nextDue = [LogbookQueries reminderNextDueInContext:world.context error:&error];
    NSDate *said = nil;
    for (NSArray *row in nextDue.rows) {
        if ([row[0] isEqual:first.id]) said = row[2];
    }
    LBCheck(@"ReminderNextDue says the same day", [said isEqual:next.dueDate], error ?: LBText(said));

    /* Closed by the event chosen: a one-off set before it, which saving the
       reminder alone closes nothing of. */
    Reminder *brakes = LBInsert([Reminder class], world.context);
    brakes.id = LBID(50);
    brakes.vehicle = world.golf;
    brakes.enteredBy = world.anna;
    brakes.task = @"Brakes";
    brakes.dueDate = LBMoment(@"2027-06-01");
    brakes.setAt = LBMoment(@"2027-05-01 09:00");
    LBSave(world.context, @"a one-off for the brakes");
    LBCheck(@"saved open", brakes.lb_isOpen, nil);
    LBCheck(@"closed by the service chosen", [brakes lb_completeByEvent:service next:&next error:&error] && brakes.event == service && !next,
            error);
    LBCheck(@"saved", LBSave(world.context, @"closed by it"), nil);
    LBCheck(@"closed again is refused", ![brakes lb_completeByEvent:service next:NULL error:&error], nil);
}

/* A schedule that recurs after a distance, closed by an event at none:
   closed, and no next made; one by months alone makes its next. */
static void LBNoMileage(void) {
    LBWorld *world = LBNewWorld();
    Schedule *permit = LBInsert([Schedule class], world.context);
    permit.id = LBID(10);
    permit.vehicle = world.golf;
    permit.enteredBy = world.anna;
    permit.expenseKind = world.parking;
    permit.intervalQuantity = LBNumber(@"10000");
    permit.intervalDistanceUnit = world.km;
    permit.duration = 12;
    LBSave(world.context, @"a schedule by distance and months");
    Reminder *first = [permit lb_startFrom:LBMoment(@"2026-01-01 09:00") mileage:LBNumber(@"140000") unit:world.km by:world.anna
                                        at:LBMoment(@"2026-10-20 18:00") error:NULL];
    LBSave(world.context, @"started");
    Expense *paid = LBExpense(world, 30, @"2026-12-01 09:00");
    LBSave(world.context, @"an expense at no distance");
    LBCheck(@"closed by it, and no next made", first.event == paid && !first.lb_nextReminder && !permit.lb_openReminder, LBDue(first));
    permit.intervalQuantity = nil;
    permit.intervalDistanceUnit = nil;
    paid.timestamp = LBMoment(@"2026-12-02 09:00");
    LBSave(world.context, @"by months alone, the expense moved a day");
    Reminder *next = first.lb_nextReminder;
    LBCheck(@"by months alone: its next, due on a day only", next && [next.dueDate isEqualToDate:LBMoment(@"2027-12-02")]
                && !next.dueMileageQuantity, LBDue(next));
}

static void LBAutomatic(void) {
    LBWorld *world = LBNewWorld();
    Vehicle *other = LBVehicle(world, 2, @"Polo");
    Schedule *oil = LBOilSchedule(world, 10);
    LBSave(world.context, @"a schedule");
    Reminder *first = [oil lb_startFrom:LBMoment(@"2026-06-01 10:00") mileage:LBNumber(@"148000") unit:world.km by:world.anna
                                     at:LBMoment(@"2026-10-20 18:00") error:NULL];
    LBSave(world.context, @"started");
    LBService(world, other, 30, @"2026-11-01 10:00", @"60000", @[ @"Oil change" ]);
    LBSave(world.context, @"another vehicle's oil change");
    LBCheck(@"another vehicle's closes nothing", first.lb_isOpen, nil);
    LBService(world, nil, 31, @"2026-10-19 10:00", @"152000", @[ @"Oil change" ]);
    LBSave(world.context, @"one the day before it was set");
    LBCheck(@"nor one from before the day it was set", first.lb_isOpen, nil);
    Service *sameDay = LBService(world, nil, 32, @"2026-10-20 08:00", @"152100", @[ @"Oil change" ]);
    LBSave(world.context, @"one the day it was set");
    LBCheck(@"one the day it was set closes it", first.event == sameDay, nil);

    /* A one-off of a kind of expense. */
    Reminder *permit = LBInsert([Reminder class], world.context);
    permit.id = LBID(40);
    permit.vehicle = world.golf;
    permit.enteredBy = world.anna;
    permit.expenseKind = world.parking;
    permit.dueDate = LBMoment(@"2026-12-31");
    permit.setAt = LBMoment(@"2026-10-20 18:00");
    LBSave(world.context, @"a one-off");
    Expense *paid = LBExpense(world, 41, @"2026-12-01 09:00");
    LBSave(world.context, @"an expense of its kind");
    LBCheck(@"an expense of the kind closes it, at no distance", permit.event == paid && !permit.doneMileageQuantity
                && !permit.lb_nextReminder, nil);

    /* Changed so that it no longer does the work: reopened, its next gone. */
    Reminder *next = first.lb_nextReminder;
    NSUUID *nextID = next.id;
    for (ServiceItem *item in [sameDay.serviceItems copy]) [world.context deleteObject:item];
    ServiceItem *wash = LBInsert([ServiceItem class], world.context);
    wash.id = LBID(3299);
    wash.task = @"Wash";
    wash.costAmount = LBNumber(@"10");
    wash.costCurrency = @"EUR";
    wash.service = sameDay;
    LBSave(world.context, @"the oil change taken off the service");
    LBCheck(@"the item taken off: reopened, the next deleted", first.lb_isOpen && !first.event && !LBReminder(nextID, world), nil);

    /* Moved: the reminder's moment follows it. */
    Service *later = LBService(world, nil, 34, @"2026-11-10 10:00", @"153000", @[ @"Oil change" ]);
    LBSave(world.context, @"another oil change");
    LBCheck(@"closed by it", first.event == later, nil);
    later.timestamp = LBMoment(@"2026-11-12 10:00");
    later.mileageQuantity = LBNumber(@"153500");
    LBSave(world.context, @"moved two days");
    next = first.lb_nextReminder;
    LBCheck(@"its moment and distance follow, and the untouched next", [first.doneAt isEqualToDate:later.timestamp]
                && LBIs(first.doneMileageQuantity, @"153500") && [next.dueDate isEqualToDate:LBMoment(@"2027-11-12")]
                && LBIs(next.dueMileageQuantity, @"168500") && [next.setAt isEqualToDate:later.timestamp],
            LBDue(next));
}

/* The earliest event wins: two oil changes added in either order leave the
   same reminders. */
static NSArray *LBTwoOilChanges(BOOL laterFirst) {
    LBWorld *world = LBNewWorld();
    Schedule *oil = LBOilSchedule(world, 10);
    LBSave(world.context, @"a schedule");
    [oil lb_startFrom:LBMoment(@"2026-06-01 10:00") mileage:LBNumber(@"148000") unit:world.km by:world.anna at:LBMoment(@"2026-10-20 18:00")
                error:NULL];
    LBSave(world.context, @"started");
    NSArray *order = laterFirst ? @[ @1, @0 ] : @[ @0, @1 ];
    for (NSNumber *which in order) {
        if (which.intValue == 0) LBService(world, nil, 30, @"2026-11-01 10:00", @"152000", @[ @"Oil change" ]);
        else LBService(world, nil, 31, @"2027-03-01 10:00", @"158000", @[ @"Oil change" ]);
        LBSave(world.context, @"an oil change");
    }
    NSMutableArray *said = [NSMutableArray array];
    NSArray *reminders = [oil.reminders.allObjects sortedArrayUsingDescriptors:@[ [NSSortDescriptor
                                                                                     sortDescriptorWithKey:NSStringFromSelector(@selector(setAt))
                                                                                                 ascending:YES] ]];
    for (Reminder *reminder in reminders) {
        [said addObject:[NSString stringWithFormat:@"%@ set %@ due %@ done %@ by %@", LBIDText(reminder.id), LBText(reminder.setAt),
                                                   LBDue(reminder), LBText(reminder.doneAt), LBIDText(reminder.event.id) ?: @"-"]];
    }
    return said;
}

static void LBEarliestWins(void) {
    NSArray *inOrder = LBTwoOilChanges(NO), *laterFirst = LBTwoOilChanges(YES);
    LBCheck(@"two oil changes: the first closes the reminder, the second its next", inOrder.count == 3
                && [inOrder[0] hasSuffix:LBIDText(LBID(30))] && [inOrder[1] hasSuffix:LBIDText(LBID(31))] && [inOrder[2] hasSuffix:@"-"],
            inOrder);
    LBCheck(@"the later added first: the earlier takes it, the same in the end", [laterFirst isEqualToArray:inOrder],
            [NSString stringWithFormat:@"%@ / %@", laterFirst, inOrder]);
}

static void LBMoveCancelDiscard(void) {
    LBWorld *world = LBNewWorld();
    Schedule *oil = LBOilSchedule(world, 10);
    LBSave(world.context, @"a schedule");
    Reminder *first = [oil lb_startFrom:LBMoment(@"2026-06-01 10:00") mileage:LBNumber(@"148000") unit:world.km by:world.anna
                                     at:LBMoment(@"2026-10-20 18:00") error:NULL];
    LBSave(world.context, @"started");
    NSError *error = nil;
    Rescheduling *moved = [first lb_rescheduleToDate:LBMoment(@"2027-07-01") mileage:nil unit:nil note:@"away in June" by:world.anna
                                                  at:LBMoment(@"2026-10-21 08:00") error:&error];
    LBCheck(@"moved: what it was due on recorded with the move", [moved.fromDate isEqualToDate:LBMoment(@"2027-06-01")]
                && !moved.fromMileageQuantity && [first.dueDate isEqualToDate:LBMoment(@"2027-07-01")] && moved.madeBy == world.anna
                && [moved.note isEqualToString:@"away in June"] && LBIs(first.dueMileageQuantity, @"163000"),
            error ?: LBDue(first));
    LBCheck(@"saved", LBSave(world.context, @"moved"), nil);
    LBCheck(@"to where it is due is refused", ![first lb_rescheduleToDate:LBMoment(@"2027-07-01") mileage:nil unit:nil note:nil by:world.anna
                                                                          at:[NSDate date] error:&error], nil);
    Rescheduling *again = [first lb_rescheduleToDate:nil mileage:LBNumber(@"165000") unit:nil note:nil by:world.anna
                                                  at:LBMoment(@"2026-10-22 08:00") error:&error];
    LBCheck(@"moved again, by distance", LBIs(again.fromMileageQuantity, @"163000") && !again.fromDate
                && LBIs(first.dueMileageQuantity, @"165000") && first.reschedulings.count == 2, error);
    LBSave(world.context, @"moved again");

    Reminder *replacement = nil;
    LBCheck(@"cancelled, replaced", [first lb_cancelOn:LBMoment(@"2026-10-25") replacementDueDate:LBMoment(@"2027-09-01") mileage:nil unit:nil
                                                    by:world.anna at:LBMoment(@"2026-10-25 09:00") replacement:&replacement error:&error]
                && [first.cancelDate isEqualToDate:LBMoment(@"2026-10-25")] && replacement.replaced == first && replacement.schedule == oil
                && replacement.lb_isOpen && oil.lb_openReminder == replacement,
            error);
    LBCheck(@"saved", LBSave(world.context, @"cancelled"), nil);
    LBCheck(@"a cancelled one is not done", ![first lb_completeByEvent:nil next:NULL error:&error], nil);

    /* Discarded: what it closed reopened, the untouched next with it. */
    Service *service = LBService(world, nil, 30, @"2027-08-20 11:00", @"164000", @[ @"Oil change" ]);
    LBSave(world.context, @"the oil change");
    Reminder *next = replacement.lb_nextReminder;
    NSUUID *nextID = next.id;
    LBCheck(@"the replacement closed by it", replacement.event == service && next, nil);
    LBCheck(@"discarded", [service lb_discardKeepingNextReminders:nil error:&error], error);
    LBSave(world.context, @"discarded");
    LBCheck(@"the replacement reopened, its next deleted", replacement.lb_isOpen && !LBReminder(nextID, world), LBDue(replacement));

    /* A touched next: refused, until the owner says. */
    service = LBService(world, nil, 31, @"2027-08-21 11:00", @"164100", @[ @"Oil change" ]);
    LBSave(world.context, @"the oil change again");
    next = replacement.lb_nextReminder;
    next.note = @"Use 5W-30";
    LBSave(world.context, @"the next noted");
    LBCheck(@"discarding it is refused, nothing changed", ![service lb_discardKeepingNextReminders:nil error:&error]
                && error.code == LBProceduresErrorNextReminderTouched && [error.userInfo[LBNextRemindersErrorKey] containsObject:next]
                && !service.isDeleted && !replacement.lb_isOpen && !world.context.hasChanges,
            error);
    LBCheck(@"keeping the next is refused: a reminder is done only by an event", ![service lb_discardKeepingNextReminders:@YES error:&error]
                && error.code == LBProceduresErrorRefused && !world.context.hasChanges, error);
    LBCheck(@"deleting the next all the same: reopened", [service lb_discardKeepingNextReminders:@NO error:&error] && replacement.lb_isOpen
                && next.isDeleted, error);
    LBCheck(@"saved", LBSave(world.context, @"discarded, the next deleted"), nil);
}

/* What a schedule's reminders are, said a line each. */
static NSArray *LBStateOf(Schedule *schedule) {
    NSMutableArray *said = [NSMutableArray array];
    NSArray *reminders = [schedule.reminders.allObjects
        sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(setAt)) ascending:YES] ]];
    for (Reminder *reminder in reminders) {
        if (reminder.isDeleted) continue;
        [said addObject:[NSString stringWithFormat:@"%@ set %@ due %@ done %@ by %@", LBIDText(reminder.id), LBText(reminder.setAt),
                                                   LBDue(reminder), LBText(reminder.doneAt), LBIDText(reminder.event.id) ?: @"-"]];
    }
    return said;
}

/* The oil schedule started, then oil changes entered one by one in the
   order given: (id, moment, km) each. */
static LBWorld *LBEntered(NSArray<NSArray *> *changes, Schedule **schedule) {
    LBWorld *world = LBNewWorld();
    Schedule *oil = LBOilSchedule(world, 10);
    LBSave(world.context, @"a schedule");
    [oil lb_startFrom:LBMoment(@"2026-06-01 10:00") mileage:LBNumber(@"148000") unit:world.km by:world.anna at:LBMoment(@"2026-10-20 18:00")
                error:NULL];
    LBSave(world.context, @"started");
    for (NSArray *change in changes) {
        LBService(world, nil, [change[0] unsignedIntValue], change[1], change[2], @[ @"Oil change" ]);
        LBSave(world.context, @"an oil change");
    }
    *schedule = oil;
    return world;
}

static Service *LBServiceOf(LBWorld *world, unsigned n) {
    return LBFetchID([Service class], LBID(n), world.context);
}

/* Any order of entering, and moves after: the same as entering the events
   as they end up, afresh. */
static void LBOrders(void) {
    NSArray *changes = @[ @[ @30, @"2026-11-01 10:00", @"152000" ], @[ @31, @"2027-03-01 10:00", @"158000" ],
                          @[ @32, @"2027-09-01 10:00", @"166000" ] ];
    NSArray *orders = @[ @[ @0, @1, @2 ], @[ @0, @2, @1 ], @[ @1, @0, @2 ], @[ @1, @2, @0 ], @[ @2, @0, @1 ], @[ @2, @1, @0 ] ];
    Schedule *oil;
    NSArray *expected = LBStateOf((LBEntered(changes, &oil), oil));
    BOOL same = expected.count == 4;
    NSMutableArray *differs = [NSMutableArray array];
    for (NSArray *order in orders) {
        NSMutableArray *entered = [NSMutableArray array];
        for (NSNumber *i in order) [entered addObject:changes[i.unsignedIntegerValue]];
        LBWorld *world = LBEntered(entered, &oil);
        NSArray *state = LBStateOf(oil);
        if (![state isEqualToArray:expected]) {
            same = NO;
            [differs addObject:@[ order, state ]];
        }
        (void)world;
    }
    LBCheck(@"three oil changes entered in each of the six orders: the same reminders", same, differs.count ? differs : expected);

    /* Moved: the last one before the others; the same as entered so. */
    LBWorld *world = LBEntered(changes, &oil);
    Service *last = LBServiceOf(world, 32);
    last.timestamp = LBMoment(@"2026-10-25 10:00");
    last.mileageQuantity = LBNumber(@"151000");
    LBSave(world.context, @"the last moved first");
    NSArray *moved = LBStateOf(oil);
    Schedule *fresh;
    LBEntered(@[ @[ @31, @"2027-03-01 10:00", @"158000" ], @[ @32, @"2026-10-25 10:00", @"151000" ], @[ @30, @"2026-11-01 10:00", @"152000" ] ],
              &fresh);
    LBCheck(@"one moved before the others: as entered so afresh", [moved isEqualToArray:LBStateOf(fresh)],
            [NSString stringWithFormat:@"%@ / %@", moved, LBStateOf(fresh)]);

    /* Moved to another vehicle: as if never of this one. */
    Vehicle *polo = LBVehicle(world, 2, @"Polo");
    LBServiceOf(world, 30).vehicle = polo;
    LBSave(world.context, @"one moved to another vehicle");
    NSArray *away = LBStateOf(oil);
    LBEntered(@[ @[ @31, @"2027-03-01 10:00", @"158000" ], @[ @32, @"2026-10-25 10:00", @"151000" ] ], &fresh);
    LBCheck(@"one moved to another vehicle: as if never entered here", [away isEqualToArray:LBStateOf(fresh)],
            [NSString stringWithFormat:@"%@ / %@", away, LBStateOf(fresh)]);

    /* A touched next that a move would change: refused, nothing saved. */
    Reminder *open = oil.lb_openReminder;
    open.note = @"Use 5W-30";
    LBSave(world.context, @"the open one noted");
    Service *first = LBServiceOf(world, 32);
    first.timestamp = LBMoment(@"2027-04-01 10:00");
    NSError *error = nil;
    LBCheck(@"a move that would change a noted next is refused", ![world.context lb_completeRemindersOfChangedEvents:&error]
                && error.code == LBProceduresErrorNextReminderTouched, error);
    [world.context rollback];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: lb-procedures-check Logbook.momd Logbook.ormplans\n");
            return 2;
        }
        LBModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@(argv[1])]];
        NSError *error = nil;
        NSData *plans = [NSData dataWithContentsOfFile:@(argv[2])];
        id list = plans ? [NSPropertyListSerialization propertyListWithData:plans options:0 format:NULL error:&error] : nil;
        ORMTables *tables = list ? [ORMTables tablesWithPropertyList:list error:&error] : nil;
        if (!LBModel.entities.count || !tables) {
            fprintf(stderr, "no model at %s, or no tables at %s: %s\n", argv[1], argv[2], error.localizedDescription.UTF8String ?: "");
            return 2;
        }
        [ORMTables registerTables:tables named:@"Logbook"];
        LBNames();
        LBDeterminism();
        LBStart();
        LBComplete();
        LBAutomatic();
        LBEarliestWins();
        LBNoMileage();
        LBOrders();
        LBMoveCancelDiscard();
        printf("procedures: %lu failed\n", (unsigned long)LBFailures);
    }
    return LBFailures ? 1 : 0;
}
