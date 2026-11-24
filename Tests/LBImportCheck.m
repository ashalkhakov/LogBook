// Another app's export imported (Shared/LBImport.h) into a vehicle of a
// store of the model's own, through the model's forms as the app enters
// them. Each check a line, "ok" or "FAIL"; 1 when one failed.
//
//   lb-import-check build/Logbook.momd build/Logbook.ormplans build/Model/Forms Tests/drivvo-export.csv Tests/maintrack-store.sql
//
// - Drivvo's CSV read: its sections, the vehicle it is of, how many of
//   each; a quoted field with commas and quotes in it;
// - planned against a vehicle: what Logbook has no place for said (its
//   tank size, a fill-up's payment method), Drivvo's fuel taken as the
//   vehicle's and said so;
// - imported: each fill-up as Drivvo had it (its moment in the user's time
//   zone, reading, volume, cost in the user's currency, station, the tank,
//   its driver by name, the user where none), the service of two rows one
//   service of two tasks, its discount, its garage;
// - imported again: nothing made, each passed over;
// - refused, and said, nothing made: a driver who does not drive the
//   vehicle, a section Logbook does not read yet, no currency to take, a
//   record the store's rules refuse (a cost below nothing). The rules the
//   server checks where a record is submitted (a reading lower than an
//   earlier one) it checks when the import is synced, as of one typed.
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMTables.h>
#import "LogbookValidation.h"
#import "LBImport.h"
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"
#import "Trip+CoreDataClass.h"
#import "VehicleComponent+CoreDataClass.h"
#import "ComponentChange+CoreDataClass.h"
#import "LBProcedures.h"
#include <sqlite3.h>
#import "VehicleDriver+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"
#import "VolumeUnit+CoreDataClass.h"

static NSUInteger LBFailures;
static NSManagedObjectModel *LBModel;
static NSString *LBForms;

static void LBCheck(NSString *what, BOOL ok, id detail) {
    printf("%s %s%s\n", ok ? "ok  " : "FAIL", what.UTF8String,
           ok || !detail ? "" : [[NSString stringWithFormat:@": %@", detail] UTF8String]);
    fflush(stdout);
    if (!ok) LBFailures++;
}

static id LBInsert(Class cls, NSManagedObjectContext *context) {
    return [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass(cls) inManagedObjectContext:context];
}

static NSManagedObjectContext *LBNewStore(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"lb-import-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
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

static User *LBUser(NSString *email, NSString *name, NSManagedObjectContext *context) {
    User *user = LBInsert([User class], context);
    user.email = email;
    user.personName = name;
    user.currency = @"EUR";
    user.timeZone = @"Europe/Berlin";
    return user;
}

static LBImport *LBRead(NSString *text, NSError **error) {
    LBImport *import = [LBImport importOfData:[text dataUsingEncoding:NSUTF8StringEncoding] named:@"export.csv" error:error];
    import.formNamed = ^ORMForm *(NSString *name, NSError **failure) {
        NSData *data = [NSData dataWithContentsOfFile:[LBForms stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"ormform"]]];
        id list = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:failure] : nil;
        return list ? [ORMForm formWithPropertyList:list error:failure] : nil;
    };
    return import;
}

static NSArray *LBRecords(Class cls, Vehicle *vehicle) {
    NSMutableArray *found = [NSMutableArray array];
    for (id record in vehicle.records) if ([record isKindOfClass:cls]) [found addObject:record];
    return [found sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:YES] ]];
}

static BOOL LBIs(NSDecimalNumber *number, NSString *text) {
    return number && [number compare:[NSDecimalNumber decimalNumberWithString:text]] == NSOrderedSame;
}

static void LBDrivvoSteps(NSString *export) {
    NSManagedObjectContext *context = LBNewStore();
    User *anna = LBUser(@"anna@example.org", @"Anna Driver", context);
    User *ben = LBUser(@"ben@example.org", @"Ben Driver", context);
    Vehicle *golf = LBInsert([Vehicle class], context);
    golf.id = [NSUUID UUID];
    golf.vehicleName = @"Golf";
    golf.make = @"Volkswagen";
    golf.carModel = @"Golf";
    golf.manufactureYear = 2016;
    golf.fuel = @"Petrol";
    golf.owner = anna;
    VehicleDriver *sharing = LBInsert([VehicleDriver class], context);
    sharing.id = [NSUUID UUID];
    sharing.vehicle = golf;
    sharing.user = ben;
    NSError *error = nil;
    if (![context orm_prepareForSave:&error] || ![context save:&error]) {
        LBCheck(@"the people and their car saved", NO, error);
        return;
    }
    LBImportSaving saving = ^BOOL(NSManagedObjectContext *c, NSError **failure) {
        return [c orm_prepareForSave:failure] && [c save:failure];
    };

    LBImport *import = LBRead(export, &error);
    LBCheck(@"Drivvo's export read", import && [import.source isEqualToString:@"Drivvo"], error);
    LBCheck(@"of the Golf: 3 fill-ups, a service", [import.vehicleNames isEqualToArray:@[ @"Golf" ]]
                && [import.counts[@"fill-ups"] isEqual:@3] && [import.counts[@"services"] isEqual:@1],
            [NSString stringWithFormat:@"%@ %@", import.vehicleNames, import.counts]);
    LBCheck(@"planned against the Golf", [import planForVehicle:golf by:anna error:&error], error);
    NSString *said = [import.leftOut componentsJoinedByString:@"\n"];
    LBCheck(@"said: its tank size, Ben's card, Drivvo's Gasoline as the Golf's Petrol, its service as Maintenance",
            [said containsString:@"fuel capacity 50.00"] && [said containsString:@"payment method 'Card'"]
                && [said containsString:@"'Gasoline' entered as the vehicle's, 'Petrol'"] && [said containsString:@"entered as Maintenance"]
                && import.leftOut.count == 4,
            said);

    NSUInteger made = 0, skipped = 0;
    BOOL done = [import importIntoVehicle:golf by:anna context:context saving:saving made:&made skipped:&skipped error:&error];
    LBCheck(@"imported: 4 made, none passed over", done && made == 4 && skipped == 0,
            error ?: [NSString stringWithFormat:@"%lu made, %lu passed over", (unsigned long)made, (unsigned long)skipped]);
    NSArray<FillUp *> *fills = LBRecords([FillUp class], golf);
    FillUp *first = fills.firstObject, *last = fills.lastObject;
    NSDateComponents *berlin = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]
        componentsInTimeZone:[NSTimeZone timeZoneWithName:@"Europe/Berlin"] fromDate:first.timestamp ?: [NSDate date]];
    LBCheck(@"three fill-ups, in time's order", fills.count == 3, @(fills.count));
    LBCheck(@"the first as Drivvo had it: 08:30 in Berlin, 12350 km, 40 L of the Golf's Petrol, 70 EUR at Shell, the tank filled, by Anna",
            berlin.hour == 8 && berlin.minute == 30 && berlin.day == 10 && LBIs(first.mileageQuantity, @"12350")
                && [first.mileageDistanceUnit.code isEqualToString:@"km"] && LBIs(first.volumeQuantity, @"40")
                && [first.volumeVolumeUnit.code isEqualToString:@"L"] && [first.fuel isEqualToString:@"Petrol"]
                && LBIs(first.totalAmount, @"70") && [first.totalCurrency isEqualToString:@"EUR"] && [first.station isEqualToString:@"Shell"]
                && first.filledTheTank && first.driver == anna && first.enteredBy == anna,
            [NSString stringWithFormat:@"%@ %ld:%ld %@ %@ %@ %@ %@ %@ %@", first.timestamp, (long)berlin.hour, (long)berlin.minute,
                                       first.mileageQuantity, first.volumeQuantity, first.fuel, first.totalAmount, first.station,
                                       first.driver.email, first.note]);
    LBCheck(@"its note, quotes and a comma in it", [first.note isEqualToString:@"Before the trip, \"north\""], first.note);
    LBCheck(@"the half fill-up not filling the tank; the last Ben's, at Aral", fills.count == 3 && !fills[1].filledTheTank
                && last.driver == ben && [last.station isEqualToString:@"Aral"],
            last.driver.email);
    Service *service = LBRecords([Service class], golf).firstObject;
    NSArray *tasks = [[service.serviceItems valueForKey:@"task"] allObjects];
    NSDecimalNumber *costs = [service.serviceItems valueForKeyPath:@"@sum.costAmount"];
    LBCheck(@"the service's two rows one service: Oil change and Labour, 260 EUR, 5 EUR off, at Garage Krause",
            service && service.serviceItems.count == 2 && [tasks containsObject:@"Oil change"] && [tasks containsObject:@"Labour"]
                && LBIs(costs, @"260") && LBIs(service.moneyAmount, @"5") && [service.garage isEqualToString:@"Garage Krause"]
                && [service.title isEqualToString:@"Spring service"] && [service.paymentMethod isEqualToString:@"Money"]
                && [service.note isEqualToString:@"Filter: Mann W 712/95"] && LBIs(service.mileageQuantity, @"12700")
                && [service.serviceKind.name isEqualToString:@"Maintenance"],
            [NSString stringWithFormat:@"%@ %@ %@ %@ %@", tasks, costs, service.moneyAmount, service.garage, service.title]);

    import = LBRead(export, &error);
    done = [import importIntoVehicle:golf by:anna context:context saving:saving made:&made skipped:&skipped error:&error];
    LBCheck(@"imported again: nothing made, the 4 passed over", done && made == 0 && skipped == 4 && LBRecords([FillUp class], golf).count == 3,
            error ?: [NSString stringWithFormat:@"%lu made, %lu passed over", (unsigned long)made, (unsigned long)skipped]);

    /* A service naming no garage (done at home): made, of none. */
    NSString *home = [[export stringByReplacingOccurrencesOfString:@"Garage Krause" withString:@""]
        stringByReplacingOccurrencesOfString:@"2026-03-16 10:00:00" withString:@"2026-03-17 10:00:00"];
    import = LBRead(home, &error);
    done = [import importIntoVehicle:golf by:anna context:context saving:saving made:&made skipped:&skipped error:&error];
    Service *athome = LBRecords([Service class], golf).lastObject;
    LBCheck(@"a service at no garage: made, of none", done && made == 1 && skipped == 3 && athome.garage == nil
                && athome.serviceItems.count == 2,
            error ?: athome.garage);

    /* Refused, nothing made. */
    NSUInteger before = golf.records.count;
    import = LBRead([export stringByReplacingOccurrencesOfString:@"Ben Driver" withString:@"Carl Other"], &error);
    done = [import importIntoVehicle:golf by:anna context:context saving:saving made:&made skipped:&skipped error:&error];
    LBCheck(@"a driver who does not drive the Golf: refused, by name", !done && [error.localizedDescription containsString:@"Carl Other"]
                && golf.records.count == before,
            error.localizedDescription);
    error = nil;
    import = LBRead([export stringByAppendingString:@"\n##Expense\n\"Odometer (km)\",\"Date\"\n\"1\",\"2026-01-01 00:00:00\"\n"], &error);
    LBCheck(@"a section not read yet: refused, by name", !import && [error.localizedDescription containsString:@"Expense"],
            error.localizedDescription);
    anna.currency = nil;
    import = LBRead(export, &error);
    done = [import planForVehicle:golf by:anna error:&error];
    LBCheck(@"no currency of the user's: refused, said", !done && [error.localizedDescription containsString:@"currency"], error.localizedDescription);
    anna.currency = @"EUR";
    [context save:NULL];
    /* A cost of nothing is none Logbook records (an amount is more than 0):
       the store's rule, as typing it would be. */
    NSString *free = [[export stringByReplacingOccurrencesOfString:@"\"35.60\"" withString:@"\"-5.00\""]
        stringByReplacingOccurrencesOfString:@"2026-03-14 12:00:00" withString:@"2026-03-14 12:30:00"];
    error = nil;
    import = LBRead(free, &error);
    done = [import importIntoVehicle:golf by:anna context:context saving:saving made:&made skipped:&skipped error:&error];
    LBCheck(@"a cost below nothing: refused by the model's rule, the record said, nothing made of it",
            !done && [error.localizedDescription containsString:@"Refuelling 3"] && made == 0 && golf.records.count == before
                && !context.hasChanges,
            error.localizedDescription ?: @(made));
    printf("said: %s\n", error.localizedDescription.UTF8String);
}

/* MainTrack's store (Tests/maintrack-store.sql, made a SQLite file here):
   its bikes made bicycles of the user's, a bike of no brand or model by
   its name; its rides trips, their readings added up; its components of
   the bike they were first on (a tyre, of the bike its wheel was on), each
   assignment a change fitting it, the wheel taken off retired by the one
   fitted then, two alike fitted at once both; an invoice a service, its
   log entries the tasks, the amount on the first, a free one's at no
   cost; what has no place said (retired, a component on no bike, an
   invoice of no bike, a plan); imported again, nothing made. */
static void LBMainTrackSteps(NSString *sqlPath) {
    NSString *sql = [NSString stringWithContentsOfFile:sqlPath encoding:NSUTF8StringEncoding error:NULL];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"Maintrack-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
    sqlite3 *db = NULL;
    char *failed = NULL;
    BOOL made = sql && sqlite3_open(path.fileSystemRepresentation, &db) == SQLITE_OK && sqlite3_exec(db, sql.UTF8String, NULL, NULL, &failed) == SQLITE_OK;
    LBCheck(@"MainTrack's store made, from Tests/maintrack-store.sql", made, failed ? @(failed) : sqlPath);
    if (db) sqlite3_close(db);
    if (!made) return;

    NSManagedObjectContext *context = LBNewStore();
    User *anna = LBUser(@"anna@example.org", @"Anna Driver", context);
    NSError *error = nil;
    if (![context orm_prepareForSave:&error] || ![context save:&error]) {
        LBCheck(@"the user saved", NO, error);
        return;
    }
    LBImportSaving saving = ^BOOL(NSManagedObjectContext *c, NSError **failure) {
        return [c orm_prepareForSave:failure] && [c save:failure];
    };
    LBImport *import = [LBImport importOfFile:[NSURL fileURLWithPath:path] error:&error];
    import.formNamed = ^ORMForm *(NSString *name, NSError **failure) {
        NSData *data = [NSData dataWithContentsOfFile:[LBForms stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"ormform"]]];
        id list = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:failure] : nil;
        return list ? [ORMForm formWithPropertyList:list error:failure] : nil;
    };
    LBCheck(@"MainTrack's store read: 2 bicycles, 7 components, 4 rides, 2 services", import && [import.source isEqualToString:@"MainTrack"]
                && import.makesVehicles && [import.counts[@"bicycles"] isEqual:@2] && [import.counts[@"components"] isEqual:@7]
                && [import.counts[@"rides"] isEqual:@4] && [import.counts[@"services"] isEqual:@2],
            error ?: import.counts);
    LBCheck(@"planned with no vehicle chosen", [import planForVehicle:nil by:anna error:&error], error);
    NSString *said = [import.leftOut componentsJoinedByString:@"\n"];
    LBCheck(@"said: Old Frame's name as its make and model, retired; the saddle on no bike; an invoice of no bike; the plan",
            [said containsString:@"Old Frame: no brand or model"] && [said containsString:@"Old Frame: retired"]
                && [said containsString:@"Spare saddle: on no bike"] && [said containsString:@"2022-09-28 at VeloDim: of no bike"]
                && [said containsString:@"1 service plans"] && [said containsString:@"its size '56'"],
            said);
    NSUInteger madeCount = 0, skipped = 0;
    BOOL done = [import importIntoVehicle:nil by:anna context:context saving:saving made:&madeCount skipped:&skipped error:&error];
    LBCheck(@"imported: 2 bicycles, 6 components, 4 trips, 6 changes, 2 services", done && madeCount == 20 && skipped == 0,
            error ?: [NSString stringWithFormat:@"%lu made, %lu passed over", (unsigned long)madeCount, (unsigned long)skipped]);
    Vehicle *commuter = nil, *old = nil;
    for (Vehicle *each in anna.ownedVehicles) {
        if ([each.vehicleName isEqualToString:@"Commuter"]) commuter = each;
        if ([each.vehicleName isEqualToString:@"Old Frame"]) old = each;
    }
    LBCheck(@"Commuter a bicycle, a Surly Long Haul Trucker of 2019, bought for 1200 EUR; Old Frame its name as its make and model",
            [commuter.vehicleKind isEqualToString:@"Bicycle"] && [commuter.make isEqualToString:@"Surly"]
                && [commuter.carModel isEqualToString:@"Long Haul Trucker"] && commuter.manufactureYear == 2019
                && LBIs(commuter.purchasePriceAmount, @"1200") && [commuter.purchasePriceCurrency isEqualToString:@"EUR"] && commuter.purchaseDate
                && [old.make isEqualToString:@"Old Frame"] && [old.carModel isEqualToString:@"Old Frame"] && !old.fuel,
            [NSString stringWithFormat:@"%@ %@ %@ %d; %@ %@", commuter.vehicleKind, commuter.make, commuter.carModel, commuter.manufactureYear,
                                       old.make, old.carModel]);
    NSArray<Trip *> *trips = LBRecords([Trip class], commuter);
    LBCheck(@"its rides trips, the readings added up: 0-10, 10-30, 30-45 km, the Zwift one virtual",
            trips.count == 3 && LBIs(trips[0].mileageQuantity, @"0") && LBIs(trips[0].distanceQuantity, @"10")
                && LBIs(trips[1].mileageQuantity, @"10") && LBIs(trips[1].distanceQuantity, @"30") && LBIs(trips[2].mileageQuantity, @"30")
                && LBIs(trips[2].distanceQuantity, @"45") && [trips[2].note containsString:@"(virtual ride)"]
                && [trips[0].note containsString:@"(commute)"] && [trips[0].moment timeIntervalSinceDate:trips[0].timestamp] == 1800,
            [trips valueForKey:@"distanceQuantity"]);
    NSMutableDictionary<NSString *, VehicleComponent *> *parts = [NSMutableDictionary dictionary];
    NSUInteger tyres = 0;
    for (Record *record in commuter.records) {
        if (![record isKindOfClass:[VehicleComponent class]]) continue;
        VehicleComponent *part = (VehicleComponent *)record;
        parts[part.componentName] = part;
        if ([part.componentKind isEqualToString:@"Tyre"]) tyres++;
    }
    VehicleComponent *wheels = parts[@"Shimano WH-R500"], *mavic = parts[@"Mavic 27\""];
    LBCheck(@"its components: the two wheel sets, both tyres (on its wheel), both chainrings; the WH-R500 bought for 3581",
            parts.count == 5 && tyres == 2 && wheels && mavic && parts[@"Inner chainring, 38 teeth"] && parts[@"Outer chainring, 50 teeth"]
                && LBIs(wheels.totalAmount, @"3581") && wheels.date && !mavic.date,
            parts.allKeys);
    ComponentChange *fit = wheels.componentChange;
    LBCheck(@"the WH-R500 fitted on 2020-03-13 at 10 km, retiring the Mavic set", fit && LBIs(fit.mileageQuantity, @"10")
                && fit.retiredVehicleComponent == mavic && mavic.wasRetiredByComponentChange == fit,
            fit.retiredVehicleComponent.componentName);
    DistanceUnit *km = [[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"DistanceUnit"] error:NULL]
        filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"code == 'km'"]].firstObject;
    LBCheck(@"its wear: 35 km since (to the latest reading, 45)", [[wheels lb_wornIn:km] isEqualToNumber:@35], [wheels lb_wornIn:km]);
    NSArray<Service *> *services = LBRecords([Service class], commuter);
    Service *home = services.firstObject, *shop = services.lastObject;
    NSArray<ServiceItem *> *shopItems = [shop.serviceItems.allObjects sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"task" ascending:YES] ]];
    LBCheck(@"two services: the chain cleaned at home at no cost, at 30 km; at VeloDim the BB replaced (1360) and the chain lubed (no cost), at 45 km",
            services.count == 2 && [home.garage isEqualToString:@"myself"] && home.serviceItems.count == 1
                && !((ServiceItem *)home.serviceItems.anyObject).costAmount && LBIs(home.mileageQuantity, @"30")
                && [shop.garage isEqualToString:@"VeloDim"] && shopItems.count == 2 && [shopItems[0].task isEqualToString:@"Lub Chain"]
                && !shopItems[0].costAmount && [shopItems[0].note isEqualToString:@"Ceramic lube"]
                && [shopItems[1].task isEqualToString:@"Replace Bottom Bracket"] && LBIs(shopItems[1].costAmount, @"1360")
                && [shop.note containsString:@"Invoice A-17."] && LBIs(shop.mileageQuantity, @"45"),
            [NSString stringWithFormat:@"%@ / %@", [home.serviceItems valueForKey:@"task"], [shop.serviceItems valueForKey:@"task"]]);

    import = [LBImport importOfFile:[NSURL fileURLWithPath:path] error:&error];
    import.formNamed = ^ORMForm *(NSString *name, NSError **failure) {
        NSData *data = [NSData dataWithContentsOfFile:[LBForms stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"ormform"]]];
        id list = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:failure] : nil;
        return list ? [ORMForm formWithPropertyList:list error:failure] : nil;
    };
    done = [import importIntoVehicle:nil by:anna context:context saving:saving made:&madeCount skipped:&skipped error:&error];
    LBCheck(@"imported again: nothing made, the 20 passed over", done && madeCount == 0 && skipped == 20 && anna.ownedVehicles.count == 2,
            error ?: [NSString stringWithFormat:@"%lu made, %lu passed over", (unsigned long)madeCount, (unsigned long)skipped]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 5) {
            fprintf(stderr, "usage: lb-import-check Logbook.momd Logbook.ormplans Forms/ drivvo-export.csv\n");
            return 2;
        }
        LBModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@(argv[1])]];
        NSError *error = nil;
        NSData *plans = [NSData dataWithContentsOfFile:@(argv[2])];
        id list = plans ? [NSPropertyListSerialization propertyListWithData:plans options:0 format:NULL error:&error] : nil;
        ORMTables *tables = list ? [ORMTables tablesWithPropertyList:list error:&error] : nil;
        LBForms = @(argv[3]);
        NSString *export = [NSString stringWithContentsOfFile:@(argv[4]) encoding:NSUTF8StringEncoding error:&error];
        if (!LBModel.entities.count || !tables || !export) {
            fprintf(stderr, "no model at %s, tables at %s, or export at %s: %s\n", argv[1], argv[2], argv[4],
                    error.localizedDescription.UTF8String ?: "");
            return 2;
        }
        [ORMTables registerTables:tables named:@"Logbook"];
        LBDrivvoSteps(export);
        if (argc > 5) LBMainTrackSteps(@(argv[5]));
        printf("import: %lu failed\n", (unsigned long)LBFailures);
    }
    return LBFailures ? 1 : 0;
}
