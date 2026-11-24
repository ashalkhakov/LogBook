// Another app's export imported (Shared/LBImport.h) into a vehicle of a
// store of the model's own, through the model's forms as the app enters
// them. Each check a line, "ok" or "FAIL"; 1 when one failed.
//
//   lb-import-check build/Logbook.momd build/Logbook.ormplans build/Model/Forms Tests/drivvo-export.csv Tests/maintrack-store.sql \
//     Tests/inventree 29
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
//
// InvenTree's API answered from a folder of its JSON (Tests/inventree, made
// up; or a copy of a real one's, with no count after it): no catalog named,
// refused; imported into Home, so many made; each order line of the item
// its supplier part is of (a line's part is a supplier part's number, not
// a part's); with the fixtures, each part, supplier part, location, order
// and unit as InvenTree has it, a price bought outside an order said;
// imported again, nothing made.
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
#import "StockUnit+CoreDataClass.h"
#import "StockItem+CoreDataClass.h"
#import "Catalog+CoreDataClass.h"
#import "Category+CoreDataClass.h"
#import "ComponentChange+CoreDataClass.h"
#import "PurchaseOrder+CoreDataClass.h"
#import "PurchaseLine+CoreDataClass.h"
#import "SupplierItem+CoreDataClass.h"
#import "Supplier+CoreDataClass.h"
#import "Contact+CoreDataClass.h"
#import "Warehouse+CoreDataClass.h"
#import "Location+CoreDataClass.h"
#import "LBProcedures.h"
#import "LBStockProcedures.h"
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

/* Drivvo's export into no vehicle chosen: the user's it is, by its plate
   (written otherwise), else its model (one vehicle only); none, one made
   of the export, its make (and year: the export says 0) said, refused
   unsaid; imported again, the one made found by its name, nothing made. */
static void LBDrivvoMatchSteps(NSString *export) {
    /* Ben, who drives no one's vehicle here, left out. */
    NSString *anyone = [export stringByReplacingOccurrencesOfString:@"\"Ben Driver\"" withString:@"\"\""];
    LBImportSaving saving = ^BOOL(NSManagedObjectContext *c, NSError **failure) {
        return [c orm_prepareForSave:failure] && [c save:failure];
    };
    NSError *error = nil;
    NSManagedObjectContext *context = LBNewStore();
    User *anna = LBUser(@"anna@example.org", @"Anna Driver", context);
    Vehicle *(^car)(NSString *, NSString *, NSString *) = ^Vehicle *(NSString *name, NSString *model, NSString *plate) {
        Vehicle *vehicle = LBInsert([Vehicle class], context);
        vehicle.id = [NSUUID UUID];
        vehicle.vehicleKind = @"Car";
        vehicle.vehicleName = name;
        vehicle.make = @"Volkswagen";
        vehicle.carModel = model;
        vehicle.manufactureYear = 2016;
        vehicle.fuel = @"Petrol";
        vehicle.registrationNumber = plate;
        vehicle.owner = anna;
        return vehicle;
    };
    Vehicle *golf = car(@"Golf '16", @"Golf", nil);
    Vehicle *polo = car(@"Town car", @"Polo", @"01abc123");
    if (![context orm_prepareForSave:&error] || ![context save:&error]) {
        LBCheck(@"Anna's cars saved", NO, error);
        return;
    }
    LBImport *import = LBRead(anyone, &error);
    BOOL planned = [import planForVehicle:nil by:anna error:&error];
    LBCheck(@"no vehicle chosen: Anna's Golf '16, by its model", planned && import.matchedVehicle == golf && !import.makesItsVehicle
                && [import.matchedHow isEqualToString:@"by its model"],
            error ?: [NSString stringWithFormat:@"%@ %@", import.matchedVehicle.vehicleName, import.matchedHow]);
    NSString *plated = [anyone stringByReplacingOccurrencesOfString:@"\"\",\"Golf\",\"\"" withString:@"\"\",\"Golf\",\"01 ABC-123\""];
    import = LBRead(plated, &error);
    planned = [import planForVehicle:nil by:anna error:&error];
    LBCheck(@"its plate 01 ABC-123: Anna's car of 01abc123, by its licence plate, before its model",
            planned && import.matchedVehicle == polo && [import.matchedHow isEqualToString:@"by its licence plate"],
            error ?: [NSString stringWithFormat:@"%@ %@", import.matchedVehicle.vehicleName, import.matchedHow]);

    /* Dan has no vehicle: one is made. */
    User *dan = LBUser(@"dan@example.org", @"Anna Driver", context);
    [context save:NULL];
    import = LBRead(anyone, &error);
    planned = [import planForVehicle:nil by:dan error:&error];
    LBCheck(@"none of Dan's: a new vehicle, Golf, its year unsaid (0)",
            planned && import.makesItsVehicle && [import.madeVehicleName isEqualToString:@"Golf"] && import.exportYear == 0, error);
    NSUInteger made = 0, skipped = 0;
    error = nil;
    BOOL done = [import importIntoVehicle:nil by:dan context:context saving:saving made:&made skipped:&skipped error:&error];
    LBCheck(@"its make and year unsaid: refused, said, nothing made", !done && made == 0 && [error.localizedDescription containsString:@"make and year"]
                && dan.ownedVehicles.count == 0,
            error);
    import.madeVehicleMake = @"Volkswagen";
    import.madeVehicleYear = 2016;
    error = nil;
    done = [import importIntoVehicle:nil by:dan context:context saving:saving made:&made skipped:&skipped error:&error];
    Vehicle *made_ = dan.ownedVehicles.anyObject;
    LBCheck(@"given them: the Golf made (a car, Volkswagen, 2016, its Gasoline), its 4 records in it: 5 made",
            done && made == 5 && dan.ownedVehicles.count == 1 && [made_.vehicleName isEqualToString:@"Golf"] && [made_.make isEqualToString:@"Volkswagen"]
                && made_.manufactureYear == 2016 && [made_.fuel isEqualToString:@"Gasoline"] && [made_.vehicleKind isEqualToString:@"Car"]
                && made_.records.count == 4,
            error ?: [NSString stringWithFormat:@"%lu made; %@ %@ %d %@ %lu records", (unsigned long)made, made_.vehicleName, made_.make,
                                                made_.manufactureYear, made_.fuel, (unsigned long)made_.records.count]);
    import = LBRead(anyone, &error);
    done = [import importIntoVehicle:nil by:dan context:context saving:saving made:&made skipped:&skipped error:&error];
    LBCheck(@"imported again: the Golf found by its name, nothing made", done && made == 0 && skipped == 4 && dan.ownedVehicles.count == 1
                && [import.matchedHow isEqualToString:@"by its name"],
            error ?: [NSString stringWithFormat:@"%lu made, %lu passed over, %@", (unsigned long)made, (unsigned long)skipped, import.matchedHow]);
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
    BOOL made = sql && sqlite3_open(path.UTF8String, &db) == SQLITE_OK && sqlite3_exec(db, sql.UTF8String, NULL, NULL, &failed) == SQLITE_OK;
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
    LBCheck(@"said: Old Frame's name as its make and model, retired; the saddle never fitted; an invoice of no bike; the plan",
            [said containsString:@"Old Frame: no brand or model"] && [said containsString:@"Old Frame: retired"]
                && [said containsString:@"Spare saddle: never fitted"] && [said containsString:@"2022-09-28 at VeloDim: of no bike"]
                && [said containsString:@"1 service plans"] && [said containsString:@"its size '56'"],
            said);
    NSUInteger madeCount = 0, skipped = 0;
    BOOL done = [import importIntoVehicle:nil by:anna context:context saving:saving made:&madeCount skipped:&skipped error:&error];
    LBCheck(@"imported: 2 bicycles, a catalog, 6 items and their 7 units, 4 trips, 6 changes, 2 services", done && madeCount == 28 && skipped == 0,
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
                && [old.make isEqualToString:@"Old Frame"] && [old.carModel isEqualToString:@"Old Frame"] && !old.fuel
                && commuter.hasNoMeter && old.hasNoMeter,
            [NSString stringWithFormat:@"%@ %@ %@ %d; %@ %@", commuter.vehicleKind, commuter.make, commuter.carModel, commuter.manufactureYear,
                                       old.make, old.carModel]);
    NSArray<Trip *> *trips = LBRecords([Trip class], commuter);
    LBCheck(@"its rides trips, the readings added up: 0-10, 10-30, 30-45 km, the Zwift one virtual",
            trips.count == 3 && LBIs(trips[0].mileageQuantity, @"0") && LBIs(trips[0].distanceQuantity, @"10")
                && LBIs(trips[1].mileageQuantity, @"10") && LBIs(trips[1].distanceQuantity, @"30") && LBIs(trips[2].mileageQuantity, @"30")
                && LBIs(trips[2].distanceQuantity, @"45") && trips[2].isVirtual && LBIs(trips[2].lengthQuantity, @"15")
                && [trips[0].note containsString:@"(commute)"] && [trips[0].moment timeIntervalSinceDate:trips[0].timestamp] == 1800,
            [trips valueForKey:@"distanceQuantity"]);
    Catalog *catalog = nil;
    for (Catalog *each in anna.ownedCatalogs) if ([each.catalogName isEqualToString:@"Bike parts"]) catalog = each;
    NSMutableDictionary<NSString *, StockItem *> *items = [NSMutableDictionary dictionary];
    for (StockItem *each in catalog.stockItems) items[each.itemName] = each;
    StockItem *wheels = items[@"Shimano WH-R500"], *tyres = items[@"Panaracer GravelKing+ 700x32C"];
    LBCheck(@"its parts items of 'Bike parts', made: 6, the two tyres one item of two units; the WH-R500 a Wheel Set by Shimano, 3581",
            catalog && items.count == 6 && tyres.stockUnits.count == 2 && [wheels.category.categoryName isEqualToString:@"Wheel Set"]
                && [wheels.manufacturer isEqualToString:@"Shimano"] && [wheels.mpn isEqualToString:@"WH-R500"] && LBIs(wheels.unitCostAmount, @"3581")
                && items[@"Spare saddle"].stockUnits.count == 1 && !items[@"Spare saddle"].stockUnits.anyObject.location,
            items.allKeys);
    StockUnit *wheel = wheels.stockUnits.anyObject, *mavic = items[@"Mavic 27\""].stockUnits.anyObject;
    ComponentChange *fit = wheel.componentChanges.anyObject;
    LBCheck(@"the WH-R500 fitted on 2020-03-13 at 10 km, removing the Mavic set; the tyres fitted into it",
            fit && LBIs(fit.mileageQuantity, @"10") && fit.removedStockUnit == mavic && fit.vehicle == commuter && wheel.componentChangesAsHost.count == 2,
            fit.removedStockUnit.stockItem.itemName);
    DistanceUnit *km = [[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"DistanceUnit"] error:NULL]
        filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"code == 'km'"]].firstObject;
    LBCheck(@"its wear: 35 km (to 45, where the Zwift ride ended)", [[wheel lb_wornIn:km] isEqualToNumber:@35] && [wheel lb_fittedTo] == commuter,
            [wheel lb_wornIn:km]);
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
    LBCheck(@"imported again: nothing made, the 27 passed over", done && madeCount == 0 && skipped == 27 && anna.ownedVehicles.count == 2
                && catalog.stockItems.count == 6,
            error ?: [NSString stringWithFormat:@"%lu made, %lu passed over", (unsigned long)madeCount, (unsigned long)skipped]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

/* InvenTree's API, answered from a folder of its answers (Tests/inventree,
   made up: each endpoint's JSON, part/category as part_category.json). */
static NSData *LBInvenTreeAnswer(NSString *folder, NSString *path) {
    NSString *endpoint = [path componentsSeparatedByString:@"/?"].firstObject;
    NSString *file = [[endpoint stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByAppendingPathExtension:@"json"];
    /* One page, all of it: a second page's offset answers none. */
    if (![path containsString:@"offset=0"]) return [@"{\"count\":0,\"results\":[]}" dataUsingEncoding:NSUTF8StringEncoding];
    return [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:file]] ?: [@"[]" dataUsingEncoding:NSUTF8StringEncoding];
}

static NSArray *LBInvenTreeRows(NSString *folder, NSString *file) {
    NSData *data = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:file]];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL][@"results"] : @[];
}

static LBImport *LBInvenTree(NSString *folder, NSError **error) {
    LBImport *import = [LBImport importOfInvenTree:[NSURL URLWithString:@"https://inventree.example.org/"] token:@"none"
                                              fetch:^NSData *(NSString *path, NSError **failure) { return LBInvenTreeAnswer(folder, path); }
                                              error:error];
    import.catalogName = @"Home";
    return import;
}

static PurchaseOrder *LBOrderMarked(Catalog *catalog, NSString *reference) {
    for (PurchaseOrder *each in catalog.purchaseOrders) if ([each.note hasPrefix:[@"InvenTree " stringByAppendingString:reference]]) return each;
    return nil;
}

/* Into a catalog of the user's, Home: with the fixtures (made == 28), each
   thing as InvenTree has it; with any folder, each order line of the item
   InvenTree's line names (its supplier part's part, never the part of
   that number); imported again, nothing made. */
static void LBInvenTreeSteps(NSString *folder, NSUInteger expected) {
    NSManagedObjectContext *context = LBNewStore();
    User *anna = LBUser(@"anna@example.org", @"Anna Driver", context);
    anna.currency = @"USD";
    NSError *error = nil;
    if (![context orm_prepareForSave:&error] || ![context save:&error]) {
        LBCheck(@"the user saved", NO, error);
        return;
    }
    /* As a device saves: the procedures, then holdings, then the rules. */
    LBImportSaving saving = ^BOOL(NSManagedObjectContext *c, NSError **failure) {
        return [c lb_completeRemindersOfChangedEvents:failure] && [c lb_holdMovedItems:failure] && [c orm_prepareForSave:failure] && [c save:failure];
    };
    LBImport *import = LBInvenTree(folder, &error);
    LBCheck(@"InvenTree read, its answers from the folder", import && [import.source isEqualToString:@"InvenTree"] && import.makesStock,
            error ?: folder);
    import.catalogName = nil;
    LBCheck(@"no catalog named: refused, said", ![import planForVehicle:nil by:anna error:&error] && [error.localizedDescription containsString:@"catalog"],
            error);
    import.catalogName = @"Home";
    NSUInteger made = 0, skipped = 0;
    error = nil;
    BOOL done = [import importIntoVehicle:nil by:anna context:context saving:saving made:&made skipped:&skipped error:&error];
    LBCheck(@"imported into Home", done && made > 0 && (!expected || made == expected),
            error ?: [NSString stringWithFormat:@"%lu made, %lu expected", (unsigned long)made, (unsigned long)expected]);
    Catalog *home = nil;
    for (Catalog *each in anna.ownedCatalogs) if ([each.catalogName isEqualToString:@"Home"]) home = each;

    /* Each line of the item InvenTree's line is of. */
    NSMutableDictionary *partOfOffer = [NSMutableDictionary dictionary], *nameOfPart = [NSMutableDictionary dictionary],
                        *referenceOf = [NSMutableDictionary dictionary];
    for (NSDictionary *row in LBInvenTreeRows(folder, @"company_part.json")) partOfOffer[row[@"pk"]] = row[@"part"];
    for (NSDictionary *row in LBInvenTreeRows(folder, @"part.json")) nameOfPart[row[@"pk"]] = row[@"name"];
    for (NSDictionary *row in LBInvenTreeRows(folder, @"order_po.json")) referenceOf[row[@"pk"]] = row[@"reference"];
    NSMutableArray *wrong = [NSMutableArray array];
    for (NSDictionary *line in LBInvenTreeRows(folder, @"order_po-line.json")) {
        id part = line[@"internal_part"] != [NSNull null] ? line[@"internal_part"] : partOfOffer[line[@"part"]];
        PurchaseOrder *order = LBOrderMarked(home, referenceOf[line[@"order"]]);
        if (!order) continue;
        if (![[order.purchaseLines valueForKeyPath:@"stockItem.itemName"] containsObject:nameOfPart[part]])
            [wrong addObject:[NSString stringWithFormat:@"%@: no line of %@ (%@)", referenceOf[line[@"order"]], nameOfPart[part],
                                                        [[order.purchaseLines valueForKeyPath:@"stockItem.itemName"] allObjects]]];
    }
    LBCheck(@"each order line of the item InvenTree's supplier part is of", wrong.count == 0, wrong);

    if (expected) {
        NSMutableDictionary *items = [NSMutableDictionary dictionary];
        for (StockItem *each in home.stockItems) items[each.itemName] = each;
        StockItem *router = items[@"Router X1"], *pc = items[@"Mini PC N100"], *cable = items[@"USB-C cable 1m"];
        LBCheck(@"its parts items: the IPN the SKU, the manufacturer part's maker and MPN, the category within its parent",
                home.stockItems.count == 3 && [router.sku isEqualToString:@"RX1"] && [router.manufacturer isEqualToString:@"Acme Networks"]
                    && [router.mpn isEqualToString:@"AX1-EU"] && [cable.category.categoryName isEqualToString:@"Cables"]
                    && [cable.category.parent.categoryName isEqualToString:@"Computers"] && [pc.note containsString:@"For the office"],
                [home.stockItems valueForKey:@"itemName"]);
        SupplierItem *pack = cable.supplierItems.anyObject;
        LBCheck(@"its supplier parts: both of one supplier's, its pack", [[home.suppliers valueForKeyPath:@"contact.contactName"] isEqual:
                                                                          [NSSet setWithObjects:@"Parts Shop", @"Big Market", nil]]
                    && pc.supplierItems.count == 1 && pc.supplierItems.anyObject.supplier == pack.supplier
                    && [pack.supplierSKU isEqualToString:@"PS-USBC1"] && [pack.packSize isEqual:@3],
                [home.suppliers valueForKeyPath:@"contact.contactName"]);
        LBCheck(@"its top locations warehouses (beside the catalog's own Main), the rest within them",
                [[home.warehouses valueForKey:@"warehouseName"] isEqual:[NSSet setWithObjects:@"Main", @"Home", @"Garage", nil]],
                [home.warehouses valueForKey:@"warehouseName"]);
        PurchaseOrder *first = LBOrderMarked(home, @"PO-0001"), *second = LBOrderMarked(home, @"PO-0002");
        PurchaseLine *cables = nil;
        for (PurchaseLine *each in first.purchaseLines) if (each.stockItem == cable) cables = each;
        LBCheck(@"its orders: Complete closed, Placed confirmed; a line of no price at what its stock cost",
                [first.orderState isEqualToString:@"Closed"] && [second.orderState isEqualToString:@"Confirmed"]
                    && [first.supplierReference isEqualToString:@"PS-88412"] && first.purchaseLines.count == 2
                    && [cables.quantity isEqual:@3] && [cables.lineUnitCostAmount isEqual:@4] && first.receipts.count == 1
                    && second.receipts.count == 0,
                [NSString stringWithFormat:@"%@ %@ %@ %@", first.orderState, second.orderState, cables.quantity, cables.lineUnitCostAmount]);
        NSMutableDictionary<NSString *, Location *> *places = [NSMutableDictionary dictionary];
        for (Warehouse *each in home.warehouses)
            for (Location *location in each.locations) places[location.locationName] = location;
        NSMutableDictionary *where = [NSMutableDictionary dictionary];
        for (StockItem *item in home.stockItems)
            for (StockUnit *unit in item.stockUnits) where[unit.serialNumber] = unit.location.locationName ?: @"(nowhere)";
        LBCheck(@"its stock where InvenTree has it: received, then moved; bought outside an order, at its price (a unit, so many)",
                [where isEqual:(@{ @"N100-0001": @"Drawer", @"RX-77": @"Garage" })]
                    && [router.stockUnits.anyObject.note containsString:@"Bought for 60 USD"]
                    && [[cable.moves valueForKey:@"note"] containsObject:@"InvenTree stock item 4\nBought for 2.5 USD"]
                    && [[places[@"Office"] lb_heldOf:cable] isEqual:@3] && [[places[@"Garage"] lb_heldOf:cable] isEqual:@5],
                @[ where, router.stockUnits.anyObject.note ?: @"(no note)", [cable.moves valueForKey:@"note"] ]);
    }

    NSUInteger first = made;
    import = LBInvenTree(folder, &error);
    done = [import importIntoVehicle:nil by:anna context:context saving:saving made:&made skipped:&skipped error:&error];
    LBCheck(@"imported again: nothing made", done && made == 0 && skipped > 0,
            error ?: [NSString stringWithFormat:@"%lu made, %lu passed over (%lu the first time)", (unsigned long)made, (unsigned long)skipped,
                                                (unsigned long)first]);
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
        LBDrivvoMatchSteps(export);
        if (argc > 5) LBMainTrackSteps(@(argv[5]));
        if (argc > 6) LBInvenTreeSteps(@(argv[6]), argc > 7 ? (NSUInteger)atol(argv[7]) : 0);
        printf("import: %lu failed\n", (unsigned long)LBFailures);
    }
    return LBFailures ? 1 : 0;
}
