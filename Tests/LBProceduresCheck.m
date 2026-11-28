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
#import "LBPlanned.h"
#import "Vehicle+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "Expense+CoreDataClass.h"
#import "MeterReading+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "VolumeUnit+CoreDataClass.h"
#import "StockUnit+CoreDataClass.h"
#import "StockItem+CoreDataClass.h"
#import "Catalog+CoreDataClass.h"
#import "Category+CoreDataClass.h"
#import "Trip+CoreDataClass.h"
#import "ComponentChange+CoreDataClass.h"
#import "LBStockProcedures.h"
#import "LBAssets.h"
#import "LBVehicleSummary.h"
#import "Asset+CoreDataClass.h"
#import "PlanTask+CoreDataClass.h"
#import "Checklist+CoreDataClass.h"
#import "Rescheduling+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"

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
    Vehicle *vehicle = LBMakeAsset([Vehicle class], world.anna, @"Volkswagen", @"Golf VII", nil, [NSDate dateWithTimeIntervalSince1970:946684800], nil, nil, nil, NULL);
    vehicle.id = LBID(n);
    vehicle.vehicleName = name;
    vehicle.manufactureYear = 2016;
    vehicle.fuel = @"Petrol";
    return vehicle;
}

static LBWorld *LBNewWorld(void) {
    LBWorld *world = [[LBWorld alloc] init];
    world.context = LBNewStore();
    world.anna = LBInsert([User class], world.context);
    world.anna.email = @"anna@example.org";
    world.km = LBUnit(@"km", world.context);
    world.mi = LBUnit(@"mi", world.context);
    /* The model's, seeded as every store's are. */
    world.maintenance = LBFetchKey([CostKind class], NSStringFromSelector(@selector(name)), @"Maintenance", world.context);
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
    LBCheck(@"counted from today and the latest distance", [first.countedFromDate isEqualToDate:LBMoment(@"2026-10-20")]
                && LBIs(first.countedFromMileageQuantity, @"150000") && first.countedFromMileageDistanceUnit == world.km,
            LBText(first.countedFromDate));
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
    LBCheck(@"from the last oil change: 2027-06-01, 163000 km, counted from it",
            [counted.dueDate isEqualToDate:LBMoment(@"2027-06-01")] && LBIs(counted.dueMileageQuantity, @"163000")
                && [counted.countedFromDate isEqualToDate:LBMoment(@"2026-06-01")] && LBIs(counted.countedFromMileageQuantity, @"148000"),
            error ?: LBDue(counted));
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
    LBCheck(@"counted from the service: its day and distance", [next.countedFromDate isEqualToDate:LBMoment(@"2027-05-20")]
                && LBIs(next.countedFromMileageQuantity, @"162400") && next.countedFromMileageDistanceUnit == world.km,
            LBText(next.countedFromDate));
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

/* A schedule changed (PROCESSES.md 11): a new one going on from it, its
   open reminder due anew, or, touched, cancelled and the new one started;
   the old one's past as it was, and nothing more of its own. */
static void LBContinue(void) {
    LBWorld *world = LBNewWorld();
    Schedule *oil = LBOilSchedule(world, 10);
    LBSave(world.context, @"a schedule");
    Reminder *first = [oil lb_startFrom:LBMoment(@"2026-06-01 10:00") mileage:LBNumber(@"148000") unit:world.km by:world.anna
                                     at:LBMoment(@"2026-06-02 10:00") error:NULL];
    LBService(world, nil, 30, @"2027-05-20 11:00", @"162400", @[ @"Oil change" ]);
    LBSave(world.context, @"an oil change");
    Reminder *open = first.lb_nextReminder;
    NSUUID *openID = open.id;
    NSError *error = nil;
    Reminder *cancelled = nil;
    NSDate *now = LBMoment(@"2027-06-01 09:00");
    Schedule *often = [oil lb_continueWithTask:@"Oil change" expenseKind:nil checklist:nil interval:LBNumber(@"10000") unit:world.km
                                        months:6 note:@"older engine" by:world.anna at:now cancelled:&cancelled error:&error];
    LBCheck(@"changed: a new schedule going on from it, of the vehicle, its intervals and note",
            often && often.continued == oil && oil.continuation == often && often.vehicle == world.golf && often.duration == 6
                && LBIs(often.intervalQuantity, @"10000") && [often.note isEqualToString:@"older engine"]
                && [often.id isEqual:LBNamedUUID([@"continuation of " stringByAppendingString:oil.id.UUIDString.lowercaseString])],
            error);
    LBCheck(@"its open reminder goes with it, the same, due anew from where it is counted from: 6 months, 10000 km on",
            open.schedule == often && [open.id isEqual:openID] && !cancelled && [open.dueDate isEqualToDate:LBMoment(@"2027-11-20")]
                && LBIs(open.dueMileageQuantity, @"172400") && [open.countedFromDate isEqualToDate:LBMoment(@"2027-05-20")],
            LBDue(open));
    LBCheck(@"the old one keeps its past, and has none open", first.schedule == oil && first.event && !oil.lb_openReminder, nil);
    LBCheck(@"saved, the model's rules kept", LBSave(world.context, @"the change"), nil);
    LBCheck(@"changed again from the old one: refused", ![oil lb_continueWithTask:@"Oil change" expenseKind:nil checklist:nil
                                                                         interval:nil unit:nil months:3 note:nil by:world.anna
                                                                               at:now cancelled:NULL error:&error],
            nil);

    /* An oil change after: closes it in the new one, whose next is due by
       the new rule; the old one makes nothing. */
    LBService(world, nil, 31, @"2027-11-01 09:00", @"170500", @[ @"Oil change" ]);
    LBCheck(@"an oil change after the change, saved", LBSave(world.context, @"another oil change"), nil);
    Reminder *after = open.lb_nextReminder;
    NSUInteger oldOnes = 0;
    for (Reminder *reminder in oil.reminders) {
        if (!reminder.isDeleted) oldOnes++;
    }
    LBCheck(@"it closes the new one's, whose next is 6 months and 10000 km on",
            open.event && after.schedule == often && [after.dueDate isEqualToDate:LBMoment(@"2028-05-01")]
                && LBIs(after.dueMileageQuantity, @"180500") && oldOnes == 1,
            [NSString stringWithFormat:@"open %@ done %@ by %@, after %@ (%@), %lu old", LBDue(open), LBText(open.doneAt),
                                       open.event.id, after.id, after == open ? @"itself" : LBDue(after), (unsigned long)oldOnes]);

    /* Moved by hand, then changed: cancelled, and the new one started from
       where it was counted from. */
    LBCheck(@"moved by hand", [after lb_rescheduleToDate:LBMoment(@"2028-06-01") mileage:nil unit:nil note:@"away" by:world.anna
                                                       at:now error:&error] != nil,
            error);
    LBSave(world.context, @"the move");
    Schedule *filter = [often lb_continueWithTask:@"Oil and filter" expenseKind:nil checklist:nil interval:LBNumber(@"10000")
                                             unit:world.km months:6 note:nil by:world.anna at:now cancelled:&cancelled error:&error];
    Reminder *started = filter.lb_openReminder;
    LBCheck(@"changed, the moved one cancelled today, and the new one started from where it was counted from",
            filter && cancelled == after && [after.cancelDate isEqualToDate:LBMoment(@"2027-06-01")] && after.schedule == often
                && started && started != after && [started.dueDate isEqualToDate:LBMoment(@"2028-05-01")]
                && LBIs(started.dueMileageQuantity, @"180500") && [started.countedFromDate isEqualToDate:LBMoment(@"2027-11-01")],
            error ?: LBDue(started));
    LBCheck(@"saved", LBSave(world.context, @"the second change"), nil);
}

/* What a schedule plans (PROCESSES.md 12): by months exactly; by distance
   on the day the vehicle is expected there, 100 km a day over its last 90
   days; whichever first; a year ahead; worked out anew as it changes. */
static void LBPlanning(void) {
    LBWorld *world = LBNewWorld();
    LBReading(world, 20, @"2026-07-05 09:00", @"140200");
    LBReading(world, 21, @"2026-10-01 09:00", @"149000");
    Schedule *oil = LBOilSchedule(world, 10);
    Schedule *wash = LBOilSchedule(world, 11);
    wash.task = @"Wash";
    wash.intervalQuantity = nil;
    wash.intervalDistanceUnit = nil;
    wash.duration = 6;
    LBSave(world.context, @"two schedules, readings");
    NSDate *now = LBMoment(@"2026-10-01 12:00");
    NSDate *year = LBMoment(@"2027-10-01");
    Reminder *open = [oil lb_startFrom:nil mileage:nil unit:nil by:world.anna at:now error:NULL];
    [wash lb_startFrom:nil mileage:nil unit:nil by:world.anna at:now error:NULL];
    LBSave(world.context, @"both started");
    NSNumber *rate = [world.golf lbKilometresADayAsOf:now];
    LBCheck(@"the vehicle goes 100 km a day over its last 90 days", rate && fabs(rate.doubleValue - 100) < 0.001, rate);
    BOOL estimated = NO;
    NSDate *day = [open lbDayAsOf:now estimated:&estimated];
    LBCheck(@"the open reminder falls on the day 164000 km is expected, before its date",
            [day isEqualToDate:LBMoment(@"2027-02-28")] && estimated, LBText(day));
    NSArray<LBPlannedReminder *> *planned = [oil lbPlannedUntil:year asOf:now];
    LBPlannedReminder *next = planned.firstObject;
    LBCheck(@"planned after it, a year ahead: one, at 179000 km, on the day expected", planned.count == 1
                && LBIs(next.dueMileage, @"179000") && next.dueUnit == world.km && [next.dueDate isEqualToDate:LBMoment(@"2028-02-28")]
                && [next.day isEqualToDate:LBMoment(@"2027-07-28")] && next.estimated,
            next ? LBText(next.day) : @"none");
    NSArray<LBPlannedReminder *> *washes = [wash lbPlannedUntil:year asOf:now];
    LBCheck(@"by months: six months on from the open one's date, exactly", washes.count == 1
                && [washes.firstObject.day isEqualToDate:LBMoment(@"2027-10-01")] && !washes.firstObject.estimated,
            washes.firstObject ? LBText(washes.firstObject.day) : @"none");

    /* Changed: every 10000 km; what it plans, at once otherwise. */
    Schedule *often = [oil lb_continueWithTask:@"Oil change" expenseKind:nil checklist:nil interval:LBNumber(@"10000") unit:world.km
                                        months:12 note:nil by:world.anna at:now cancelled:NULL error:NULL];
    LBSave(world.context, @"the change");
    planned = [often lbPlannedUntil:year asOf:now];
    LBCheck(@"changed, it plans otherwise: 169000 and 179000 km, on their days",
            planned.count == 2 && LBIs(planned[0].dueMileage, @"169000") && [planned[0].day isEqualToDate:LBMoment(@"2027-04-19")]
                && LBIs(planned[1].dueMileage, @"179000") && [planned[1].day isEqualToDate:LBMoment(@"2027-07-28")],
            [planned valueForKey:@"dueMileage"]);
    LBCheck(@"the old one plans nothing", [oil lbPlannedUntil:year asOf:now].count == 0, nil);

    /* No readings to tell by: by its distance, on no day, three. */
    Vehicle *polo = LBVehicle(world, 2, @"Polo");
    Schedule *tyres = LBOilSchedule(world, 12);
    tyres.vehicle = polo;
    tyres.task = @"Tyre rotation";
    [tyres setValue:nil forKey:@"duration"];
    tyres.intervalQuantity = LBNumber(@"10000");
    LBSave(world.context, @"a vehicle with no readings, a schedule by distance");
    [tyres lb_startFrom:now mileage:LBNumber(@"50000") unit:world.km by:world.anna at:now error:NULL];
    NSArray<LBPlannedReminder *> *undated = [tyres lbPlannedUntil:year asOf:now];
    LBCheck(@"with no readings to tell by: three, by distance, on no day",
            undated.count == 3 && LBIs(undated[0].dueMileage, @"70000") && !undated[0].day && LBIs(undated[2].dueMileage, @"90000"),
            [undated valueForKey:@"dueMileage"]);
}

/* Days where they are (PROCESSES.md: Days and time zones): an oil change
   at 02:30 on 1 June in Almaty, 21:30 on 31 May in UTC, is of 1 June, and
   so is what it makes due; the same moment logged in Berlin is of 31 May. */
static void LBTimeZones(void) {
    LBWorld *world = LBNewWorld();
    world.anna.timeZone = @"Asia/Almaty";
    Schedule *oil = LBOilSchedule(world, 10);
    LBSave(world.context, @"a schedule, its owner in Almaty");
    Reminder *first = [oil lb_startFrom:LBMoment(@"2026-01-10 10:00") mileage:LBNumber(@"140000") unit:world.km by:world.anna
                                     at:LBMoment(@"2026-01-11 10:00") error:NULL];
    Service *service = LBService(world, nil, 30, @"2026-05-31 21:30", @"150000", @[ @"Oil change" ]);
    LBSave(world.context, @"an oil change at 02:30 in Almaty");
    LBCheck(@"an event of no zone of its own: its day where its owner lives", [LBEventDay(service) isEqualToDate:LBMoment(@"2026-06-01")],
            LBText(LBEventDay(service)));
    Reminder *next = first.lb_nextReminder;
    LBCheck(@"what it makes due counted from that day: 1 June, 12 months on",
            [next.countedFromDate isEqualToDate:LBMoment(@"2026-06-01")] && [next.dueDate isEqualToDate:LBMoment(@"2027-06-01")],
            LBDue(next));
    service.timeZone = @"Europe/Berlin";
    LBCheck(@"the same moment logged in Berlin: 31 May", [LBEventDay(service) isEqualToDate:LBMoment(@"2026-05-31")],
            LBText(LBEventDay(service)));
    LBCheck(@"the owner's today: where they live", [LBOwnerDay(world.golf, LBMoment(@"2026-05-31 21:30")) isEqualToDate:LBMoment(@"2026-06-01")],
            nil);
    LBCheck(@"a day given is its own, whatever the zone", [LBDayIn(LBMoment(@"2026-06-01"), @"America/Los_Angeles") isEqualToDate:LBMoment(@"2026-05-31")]
                && [LBDay(LBMoment(@"2026-06-01")) isEqualToDate:LBMoment(@"2026-06-01")],
            nil);
}

/* What a vehicle is: a bicycle uses no fuel and is never filled up; a car,
   or one stored before vehicles had kinds, uses one and was built in a
   year. A component fitted does the work of the task named as its kind,
   and wears from the reading it was fitted at. */
static BOOL LBRefused(NSManagedObjectContext *context) {
    NSError *error = nil;
    BOOL saved = [context lb_completeRemindersOfChangedEvents:&error] && [context orm_prepareForSave:&error] && [context save:&error];
    if (!saved) [context rollback];
    return !saved;
}

static void LBKindsAndComponents(void) {
    LBWorld *world = LBNewWorld();
    Vehicle *bike = LBMakeAsset([Vehicle class], world.anna, @"Surly", @"Long Haul Trucker", nil, [NSDate dateWithTimeIntervalSince1970:946684800], nil, nil, nil, NULL);
    bike.id = LBID(2);
    bike.vehicleName = @"Commuter";
    bike.vehicleKind = @"Bicycle";
    LBCheck(@"a bicycle: no fuel, no year", LBSave(world.context, @"a bicycle"), nil);
    bike.fuel = @"Petrol";
    LBCheck(@"a bicycle that uses a fuel: refused", LBRefused(world.context), nil);
    Vehicle *car = LBVehicle(world, 3, @"Polo");
    car.vehicleKind = @"Car";
    car.fuel = nil;
    LBCheck(@"a car that uses no fuel: refused", LBRefused(world.context), nil);
    world.golf.fuel = nil;
    LBCheck(@"one of no kind (stored before kinds) that uses no fuel: refused", LBRefused(world.context), nil);
    FillUp *fill = LBInsert([FillUp class], world.context);
    LBEvent(world, fill, bike, 5, @"2026-06-01 10:00");
    fill.mileageQuantity = LBNumber(@"1000");
    fill.mileageDistanceUnit = world.km;
    fill.volumeQuantity = LBNumber(@"1");
    fill.volumeVolumeUnit = LBFetchKey([VolumeUnit class], NSStringFromSelector(@selector(code)), @"L", world.context);
    fill.fuel = @"Petrol";
    fill.totalAmount = LBNumber(@"2");
    fill.totalCurrency = @"EUR";
    LBCheck(@"a bicycle filled up: refused", LBRefused(world.context), nil);

    /* A bicycle with no meter: its readings worked out from its trips,
       10 km and then 20 km on a trainer, its service between. */
    [world.context rollback];
    bike.hasNoMeter = YES;
    bike.meterUnit = nil;
    Trip *first = LBInsert([Trip class], world.context);
    LBEvent(world, first, bike, 6, @"2026-06-01 10:00");
    first.moment = LBMoment(@"2026-06-01 11:00");
    first.lengthQuantity = LBNumber(@"10");
    first.lengthDistanceUnit = world.km;
    Service *lubed = LBService(world, bike, 7, @"2026-06-02 10:00", @"999", @[ @"Lub Chain" ]);
    Trip *zwift = LBInsert([Trip class], world.context);
    LBEvent(world, zwift, bike, 8, @"2026-06-03 10:00");
    zwift.moment = LBMoment(@"2026-06-03 11:00");
    zwift.lengthQuantity = LBNumber(@"20");
    zwift.lengthDistanceUnit = world.km;
    zwift.isVirtual = YES;
    BOOL saved = LBSave(world.context, @"a bicycle's trips");
    LBCheck(@"no meter: its readings its trips' lengths added up: 0-10, the service at 10 (not the 999 said), 10-30",
            saved && LBIs(first.mileageQuantity, @"0") && LBIs(first.distanceQuantity, @"10") && LBIs(lubed.mileageQuantity, @"10")
                && LBIs(zwift.mileageQuantity, @"10") && LBIs(zwift.distanceQuantity, @"30"),
            [NSString stringWithFormat:@"%@-%@, %@, %@-%@", first.mileageQuantity, first.distanceQuantity, lubed.mileageQuantity,
                                       zwift.mileageQuantity, zwift.distanceQuantity]);

    /* The chain every 3000 km; a chain, a wheel and a tyre, units of a
       catalog's items. */
    Schedule *chain = LBInsert([Schedule class], world.context);
    chain.id = LBID(10);
    chain.vehicle = bike;
    chain.enteredBy = world.anna;
    chain.task = @"Chain";
    chain.intervalQuantity = LBNumber(@"3000");
    chain.intervalDistanceUnit = world.km;
    LBSave(world.context, @"the chain's schedule");
    Reminder *due = [chain lb_startFrom:LBMoment(@"2026-05-01 10:00") mileage:LBNumber(@"0") unit:world.km by:world.anna
                                     at:LBMoment(@"2026-05-01 18:00") error:NULL];
    LBSave(world.context, @"started");
    Catalog *parts = LBInsert([Catalog class], world.context);
    parts.id = LBID(50);
    parts.catalogName = @"Bike parts";
    parts.catalogOwner = world.anna;
    StockUnit * (^unitOf)(unsigned, NSString *, NSString *) = ^StockUnit *(unsigned n, NSString *name, NSString *kind) {
        Category *category = LBInsert([Category class], world.context);
        category.id = LBID(n + 1);
        category.categoryName = kind;
        category.catalog = parts;
        StockItem *item = LBInsert([StockItem class], world.context);
        item.id = LBID(n + 2);
        item.itemName = name;
        item.catalog = parts;
        item.category = category;
        item.created = [NSDate date];
        item.sku = [NSString stringWithFormat:@"BP-%u", n];
        StockUnit *unit = LBInsert([StockUnit class], world.context);
        unit.id = LBID(n + 3);
        unit.stockItem = item;
        return unit;
    };
    StockUnit *kmc = unitOf(60, @"KMC X9", @"Chain"), *wheel = unitOf(70, @"Shimano WH-R500", @"Wheel Set");
    StockUnit *tyre = unitOf(80, @"GravelKing+", @"Tyre"), *pads = unitOf(90, @"Shimano B01S", @"Brake pads");
    LBSave(world.context, @"the parts");
    ComponentChange * (^fit)(unsigned, NSString *, StockUnit *) = ^ComponentChange *(unsigned n, NSString *moment, StockUnit *unit) {
        ComponentChange *change = LBInsert([ComponentChange class], world.context);
        LBEvent(world, change, bike, n, moment);
        change.mileageQuantity = LBNumber(@"0");
        change.mileageDistanceUnit = world.km;
        change.stockUnit = unit;
        return change;
    };
    fit(100, @"2026-05-20 10:00", pads);
    LBSave(world.context, @"brake pads fitted");
    LBCheck(@"brake pads fitted close nothing of the chain's", due.lb_isOpen, nil);
    ComponentChange *chainOn = fit(101, @"2026-05-21 10:00", kmc);
    fit(102, @"2026-05-21 10:05", wheel).mountPosition = @"Rear";
    ComponentChange *tyreOn = fit(103, @"2026-05-21 10:10", tyre);
    tyreOn.host = wheel;
    tyreOn.mountPosition = @"Rear";
    tyreOn.skipsVirtualTrips = YES;
    LBCheck(@"fitted: a chain, a wheel, a tyre into the wheel; their readings the bicycle's then (0)", LBSave(world.context, @"fitted")
                && LBIs(chainOn.mileageQuantity, @"0") && [kmc lb_fittedTo] == bike && [tyre lb_fittedTo] == bike, chainOn.mileageQuantity);
    Reminder *next = due.lb_nextReminder;
    LBCheck(@"a chain fitted (a unit of a Chain) closes the chain's, the next due 3000 km on", due.event == chainOn && LBIs(next.dueMileageQuantity, @"3000"),
            LBDue(next));
    LBCheck(@"the chain wore 30 km (both trips); the tyre, on no virtual trip, 10", [[kmc lb_wornIn:world.km] isEqualToNumber:@30]
                && [[tyre lb_wornIn:world.km] isEqualToNumber:@10],
            [NSString stringWithFormat:@"%@, %@", [kmc lb_wornIn:world.km], [tyre lb_wornIn:world.km]]);
    /* The wheel taken off, a new chain on: the tyre goes with its wheel. */
    StockUnit *newer = unitOf(110, @"KMC X10", @"Chain");
    ComponentChange *swap = fit(111, @"2026-06-04 10:00", newer);
    swap.removedStockUnit = kmc;
    ComponentChange *off = fit(112, @"2026-06-04 10:05", pads);
    off.removedStockUnit = wheel;
    Trip *later = LBInsert([Trip class], world.context);
    LBEvent(world, later, bike, 113, @"2026-06-05 10:00");
    later.moment = LBMoment(@"2026-06-05 11:00");
    later.lengthQuantity = LBNumber(@"5");
    later.lengthDistanceUnit = world.km;
    LBCheck(@"removed, the old chain wears no more (30), off the bike; the tyre with its wheel (10); the new chain 5",
            LBSave(world.context, @"swapped") && [[kmc lb_wornIn:world.km] isEqualToNumber:@30] && ![kmc lb_fittedTo]
                && [[tyre lb_wornIn:world.km] isEqualToNumber:@10] && ![tyre lb_fittedTo] && [[newer lb_wornIn:world.km] isEqualToNumber:@5],
            [NSString stringWithFormat:@"%@ %@ %@", [kmc lb_wornIn:world.km], [tyre lb_wornIn:world.km], [newer lb_wornIn:world.km]]);
    ComponentChange *both = fit(120, @"2026-06-06 10:00", newer);
    both.removedStockUnit = newer;
    LBCheck(@"a change fitting and removing one unit: refused", LBRefused(world.context), nil);
}

/* Fuel per meter, and units that are assets fitted in others (docs/CSDP.md,
   A fill-up; A unit that is an asset). */
/* Refused, and why. */
static NSString *LBRefusal(NSManagedObjectContext *context) {
    NSError *error = nil;
    BOOL saved = [context lb_completeRemindersOfChangedEvents:&error] && [context orm_prepareForSave:&error] && [context save:&error];
    if (!saved) [context rollback];
    return saved ? nil : LBSaid(error);
}

static FillUp *LBFull(LBWorld *world, Asset *asset, unsigned n, NSString *moment, NSString *reading, DistanceUnit *unit, NSString *litres) {
    FillUp *fill = LBInsert([FillUp class], world.context);
    LBEvent(world, fill, (Vehicle *)asset, n, moment);
    fill.mileageQuantity = LBNumber(reading);
    fill.mileageDistanceUnit = unit;
    fill.volumeQuantity = LBNumber(litres);
    fill.volumeVolumeUnit = LBFetchKey([VolumeUnit class], NSStringFromSelector(@selector(code)), @"L", world.context);
    fill.fuel = @"Petrol";
    fill.station = @"Shell";
    fill.totalAmount = LBNumber(@"10");
    fill.totalCurrency = @"EUR";
    fill.filledTheTank = YES;
    return fill;
}

static void LBFuelAndHierarchy(void) {
    LBWorld *world = LBNewWorld();
    DistanceUnit *hours = LBUnit(@"h", world.context);
    NSDate *day = [NSDate dateWithTimeIntervalSince1970:946684800];
    Asset *generator = LBMakeAsset([Asset class], world.anna, @"Honda", @"EU22i", nil, day, nil, nil, nil, NULL);
    generator.id = LBID(2);
    generator.vehicleName = @"Generator";
    generator.meterUnit = hours;
    generator.fuel = @"Petrol";
    LBFull(world, generator, 10, @"2026-06-01 10:00", @"200", hours, @"3");
    FillUp *second = LBFull(world, generator, 11, @"2026-06-08 10:00", @"210", hours, @"5");
    LBFull(world, world.golf, 12, @"2026-06-01 10:00", @"1000", world.km, @"40");
    FillUp *golfs = LBFull(world, world.golf, 13, @"2026-06-08 10:00", @"1600", world.km, @"36");
    LBCheck(@"a generator, no vehicle, filled up", LBSave(world.context, @"fill-ups"), nil);
    NSError *error = nil;
    ORMQueryResult *result = [LogbookQueries fullTankConsumptionInContext:world.context error:&error];
    NSMutableDictionary *of = [NSMutableDictionary dictionary];
    for (NSArray *row in result.rows) if (row.count > 3) of[row[0]] = row[3];
    LBCheck(@"consumption per its meter: the generator's 5 L over 10 h, 0.5 L/h; the Golf's 36 L over 600 km, 6 L/100 km",
            [of[second.id] isEqual:LBNumber(@"0.5")] && [of[golfs.id] isEqual:LBNumber(@"6")], of);
    NSString *perHour = [[[LBVehicleSummary alloc] initWithVehicle:(Vehicle *)generator] consumption];
    NSString *perKm = [[[LBVehicleSummary alloc] initWithVehicle:world.golf] consumption];
    LBCheck(@"and said so: 0.50 L/h, 6.00 L/100 km", [perHour isEqualToString:@"0.50 L/h"] && [perKm isEqualToString:@"6.00 L/100 km"],
            [NSString stringWithFormat:@"%@, %@", perHour, perKm]);
    Trip *trip = LBInsert([Trip class], world.context);
    LBEvent(world, trip, (Vehicle *)generator, 14, @"2026-06-09 10:00");
    trip.mileageQuantity = LBNumber(@"210");
    trip.mileageDistanceUnit = hours;
    NSString *why = LBRefusal(world.context);
    LBCheck(@"a trip of what is no vehicle: refused, as no vehicle's", [why containsString:@"that Asset is a Vehicle"], why);

    /* A power station, its battery an asset fitted in it; a tray the
       battery goes into later. */
    Asset *station = LBMakeAsset([Asset class], world.anna, @"EcoFlow", @"River 2 Pro", @"R2P-0042", day, nil, nil, nil, NULL);
    station.id = LBID(20);
    station.vehicleName = @"River power";
    station.meterUnit = LBUnit(@"cycles", world.context);
    Asset *battery = LBMakeAsset([Asset class], world.anna, @"EcoFlow", @"River 2 Pro Extra Battery", @"EB-0107", day, nil, nil, nil, NULL);
    battery.id = LBID(21);
    battery.vehicleName = @"River battery";
    battery.meterUnit = station.meterUnit;
    LBSave(world.context, @"the station and its battery");
    ComponentChange * (^change)(unsigned, Asset *, NSString *, StockUnit *) = ^ComponentChange *(unsigned n, Asset *on, NSString *moment, StockUnit *unit) {
        ComponentChange *made = LBInsert([ComponentChange class], world.context);
        LBEvent(world, made, (Vehicle *)on, n, moment);
        made.mileageQuantity = LBNumber(@"0");
        made.mileageDistanceUnit = on.meterUnit;
        made.stockUnit = unit;
        return made;
    };
    change(30, station, @"2026-07-01 10:00", battery.stockUnit);
    LBCheck(@"the battery fitted: in the station, one of its components",
            LBSave(world.context, @"fitted") && battery.parent == station && [station.components isEqualToSet:[NSSet setWithObject:battery]],
            battery.parent.vehicleName);
    change(31, battery, @"2026-07-02 10:00", station.stockUnit);
    why = LBRefusal(world.context);
    LBCheck(@"the station fitted in its own battery: refused, a cycle", [why containsString:@"is fitted in some Asset2 that is fitted in Asset1"], why);
    change(32, station, @"2026-07-02 10:00", station.stockUnit);
    why = LBRefusal(world.context);
    LBCheck(@"the station fitted in itself: refused", [why containsString:@"is fitted in that Asset"], why);
    Asset *spare = LBMakeNewAsset([Asset class], world.anna, @"Spare battery", day, NULL);
    spare.meterUnit = station.meterUnit;
    spare.vehicleName = @"Spare battery";
    ComponentChange *off = change(33, station, @"2026-07-03 10:00", spare.stockUnit);
    off.removedStockUnit = battery.stockUnit;
    LBCheck(@"replaced, the battery is in nothing; the spare in the station",
            LBSave(world.context, @"replaced") && !battery.parent && spare.parent == station, battery.parent.vehicleName);
    Asset *tray = LBMakeNewAsset([Asset class], world.anna, @"Tray", day, NULL);
    tray.meterUnit = station.meterUnit;
    tray.vehicleName = @"Tray";
    change(34, station, @"2026-07-04 10:00", tray.stockUnit);
    ComponentChange *into = change(35, station, @"2026-07-04 10:05", battery.stockUnit);
    into.host = tray.stockUnit;
    LBCheck(@"fitted into the tray on the station: in the station", LBSave(world.context, @"into the tray") && battery.parent == station,
            battery.parent.vehicleName);
    Asset *fan = LBMakeNewAsset([Asset class], world.anna, @"Fan", day, NULL);
    fan.meterUnit = station.meterUnit;
    fan.vehicleName = @"Fan";
    change(36, station, @"2026-07-05 10:00", fan.stockUnit).removedStockUnit = tray.stockUnit;
    LBCheck(@"the tray removed, the battery goes with it", LBSave(world.context, @"the tray off") && !battery.parent && !tray.parent,
            battery.parent.vehicleName);
}

/* Maintenance plans (docs/CSDP.md, A maintenance plan). */
static PlanTask *LBPlanTask(LBWorld *world, StockItem *item, unsigned n, NSString *task, Checklist *checklist, NSString *km, int32_t months) {
    PlanTask *plan = LBInsert([PlanTask class], world.context);
    plan.id = LBID(n);
    plan.stockItem = item;
    plan.task = task;
    plan.checklist = checklist;
    if (km) {
        plan.intervalQuantity = LBNumber(km);
        plan.intervalDistanceUnit = world.km;
    }
    if (months > 0) plan.duration = months;
    return plan;
}

/* The asset's schedule of the plan task: the one not ended, else the
   latest ended. */
static Schedule *LBFollowing(Asset *asset, PlanTask *plan) {
    Schedule *found = nil;
    for (Schedule *schedule in plan.schedules) {
        if (schedule.vehicle != asset || schedule.isDeleted) continue;
        if (!schedule.endedOn) return schedule;
        found = schedule;
    }
    return found;
}

static NSString *LBWarned(NSManagedObject *object) {
    NSMutableArray *said = [NSMutableArray array];
    if ([object respondsToSelector:@selector(orm_deonticViolations)]) {
        for (NSError *each in [(id)object orm_deonticViolations]) [said addObject:each.localizedDescription ?: @""];
    }
    return [said componentsJoinedByString:@"; "];
}

static void LBPlans(void) {
    LBWorld *world = LBNewWorld();
    NSDate *day = LBMoment(@"2000-01-01");
    Asset *first = LBMakeAsset([Asset class], world.anna, @"EcoFlow", @"River 2 Pro", @"R2P-0042", day, nil, nil, nil, NULL);
    first.id = LBID(20);
    first.vehicleName = @"River power";
    first.meterUnit = LBUnit(@"cycles", world.context);
    LBSave(world.context, @"a power station");
    StockItem *river = first.stockUnit.stockItem;
    Checklist *battery = LBInsert([Checklist class], world.context);
    battery.id = LBID(21);
    battery.checklistName = @"Battery check";
    battery.user = world.anna;
    PlanTask *check = LBPlanTask(world, river, 22, nil, battery, nil, 6);
    PlanTask *firmware = LBPlanTask(world, river, 23, @"Firmware update", nil, nil, 12);
    LBCheck(@"the maker's plan for the River 2 Pro: a battery check every 6 months, a firmware update every 12", LBSave(world.context, @"the plan"),
            nil);
    Schedule *checked = LBFollowing(first, check), *updated = LBFollowing(first, firmware);
    LBCheck(@"the station there before follows it: its schedules the plan's, each started", checked.checklist == battery && checked.duration == 6
                && [updated.task isEqualToString:@"Firmware update"] && updated.duration == 12 && checked.lb_openReminder && updated.lb_openReminder,
            [NSString stringWithFormat:@"%@ %d, %@ %d", checked.checklist.checklistName, checked.duration, updated.task, updated.duration]);
    Asset *second = LBMakeAsset([Asset class], world.anna, @"EcoFlow", @"River 2 Pro", @"R2P-0043", day, nil, nil, nil, NULL);
    second.id = LBID(24);
    second.vehicleName = @"River two";
    second.meterUnit = first.meterUnit;
    LBSave(world.context, @"a second station");
    Reminder *due = LBFollowing(second, firmware).lb_openReminder;
    LBCheck(@"one added after follows it from when it came in: its update due 12 months on, 2001-01-01",
            second.stockUnit.stockItem == river && [LBText(due.dueDate) hasPrefix:@"2001-01-01"], LBDue(due));
    firmware.duration = 24;
    LBSave(world.context, @"the plan revised");
    LBCheck(@"the plan revised (every 24 months): both stations' schedules follow it",
            LBFollowing(first, firmware).duration == 24 && LBFollowing(second, firmware).duration == 24,
            [NSString stringWithFormat:@"%d %d", LBFollowing(first, firmware).duration, LBFollowing(second, firmware).duration]);
    NSError *error = nil;
    Schedule *changed = [updated lb_continueWithTask:@"Firmware update" expenseKind:nil checklist:nil interval:nil unit:nil months:36 note:nil
                                                  by:world.anna at:[NSDate date] cancelled:NULL error:&error];
    LBCheck(@"a plan's schedule changed by its owner: refused, the plan is changed in Stock", !changed && [error.localizedDescription containsString:@"maker's plan"],
            error.localizedDescription);

    /* Moved and cancelled: recorded, and warned of. */
    Rescheduling *moved = [due lb_rescheduleToDate:LBMoment(@"2001-03-01") mileage:nil unit:nil note:nil by:world.anna at:[NSDate date] error:&error];
    BOOL saved = moved && LBSave(world.context, @"moved");
    LBCheck(@"a plan's reminder moved: saved, and warned of", saved && [LBWarned(moved) containsString:@"forbidden"], LBWarned(moved) ?: error);
    Reminder *open = LBFollowing(first, check).lb_openReminder;
    saved = [open lb_cancelOn:nil replacementDueDate:nil mileage:nil unit:nil by:world.anna at:[NSDate date] replacement:NULL error:&error]
            && LBSave(world.context, @"cancelled");
    LBCheck(@"a plan's reminder cancelled: saved, and warned of", saved && [LBWarned(open) containsString:@"forbidden"], LBWarned(open) ?: error);

    /* A second schedule of the same plan task: refused. */
    Schedule *twice = LBInsert([Schedule class], world.context);
    twice.id = LBID(25);
    twice.vehicle = first;
    twice.enteredBy = world.anna;
    twice.planTask = check;
    twice.checklist = battery;
    twice.duration = 6;
    NSString *why = LBRefusal(world.context);
    LBCheck(@"an asset following a plan task twice: refused", [why containsString:@"follows that PlanTask"], why);

    /* A plan by kilometres for what counts cycles, and by no time: refused. */
    LBPlanTask(world, river, 26, @"Fan clean", nil, @"1000", 0);
    why = LBRefusal(world.context);
    LBCheck(@"a plan by km for a station metered in cycles: refused, said so", [why containsString:@"counted in km"], why);

    /* A chain's plan, brought to the bicycle it is fitted to. */
    Vehicle *bike = LBMakeAsset([Vehicle class], world.anna, @"Surly", @"Long Haul Trucker", nil, day, nil, nil, nil, NULL);
    bike.id = LBID(30);
    bike.vehicleName = @"Commuter";
    bike.vehicleKind = @"Bicycle";
    bike.meterUnit = world.km;
    LBSave(world.context, @"a bicycle");
    Catalog *catalog = river.catalog;
    StockItem * (^itemOf)(unsigned, NSString *) = ^StockItem *(unsigned n, NSString *name) {
        StockItem *item = LBInsert([StockItem class], world.context);
        item.id = LBID(n);
        item.itemName = name;
        item.catalog = catalog;
        item.created = [NSDate date];
        item.sku = [NSString stringWithFormat:@"PL-%u", n];
        return item;
    };
    StockUnit * (^unitOf)(unsigned, StockItem *) = ^StockUnit *(unsigned n, StockItem *item) {
        StockUnit *unit = LBInsert([StockUnit class], world.context);
        unit.id = LBID(n);
        unit.stockItem = item;
        return unit;
    };
    StockItem *chains = itemOf(36, @"KMC X9");
    StockUnit *kmc = unitOf(37, chains);
    PlanTask *chainPlan = LBPlanTask(world, chains, 31, @"Chain", nil, @"3000", 0);
    LBSave(world.context, @"a chain and its plan");
    ComponentChange * (^change)(unsigned, NSString *, NSString *, StockUnit *) = ^ComponentChange *(unsigned n, NSString *moment, NSString *km, StockUnit *unit) {
        ComponentChange *made = LBInsert([ComponentChange class], world.context);
        LBEvent(world, made, bike, n, moment);
        made.mileageQuantity = LBNumber(km);
        made.mileageDistanceUnit = world.km;
        made.stockUnit = unit;
        return made;
    };
    change(32, @"2026-08-01 10:00", @"3900", kmc);
    LBSave(world.context, @"the chain fitted");
    Schedule *chainSchedule = LBFollowing(bike, chainPlan);
    LBCheck(@"the chain fitted brings its plan: the bicycle's chain due 3000 km on, at 6900", LBIs(chainSchedule.lb_openReminder.dueMileageQuantity, @"6900"),
            LBDue(chainSchedule.lb_openReminder));
    StockUnit *another = unitOf(33, chains);
    change(34, @"2026-10-01 10:00", @"6800", another).removedStockUnit = kmc;
    LBSave(world.context, @"a new chain of the same");
    Reminder *next = LBFollowing(bike, chainPlan).lb_openReminder;
    LBCheck(@"replaced by another of its item: the change did the work, the next due at 9800", LBIs(next.dueMileageQuantity, @"9800"), LBDue(next));
    StockUnit *belt = unitOf(39, itemOf(38, @"Gates CDX belt"));
    change(35, @"2026-11-01 10:00", @"7000", belt).removedStockUnit = another;
    Reminder *wasOpen = next;
    saved = LBSave(world.context, @"a belt");
    Schedule *ended = LBFollowing(bike, chainPlan);
    LBCheck(@"the chain taken off for a belt: its schedule ended, its reminder cancelled, none made; no warning",
            saved && ended.endedOn && wasOpen.cancelDate && !ended.lb_openReminder && !LBWarned(wasOpen).length,
            [NSString stringWithFormat:@"ended %@, cancelled %@, open %@, warned %@", ended.endedOn, wasOpen.cancelDate,
                                       LBDue(ended.lb_openReminder), LBWarned(wasOpen)]);
    change(40, @"2026-11-20 10:00", @"7400", unitOf(41, chains)).removedStockUnit = belt;
    saved = LBSave(world.context, @"a chain again");
    Schedule *again = LBFollowing(bike, chainPlan);
    LBCheck(@"a chain fitted again: a new schedule follows the plan, the chain due at 10400; the ended one as it was",
            saved && again != ended && !again.endedOn && LBIs(again.lb_openReminder.dueMileageQuantity, @"10400") && !ended.lb_openReminder,
            LBDue(again.lb_openReminder));

    /* A plan task deleted: its schedules' reminders gone. */
    Schedule *secondCheck = LBFollowing(second, check);
    Reminder *checkDue = secondCheck.lb_openReminder;
    [world.context deleteObject:check];
    LBCheck(@"a plan task deleted: the stations' schedules of it ended, their reminders cancelled",
            LBSave(world.context, @"the check gone") && secondCheck.endedOn && checkDue.cancelDate && !secondCheck.lb_openReminder,
            [NSString stringWithFormat:@"%@ %@", secondCheck.endedOn, checkDue.cancelDate]);
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
        LBContinue();
        LBPlanning();
        LBTimeZones();
        LBKindsAndComponents();
        LBFuelAndHierarchy();
        LBPlans();
        printf("procedures: %lu failed\n", (unsigned long)LBFailures);
    }
    return LBFailures ? 1 : 0;
}
