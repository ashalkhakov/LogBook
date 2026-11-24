#import "LBImport.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>
#include <sqlite3.h>
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "VehicleDriver+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "Event+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"
#import "StockUnit+CoreDataClass.h"
#import "StockItem+CoreDataClass.h"
#import "Catalog+CoreDataClass.h"
#import "Category+CoreDataClass.h"
#import "LBStockProcedures.h"
#import "Trip+CoreDataClass.h"
#import "ComponentChange+CoreDataClass.h"

NSErrorDomain const LBImportErrorDomain = @"LBImportErrorDomain";

static NSError *LBImportError(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static NSError *LBImportError(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *said = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    return [NSError errorWithDomain:LBImportErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey : said }];
}

/* What a save refused, each rule broken said: Core Data's "Multiple
   validation errors occurred" opened into its errors, each the value
   (key) of what (entity) and why. */
static NSString *LBRefusal(NSError *failure) {
    NSMutableArray *said = [NSMutableArray array];
    id details = failure.userInfo[NSDetailedErrorsKey];
    NSArray *each = [details isKindOfClass:[NSArray class]] ? details : (failure ? @[ failure ] : @[]);
    for (id entry in each) {
        /* An error, as Apple's are; what else a store gives, said as it is. */
        if (![entry isKindOfClass:[NSError class]]) {
            [said addObject:[entry description] ?: @"refused"];
            continue;
        }
        NSError *e = entry;
        /* The object, where it is one (FreeCoreData's may give its id). */
        id given = e.userInfo[NSValidationObjectErrorKey];
        NSManagedObject *object = [given isKindOfClass:[NSManagedObject class]] ? given : nil;
        id named = e.userInfo[NSValidationKeyErrorKey];
        NSString *key = [named isKindOfClass:[NSString class]] ? named : nil;
        id described = e.localizedDescription;
        NSString *why = [described isKindOfClass:[NSString class]] ? described : [described description] ?: @"refused";
        /* A store that gives no words, only the code (FreeCoreData's): the
           words Core Data's codes mean. */
        if (!why.length || [why rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
            NSDictionary *meant = @{ @(NSManagedObjectValidationError) : @"is not a value it may have",
                                     @(NSValidationMissingMandatoryPropertyError) : @"is required",
                                     @(NSValidationNumberTooLargeError) : @"is too large", @(NSValidationNumberTooSmallError) : @"is too small",
                                     @(NSValidationDateTooLateError) : @"is too late", @(NSValidationDateTooSoonError) : @"is too soon",
                                     @(NSValidationStringTooLongError) : @"is too long", @(NSValidationStringTooShortError) : @"is too short",
                                     @(NSValidationStringPatternMatchingError) : @"is not of its pattern",
                                     @(NSValidationInvalidDateError) : @"is no date" };
            why = meant[@(e.code)] ?: [NSString stringWithFormat:@"refused (%ld)", (long)e.code];
        }
        /* Apple's own words keep the property's place unfilled. */
        if (key) why = [why stringByReplacingOccurrencesOfString:@"%{PROPERTY}@" withString:key];
        if (object || key)
            [said addObject:[NSString stringWithFormat:@"%@%@%@: %@", object.entity.name ?: @"", key ? @" " : @"", key ?: @"", why]];
        else
            [said addObject:why];
    }
    return [said componentsJoinedByString:@"; "];
}

#pragma mark CSV

NSArray<NSArray<NSString *> *> *LBCSVRows(NSString *text) {
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray *row = [NSMutableArray array];
    NSMutableString *field = [NSMutableString string];
    BOOL quoted = NO, began = NO;
    NSUInteger length = text.length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [text characterAtIndex:i];
        if (quoted) {
            if (c == '"') {
                if (i + 1 < length && [text characterAtIndex:i + 1] == '"') {
                    [field appendString:@"\""];
                    i++;
                } else {
                    quoted = NO;
                }
            } else {
                [field appendFormat:@"%C", c];
            }
            continue;
        }
        if (c == '"') {
            quoted = YES;
            began = YES;
        } else if (c == ',') {
            [row addObject:[field copy]];
            [field setString:@""];
            began = YES;
        } else if (c == '\n' || c == '\r') {
            if (c == '\r' && i + 1 < length && [text characterAtIndex:i + 1] == '\n') i++;
            if (began || field.length) [row addObject:[field copy]];
            [rows addObject:[row copy]];
            [row removeAllObjects];
            [field setString:@""];
            began = NO;
        } else {
            [field appendFormat:@"%C", c];
            began = YES;
        }
    }
    if (began || field.length || row.count) {
        [row addObject:[field copy]];
        [rows addObject:[row copy]];
    }
    return rows;
}

#pragma mark Drivvo's export

/* A section of the export: its header, and its rows as dictionaries by
   column (a column named twice, Drivvo's "Price / L" of each fuel, by its
   name and its place: "Price / L#2"). */
@interface LBSection : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *columns;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSString *> *> *rows;
@end

@implementation LBSection
@end

static NSDecimalNumber *LBNumber(NSString *text) {
    if (!text.length) return nil;
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:text locale:@{ NSLocaleDecimalSeparator : @"." }];
    return number == [NSDecimalNumber notANumber] ? nil : number;
}

static BOOL LBIsZero(NSString *text) {
    NSDecimalNumber *number = LBNumber(text);
    return !text.length || (number && [number compare:[NSDecimalNumber zero]] == NSOrderedSame);
}

/* What a header's parenthesised or slashed unit says, as Logbook codes
   it: "Odometer (km)" km, "Price / L" L. */
static NSString *LBUnitIn(NSString *column) {
    NSString *unit = nil;
    NSRange open = [column rangeOfString:@"("], close = [column rangeOfString:@")" options:NSBackwardsSearch];
    if (open.location != NSNotFound && close.location != NSNotFound && close.location > open.location) {
        unit = [column substringWithRange:NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))];
    } else {
        NSRange slash = [column rangeOfString:@"/" options:NSBackwardsSearch];
        if (slash.location != NSNotFound) unit = [column substringFromIndex:NSMaxRange(slash)];
    }
    unit = [unit stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSDictionary *codes = @{ @"km" : @"km", @"mi" : @"mi", @"L" : @"L", @"l" : @"L", @"gal" : @"gal (US)", @"US gal" : @"gal (US)",
                             @"UK gal" : @"gal (imp)", @"Imp gal" : @"gal (imp)" };
    return unit ? codes[unit] : nil;
}

@interface LBImport ()
@property (nonatomic, readwrite, copy) NSString *source;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *vehicleNames;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *counts;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *leftOut;
@end

/* A record to enter: its form, its values, its repeat's rows, and how the
   user would know it ("Refuelling 3, 2022-05-31 13:14"). */
@interface LBEntry : NSObject
@property (nonatomic, copy) NSString *form;
@property (nonatomic, copy) NSString *what;
@property (nonatomic, strong) NSDate *moment;
@property (nonatomic, strong) NSDecimalNumber *mileage;
@property (nonatomic, assign) Class kind;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *values;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray *> *repeats;
/* MainTrack's: the bike it is of (else the vehicle imported into); the
   elements that are a part's unit (element: the part's pk), keyed as the
   units are made. */
@property (nonatomic, strong) NSNumber *bike;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *refers;
@end

/* A bike of MainTrack's, made a vehicle of Logbook's (there is no form of
   a vehicle: it is made as the vehicle's tab makes one). */
@interface LBBike : NSObject
@property (nonatomic, strong) NSNumber *pk;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *make;
@property (nonatomic, copy) NSString *model;
@property (nonatomic) int32_t year;
@property (nonatomic, strong) NSDate *bought;
@property (nonatomic, strong) NSDecimalNumber *price;
@property (nonatomic, strong) NSDecimalNumber *odometer;
@end

@implementation LBEntry
@end

@implementation LBBike
@end

/* A component of MainTrack's, made a unit of an item of the catalog's. */
@interface LBPart : NSObject
@property (nonatomic, strong) NSNumber *pk;
@property (nonatomic, copy) NSString *item, *category, *manufacturer, *model, *serial, *note;
@property (nonatomic, strong) NSDecimalNumber *cost;
@property (nonatomic, strong) NSDate *bought;
@end

@implementation LBPart
@end

@implementation LBImport {
    NSDictionary<NSString *, LBSection *> *_sections;
    NSArray<LBEntry *> *_entries;
    /* MainTrack's tables, read whole: by table, its rows (column: value). */
    NSDictionary<NSString *, NSArray<NSDictionary *> *> *_tables;
    NSDictionary<NSString *, NSNumber *> *_entities;
    NSArray<LBBike *> *_bikes;
    NSArray<LBPart *> *_parts;
}

static BOOL LBIsSQLite(NSData *data) {
    return data.length >= 16 && memcmp(data.bytes, "SQLite format 3", 16) == 0;
}

+ (instancetype)importOfFile:(NSURL *)file error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:error];
    if (!data) return nil;
    if (LBIsSQLite(data)) {
        LBImport *import = [[self alloc] init];
        import.source = @"MainTrack";
        return [import readMainTrack:file.path error:error] ? import : nil;
    }
    return [self importOfData:data named:file.lastPathComponent error:error];
}

+ (instancetype)importOfData:(NSData *)data named:(NSString *)name error:(NSError **)error {
    /* A store (MainTrack's) is read from a file: this one's, a copy. */
    if (LBIsSQLite(data)) {
        NSString *copy = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                     [NSString stringWithFormat:@"lb-import-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
        if (![data writeToFile:copy options:NSDataWritingAtomic error:error]) return nil;
        LBImport *import = [[self alloc] init];
        import.source = @"MainTrack";
        BOOL read = [import readMainTrack:copy error:error];
        [[NSFileManager defaultManager] removeItemAtPath:copy error:NULL];
        return read ? import : nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([text hasPrefix:@"﻿"]) text = [text substringFromIndex:1];
    if (!text || ![text hasPrefix:@"##"]) {
        if (error) *error = LBImportError(@"%@ is no export Logbook reads: Drivvo's CSV export begins with a section, ##Vehicle.", name);
        return nil;
    }
    LBImport *import = [[self alloc] init];
    import.source = @"Drivvo";
    if (![import readDrivvo:text named:name error:error]) return nil;
    return import;
}

- (BOOL)readDrivvo:(NSString *)text named:(NSString *)name error:(NSError **)error {
    NSMutableDictionary<NSString *, LBSection *> *sections = [NSMutableDictionary dictionary];
    LBSection *section = nil;
    for (NSArray<NSString *> *row in LBCSVRows(text)) {
        BOOL blank = YES;
        for (NSString *field in row) blank = blank && field.length == 0;
        if (blank) continue;
        if (row.count == 1 && [row[0] hasPrefix:@"##"]) {
            section = [[LBSection alloc] init];
            section.name = [row[0] substringFromIndex:2];
            section.rows = [NSMutableArray array];
            sections[section.name] = section;
            continue;
        }
        if (!section) continue;
        if (!section.columns) {
            NSMutableArray *columns = [NSMutableArray array];
            NSCountedSet *seen = [NSCountedSet set];
            for (NSString *column in row) {
                [seen addObject:column];
                NSUInteger times = [seen countForObject:column];
                [columns addObject:times > 1 ? [NSString stringWithFormat:@"%@#%lu", column, (unsigned long)times] : column];
            }
            section.columns = columns;
            continue;
        }
        if (row.count != section.columns.count) {
            if (error) *error = LBImportError(@"%@: a row of ##%@ has %lu fields, its header %lu.", name, section.name,
                                              (unsigned long)row.count, (unsigned long)section.columns.count);
            return NO;
        }
        [section.rows addObject:[NSDictionary dictionaryWithObjects:row forKeys:section.columns]];
    }
    /* Sections not read yet: refused, not passed over. */
    NSMutableArray *unread = [NSMutableArray array];
    for (LBSection *each in sections.allValues) {
        if (each.rows.count && ![@[ @"Vehicle", @"Refuelling", @"Service" ] containsObject:each.name]) [unread addObject:each.name];
    }
    if (unread.count) {
        if (error) *error = LBImportError(@"%@ has %@, which Logbook does not import from Drivvo yet.", name,
                                          [[unread sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]);
        return NO;
    }
    _sections = sections;
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *vehicle in sections[@"Vehicle"].rows) {
        NSString *named = vehicle[@"Name"].length ? vehicle[@"Name"] : vehicle[@"Model"];
        if (named.length) [names addObject:named];
    }
    self.vehicleNames = names;
    NSMutableSet *services = [NSMutableSet set];
    for (NSDictionary<NSString *, NSString *> *row in sections[@"Service"].rows) [services addObject:@[ row[@"Date"] ?: @"", row[@"Odometer (km)"] ?: row[@"Odometer (mi)"] ?: @"" ]];
    self.counts = @{ @"fill-ups" : @(sections[@"Refuelling"].rows.count), @"services" : @(services.count) };
    self.leftOut = @[];
    return YES;
}

- (NSString *)summary {
    NSMutableArray *said = [NSMutableArray array];
    for (NSString *kind in [_counts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSUInteger n = _counts[kind].unsignedIntegerValue;
        /* "fill-ups" said of one: "fill-up". */
        [said addObject:[NSString stringWithFormat:@"%lu %@", (unsigned long)n, n == 1 ? [kind substringToIndex:kind.length - 1] : kind]];
    }
    return [said componentsJoinedByString:@", "];
}

- (ORMForm *)form:(NSString *)name error:(NSError **)error {
    return _formNamed ? _formNamed(name, error) : [ORMForm formNamed:name error:error];
}

/* Who drove, by the name Drivvo has: no one named, the user entering it;
   else the one of those who drive the vehicle of that name. */
- (User *)driverNamed:(NSString *)name ofVehicle:(Vehicle *)vehicle user:(User *)user {
    if (!name.length || [name isEqualToString:user.personName]) return user;
    NSMutableArray<User *> *drivers = [NSMutableArray arrayWithObject:vehicle.owner ?: user];
    for (VehicleDriver *each in vehicle.vehicleDrivers) if (each.user) [drivers addObject:each.user];
    for (User *driver in drivers) {
        if ([driver.personName isEqualToString:name]) return driver;
    }
    return nil;
}

- (BOOL)planForVehicle:(Vehicle *)vehicle by:(User *)user error:(NSError **)error {
    if (self.makesVehicles) return [self planMainTrackBy:user error:error];
    if (!vehicle) {
        if (error) *error = LBImportError(@"%@'s export goes into a vehicle already set up: choose it first.", _source);
        return NO;
    }
    NSMutableArray *leftOut = [NSMutableArray array];
    NSMutableArray<LBEntry *> *entries = [NSMutableArray array];
    NSString *currency = user.currency;
    if (!currency.length) {
        if (error) *error = LBImportError(@"Drivvo's export says no currency: say yours in Preferences first, and it is taken as the export's.");
        return NO;
    }
    NSTimeZone *zone = user.timeZone.length ? [NSTimeZone timeZoneWithName:user.timeZone] : [NSTimeZone localTimeZone];
    NSDateFormatter *read = [[NSDateFormatter alloc] init];
    read.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    read.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    read.timeZone = zone ?: [NSTimeZone localTimeZone];
    NSISO8601DateFormatter *write = [[NSISO8601DateFormatter alloc] init];

    /* The vehicle as Drivvo has it: what it says that the vehicle does
       not, left out (the import goes into a vehicle already set up). */
    for (NSDictionary<NSString *, NSString *> *row in _sections[@"Vehicle"].rows) {
        NSString *named = row[@"Name"].length ? row[@"Name"] : row[@"Model"];
        NSString *plate = row[@"License plate"];
        if (plate.length && ![plate isEqualToString:vehicle.registrationNumber ?: @""])
            [leftOut addObject:[NSString stringWithFormat:@"Vehicle %@: its licence plate '%@'", named, plate]];
        NSInteger year = row[@"Year"].integerValue;
        if (year > 0 && year != vehicle.manufactureYear)
            [leftOut addObject:[NSString stringWithFormat:@"Vehicle %@: its year %ld", named, (long)year]];
        for (NSString *column in row) {
            if ([column hasPrefix:@"Fuel capacity"] && !LBIsZero(row[column]))
                [leftOut addObject:[NSString stringWithFormat:@"Vehicle %@: its fuel capacity %@ (Logbook keeps no tank size)", named, row[column]]];
        }
        if (!LBIsZero(row[@"Purchase price"]))
            [leftOut addObject:[NSString stringWithFormat:@"Vehicle %@: its purchase price %@ (say it in the vehicle's Purchase)", named, row[@"Purchase price"]]];
        if (!LBIsZero(row[@"Sale price"]))
            [leftOut addObject:[NSString stringWithFormat:@"Vehicle %@: its sale price %@ (record the sale as an income)", named, row[@"Sale price"]]];
        if (row[@"Notes"].length) [leftOut addObject:[NSString stringWithFormat:@"Vehicle %@: its notes '%@'", named, row[@"Notes"]]];
    }

    /* Fill-ups. */
    LBSection *fills = _sections[@"Refuelling"];
    NSString *distance = nil, *volume = nil;
    for (NSString *column in fills.columns) {
        if ([column hasPrefix:@"Odometer"]) distance = column;
        if ([column hasPrefix:@"Price /"] && ![column containsString:@"#"]) volume = column;
    }
    NSSet *fuels = [NSSet setWithArray:[fills.rows valueForKey:@"Fuel"] ?: @[]];
    /* One fuel in the export, and the vehicle uses another by name
       (Drivvo's "Gasoline", Logbook's "Petrol"): the vehicle's. */
    NSString *asFuel = nil;
    if (fuels.count == 1 && vehicle.fuel.length && ![fuels.anyObject isEqualToString:vehicle.fuel]) {
        asFuel = vehicle.fuel;
        [leftOut addObject:[NSString stringWithFormat:@"Refuelling: its fuel '%@' entered as the vehicle's, '%@'", fuels.anyObject, vehicle.fuel]];
    }
    NSUInteger number = 0;
    for (NSDictionary<NSString *, NSString *> *row in fills.rows) {
        number++;
        NSString *what = [NSString stringWithFormat:@"Refuelling %lu (%@)", (unsigned long)number, row[@"Date"]];
        NSString *distanceUnit = LBUnitIn(distance ?: @""), *volumeUnit = LBUnitIn(volume ?: @"");
        if (!distanceUnit || !volumeUnit) {
            if (error) *error = LBImportError(@"%@: its units (%@, %@) are none Logbook has (km, mi; L, gal).", what, distance, volume);
            return NO;
        }
        NSDate *moment = [read dateFromString:row[@"Date"]];
        if (!moment) {
            if (error) *error = LBImportError(@"%@: its date is none Drivvo writes.", what);
            return NO;
        }
        User *driver = [self driverNamed:row[@"Driver"] ofVehicle:vehicle user:user];
        if (!driver) {
            if (error) *error = LBImportError(@"%@: its driver %@ is no one who drives %@ in Logbook: share the vehicle with them first.",
                                              what, row[@"Driver"], vehicle.vehicleName);
            return NO;
        }
        NSMutableDictionary *values = [@{ @"timestamp" : [write stringFromDate:moment], @"mileageQuantity" : row[distance] ?: @"",
                                          @"mileageDistanceUnit" : distanceUnit, @"volumeQuantity" : row[@"Volume"] ?: @"",
                                          @"volumeVolumeUnit" : volumeUnit, @"fuel" : asFuel ?: row[@"Fuel"] ?: @"",
                                          @"totalAmount" : row[@"Total cost"] ?: @"", @"totalCurrency" : currency,
                                          @"driver" : driver.email ?: @"",
                                          @"filledTheTank" : [row[@"Filled tank completely"] isEqualToString:@"Yes"] ? @"true" : @"false" } mutableCopy];
        if (row[@"Petrol station"].length) values[@"station"] = row[@"Petrol station"];
        if (row[@"Notes"].length) values[@"note"] = row[@"Notes"];
        /* What a fill-up of Logbook's has no place for. */
        for (NSString *extra in @[ @"Second fuel", @"Third fuel", @"Charging type", @"Battery start (%)", @"Battery end (%)",
                                   @"Duration (min)", @"Payment method", @"Reason" ]) {
            if (row[extra].length) [leftOut addObject:[NSString stringWithFormat:@"%@: its %@ '%@'", what, extra.lowercaseString, row[extra]]];
        }
        if (!LBIsZero(row[@"Discount"])) [leftOut addObject:[NSString stringWithFormat:@"%@: its discount %@", what, row[@"Discount"]]];
        /* Its price per unit Logbook works out; one Drivvo says otherwise
           (by more than a unit of its last place) is said. */
        NSDecimalNumber *price = LBNumber(row[volume]), *total = LBNumber(row[@"Total cost"]), *litres = LBNumber(row[@"Volume"]);
        if (price && total && litres.doubleValue > 0 && fabs(total.doubleValue / litres.doubleValue - price.doubleValue) > 0.01 * price.doubleValue)
            [leftOut addObject:[NSString stringWithFormat:@"%@: its price %@ per %@ (Logbook works it out from the cost and the volume: %.2f)",
                                                         what, row[volume], volumeUnit, total.doubleValue / litres.doubleValue]];
        LBEntry *entry = [[LBEntry alloc] init];
        entry.form = @"RecordFillUp";
        entry.what = what;
        entry.kind = [FillUp class];
        entry.moment = moment;
        entry.mileage = LBNumber(row[distance]);
        entry.values = values;
        [entries addObject:entry];
    }

    /* Services: the rows of one date and reading, one service; each row a
       task of it, its cost. */
    LBSection *services = _sections[@"Service"];
    NSString *serviceDistance = nil;
    for (NSString *column in services.columns) if ([column hasPrefix:@"Odometer"]) serviceDistance = column;
    NSMutableArray *groups = [NSMutableArray array];
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, NSString *> *row in services.rows) {
        NSArray *key = @[ row[@"Date"] ?: @"", row[serviceDistance] ?: @"" ];
        NSMutableArray *group = byKey[key];
        if (!group) {
            group = byKey[key] = [NSMutableArray array];
            [groups addObject:group];
        }
        [group addObject:row];
    }
    /* Drivvo says no service's kind: Logbook's are Maintenance and Repair. */
    if (groups.count) [leftOut addObject:@"Service: Drivvo says no kind of service; each entered as Maintenance"];
    number = 0;
    for (NSArray<NSDictionary<NSString *, NSString *> *> *group in groups) {
        number++;
        NSDictionary<NSString *, NSString *> *first = group.firstObject;
        NSString *what = [NSString stringWithFormat:@"Service %lu (%@)", (unsigned long)number, first[@"Date"]];
        NSString *distanceUnit = LBUnitIn(serviceDistance ?: @"");
        NSDate *moment = [read dateFromString:first[@"Date"]];
        if (!distanceUnit || !moment) {
            if (error) *error = LBImportError(@"%@: its %@ is none Logbook reads.", what, distanceUnit ? @"date" : @"distance's unit");
            return NO;
        }
        /* What its rows say as one: the same of each, else said. */
        NSString * (^common)(NSString *) = ^NSString *(NSString *column) {
            NSSet *said = [NSSet setWithArray:[group valueForKey:column] ?: @[]];
            return said.count == 1 ? said.anyObject : nil;
        };
        for (NSString *column in @[ @"Service location", @"Driver", @"Payment method", @"Title", @"Instalments", @"First instalment" ]) {
            if (!common(column))
                [leftOut addObject:[NSString stringWithFormat:@"%@: its tasks' %@s differ; the first's, '%@', taken",
                                                             what, column.lowercaseString, first[column]]];
        }
        User *driver = [self driverNamed:first[@"Driver"] ofVehicle:vehicle user:user];
        if (!driver) {
            if (error) *error = LBImportError(@"%@: its driver %@ is no one who drives %@ in Logbook: share the vehicle with them first.",
                                              what, first[@"Driver"], vehicle.vehicleName);
            return NO;
        }
        NSMutableDictionary *values = [@{ @"timestamp" : [write stringFromDate:moment], @"mileageQuantity" : first[serviceDistance] ?: @"",
                                          @"mileageDistanceUnit" : distanceUnit, @"driver" : driver.email ?: @"",
                                          @"currency" : currency, @"serviceKind" : @"Maintenance" } mutableCopy];
        if (first[@"Title"].length) values[@"title"] = first[@"Title"];
        if (first[@"Service location"].length) values[@"garage"] = first[@"Service location"];
        if (first[@"Payment method"].length) values[@"paymentMethod"] = first[@"Payment method"];
        if (first[@"Instalments"].integerValue > 1) values[@"instalments"] = first[@"Instalments"];
        if (first[@"First instalment"].length)
            [leftOut addObject:[NSString stringWithFormat:@"%@: its first instalment's date '%@'", what, first[@"First instalment"]]];
        /* Drivvo's discount is the service's: of each row, summed. */
        NSDecimalNumber *discount = [NSDecimalNumber zero];
        for (NSDictionary *row in group) discount = [discount decimalNumberByAdding:LBNumber(row[@"Discount"]) ?: [NSDecimalNumber zero]];
        if ([discount compare:[NSDecimalNumber zero]] == NSOrderedDescending) {
            values[@"moneyAmount"] = discount.stringValue;
            values[@"moneyCurrency"] = currency;
        }
        NSString *note = common(@"Notes");
        if (note.length) values[@"note"] = note;
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary<NSString *, NSString *> *row in group) {
            NSMutableDictionary *item = [@{ @"task" : row[@"Type of service"] ?: @"", @"costAmount" : row[@"Total cost"] ?: @"",
                                            @"costCurrency" : currency } mutableCopy];
            if (!note && row[@"Notes"].length) item[@"note"] = row[@"Notes"];
            [items addObject:item];
        }
        LBEntry *entry = [[LBEntry alloc] init];
        entry.form = @"RecordService";
        entry.what = what;
        entry.kind = [Service class];
        entry.moment = moment;
        entry.mileage = LBNumber(first[serviceDistance]);
        entry.values = values;
        entry.repeats = @{ @"serviceItems" : items };
        [entries addObject:entry];
    }
    [entries sortUsingComparator:^NSComparisonResult(LBEntry *a, LBEntry *b) { return [a.moment compare:b.moment]; }];
    _entries = entries;
    self.leftOut = leftOut;
    return YES;
}

/* The vehicle has it already: a record of its kind at that moment (to the
   second) and reading. */
- (BOOL)vehicle:(Vehicle *)vehicle has:(LBEntry *)entry {
    return [self vehicle:vehicle has:entry fitting:nil];
}

/* The same, of a component change: one that fits that component (two fitted
   at once, chainrings, are two). */
- (BOOL)vehicle:(Vehicle *)vehicle has:(LBEntry *)entry fitting:(NSString *)component {
    for (Record *record in vehicle.records) {
        if (![record isKindOfClass:entry.kind] || record.isDeleted) continue;
        if (component && [record isKindOfClass:[ComponentChange class]]
            && ![((ComponentChange *)record).stockUnit.id.UUIDString isEqualToString:component]) continue;
        Event *event = (Event *)record;
        if (fabs(event.timestamp.timeIntervalSinceReferenceDate - entry.moment.timeIntervalSinceReferenceDate) < 1
            && (!entry.mileage || [event.mileageQuantity compare:entry.mileage] == NSOrderedSame)) return YES;
    }
    return NO;
}

- (BOOL)importIntoVehicle:(Vehicle *)vehicle
                       by:(User *)user
                  context:(NSManagedObjectContext *)context
                   saving:(LBImportSaving)saving
                     made:(NSUInteger *)made
                  skipped:(NSUInteger *)skipped
                    error:(NSError **)error {
    if (made) *made = 0;
    if (skipped) *skipped = 0;
    if (self.makesVehicles) return [self importMainTrackBy:user context:context saving:saving made:made skipped:skipped error:error];
    if (![self planForVehicle:vehicle by:user error:error]) return NO;
    NSMutableDictionary<NSString *, ORMForm *> *forms = [NSMutableDictionary dictionary];
    for (LBEntry *entry in _entries) {
        if ([self vehicle:vehicle has:entry]) {
            if (skipped) (*skipped)++;
            continue;
        }
        ORMForm *form = forms[entry.form] ?: [self form:entry.form error:error];
        if (!form) return NO;
        forms[entry.form] = form;
        ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form
                                                                 given:@{ @"vehicle" : vehicle.id.UUIDString ?: @"", @"enteredBy" : user.email ?: @"" }];
        /* The store's own refusal, kept: the session says only its summary. */
        __block NSError *refused = nil;
        [session useContext:context saving:^BOOL(NSManagedObjectContext *c, NSError **e) {
            NSError *why = nil;
            BOOL saved = saving(c, &why);
            if (!saved) refused = why;
            if (e) *e = why;
            return saved;
        }];
        NSError *failure = nil;
        if (![session open:&failure]) {
            if (error) *error = LBImportError(@"%@: its form %@ did not open: %@", entry.what, entry.form, failure.localizedDescription);
            return NO;
        }
        [entry.values enumerateKeysAndObjectsUsingBlock:^(NSString *element, NSString *value, BOOL *stop) {
            [session setValue:value forElement:element];
        }];
        [entry.repeats enumerateKeysAndObjectsUsingBlock:^(NSString *repeat, NSArray *rows, BOOL *stop) {
            [session setRows:rows forRepeat:repeat];
        }];
        if (![session save:&failure]) {
            NSMutableArray *said = [NSMutableArray array];
            [session.errors enumerateKeysAndObjectsUsingBlock:^(NSString *element, NSString *message, BOOL *stop) {
                [said addObject:element.length ? [NSString stringWithFormat:@"%@: %@", element, message] : message];
            }];
            if (refused) [said setArray:@[ LBRefusal(refused) ]];
            else if (!said.count && failure) [said addObject:LBRefusal(failure)];
            [context rollback];
            if (error) *error = LBImportError(@"%@ refused: %@", entry.what, [said componentsJoinedByString:@"; "]);
            return NO;
        }
        if (made) (*made)++;
    }
    return YES;
}


#pragma mark MainTrack's store

/* A table's rows, each a dictionary of its columns: text, numbers, data;
   NULL left out. */
static NSArray<NSDictionary *> *LBRows(sqlite3 *db, NSString *sql) {
    NSMutableArray *rows = [NSMutableArray array];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) return nil;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int i = 0; i < sqlite3_column_count(statement); i++) {
            NSString *name = @(sqlite3_column_name(statement, i));
            switch (sqlite3_column_type(statement, i)) {
            case SQLITE_INTEGER: row[name] = @(sqlite3_column_int64(statement, i)); break;
            case SQLITE_FLOAT: row[name] = @(sqlite3_column_double(statement, i)); break;
            case SQLITE_TEXT: row[name] = @((const char *)sqlite3_column_text(statement, i)); break;
            case SQLITE_BLOB: row[name] = [NSData dataWithBytes:sqlite3_column_blob(statement, i) length:(NSUInteger)sqlite3_column_bytes(statement, i)]; break;
            default: break;
            }
        }
        [rows addObject:row];
    }
    sqlite3_finalize(statement);
    return rows;
}

static NSString *LBText(NSDictionary *row, NSString *column) {
    id value = row[column];
    NSString *text = [value isKindOfClass:[NSString class]] ? value : nil;
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return text.length ? text : nil;
}

static double LBDouble(NSDictionary *row, NSString *column) {
    id value = row[column];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0;
}

/* A moment Core Data stores: seconds since 2001-01-01 UTC. */
static NSDate *LBMoment(NSDictionary *row, NSString *column) {
    id value = row[column];
    return [value isKindOfClass:[NSNumber class]] ? [NSDate dateWithTimeIntervalSinceReferenceDate:[value doubleValue]] : nil;
}

/* A distance in kilometres, to the metre, of a ride's distance and unit. */
static double LBKilometres(double distance, NSString *unit) {
    if ([unit isEqualToString:@"km"]) return distance;
    if ([unit isEqualToString:@"mi"]) return distance * 1.609344;
    return distance / 1000;
}

static NSString *LBDecimal(double value) {
    return [NSString stringWithFormat:@"%.3f", value];
}

- (BOOL)readMainTrack:(NSString *)path error:(NSError **)error {
    /* A copy (with its log), read: the app's store is never opened, and may
       be in use. */
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                   [NSString stringWithFormat:@"lb-maintrack-%@", [NSProcessInfo processInfo].globallyUniqueString]];
    [files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *copy = [folder stringByAppendingPathComponent:@"Maintrack.sqlite"];
    for (NSString *suffix in @[ @"", @"-wal", @"-shm" ]) {
        NSString *from = [path stringByAppendingString:suffix];
        if ([files fileExistsAtPath:from]) [files copyItemAtPath:from toPath:[copy stringByAppendingString:suffix] error:NULL];
    }
    sqlite3 *db = NULL;
    BOOL opened = sqlite3_open_v2(copy.UTF8String, &db, SQLITE_OPEN_READWRITE, NULL) == SQLITE_OK;
    NSMutableDictionary *tables = [NSMutableDictionary dictionary];
    NSMutableDictionary *entities = [NSMutableDictionary dictionary];
    if (opened) {
        for (NSDictionary *row in LBRows(db, @"SELECT Z_NAME, Z_ENT FROM Z_PRIMARYKEY") ?: @[]) entities[row[@"Z_NAME"]] = row[@"Z_ENT"];
        for (NSString *table in @[ @"ZMANAGEDGEAR", @"ZMANAGEDACTIVITY", @"ZMANAGEDASSIGNMENT", @"ZMANAGEDINVOICE", @"ZMANAGEDSERVICEHEADER",
                                   @"ZMANAGEDRULE" ]) {
            NSArray *rows = LBRows(db, [NSString stringWithFormat:@"SELECT * FROM %@", table]);
            if (rows) tables[table] = rows;
        }
    }
    if (db) sqlite3_close(db);
    [files removeItemAtPath:folder error:NULL];
    if (!opened || !entities[@"ManagedBike"] || !tables[@"ZMANAGEDGEAR"] || !tables[@"ZMANAGEDACTIVITY"]) {
        if (error) *error = LBImportError(@"%@ is no store of MainTrack's: Logbook reads MainTrack's Maintrack.sqlite.", path.lastPathComponent);
        return NO;
    }
    _tables = tables;
    _entities = entities;
    NSMutableArray *names = [NSMutableArray array];
    NSUInteger bikes = 0, components = 0;
    for (NSDictionary *gear in tables[@"ZMANAGEDGEAR"]) {
        if ([gear[@"Z_ENT"] isEqual:entities[@"ManagedBike"]]) {
            bikes++;
            if (LBText(gear, @"ZNAME")) [names addObject:LBText(gear, @"ZNAME")];
        } else if ([gear[@"Z_ENT"] isEqual:entities[@"ManagedComponent"]]) {
            components++;
        }
    }
    NSMutableSet *invoices = [NSMutableSet set];
    for (NSDictionary *log in tables[@"ZMANAGEDSERVICEHEADER"]) {
        if (log[@"ZINVOICE"] && [log[@"Z_ENT"] isEqual:entities[@"ManagedServiceLog"]]) [invoices addObject:log[@"ZINVOICE"]];
    }
    self.vehicleNames = names;
    self.counts = @{ @"bicycles" : @(bikes), @"components" : @(components), @"rides" : @([tables[@"ZMANAGEDACTIVITY"] count]),
                     @"services" : @(invoices.count) };
    self.leftOut = @[];
    return YES;
}

- (BOOL)makesVehicles {
    return [_source isEqualToString:@"MainTrack"];
}

/* MainTrack's as Logbook's: each bike a bicycle, each component one of the
   bike it was first fitted to, each ride a trip, each assignment a
   component change, each invoice a service; the readings worked out from
   the rides (the bike's distance at a moment: what it had ridden before). */
- (BOOL)planMainTrackBy:(User *)user error:(NSError **)error {
    NSString *currency = user.currency;
    if (!currency.length) {
        if (error) *error = LBImportError(@"MainTrack's store says no currency: say yours in Preferences first, and it is taken as its.");
        return NO;
    }
    NSMutableArray *leftOut = [NSMutableArray array];
    NSMutableArray<LBEntry *> *entries = [NSMutableArray array];
    NSMutableArray<LBBike *> *bikes = [NSMutableArray array];
    NSISO8601DateFormatter *write = [[NSISO8601DateFormatter alloc] init];
    NSDateFormatter *day = [[NSDateFormatter alloc] init];
    day.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    day.dateFormat = @"yyyy-MM-dd";
    day.timeZone = user.timeZone.length ? [NSTimeZone timeZoneWithName:user.timeZone] : [NSTimeZone localTimeZone];

    NSMutableDictionary<NSNumber *, NSDictionary *> *gear = [NSMutableDictionary dictionary];
    for (NSDictionary *row in _tables[@"ZMANAGEDGEAR"]) gear[row[@"Z_PK"]] = row;
    BOOL (^isBike)(NSNumber *) = ^BOOL(NSNumber *pk) { return [gear[pk][@"Z_ENT"] isEqual:self->_entities[@"ManagedBike"]]; };
    NSString * (^named)(NSNumber *) = ^NSString *(NSNumber *pk) { return LBText(gear[pk], @"ZNAME") ?: [NSString stringWithFormat:@"gear %@", pk]; };

    /* Each bike's rides, in time's order: its reading at a moment is its
       first reading and the rides begun before it. */
    NSMutableDictionary<NSNumber *, NSMutableArray<NSDictionary *> *> *rides = [NSMutableDictionary dictionary];
    for (NSDictionary *ride in _tables[@"ZMANAGEDACTIVITY"]) {
        NSNumber *bike = ride[@"ZPARENTGEAR"];
        if (!bike || !isBike(bike) || !LBMoment(ride, @"ZSTARTTIME")) {
            [leftOut addObject:[NSString stringWithFormat:@"A ride of %@: %@", bike ? named(bike) : @"no bike",
                                                         LBText(ride, @"ZTEXT") ?: @"(untitled)"]];
            continue;
        }
        if (!rides[bike]) rides[bike] = [NSMutableArray array];
        [rides[bike] addObject:ride];
    }
    for (NSMutableArray *list in rides.allValues) {
        [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [LBMoment(a, @"ZSTARTTIME") compare:LBMoment(b, @"ZSTARTTIME")];
        }];
    }
    double (^readingAt)(NSNumber *, NSDate *) = ^double(NSNumber *bike, NSDate *moment) {
        double km = LBDouble(gear[bike], @"ZINITIALODOMETER");
        for (NSDictionary *ride in rides[bike]) {
            if ([LBMoment(ride, @"ZSTARTTIME") compare:moment] != NSOrderedAscending) break;
            km += LBKilometres(LBDouble(ride, @"ZDISTANCE"), LBText(ride, @"ZDISTANCEUNITRAWVALUE"));
        }
        return km;
    };

    /* The bikes. */
    NSUInteger photos = 0, strava = 0;
    for (NSDictionary *row in _tables[@"ZMANAGEDGEAR"]) {
        NSNumber *pk = row[@"Z_PK"];
        if (!isBike(pk)) continue;
        LBBike *bike = [[LBBike alloc] init];
        bike.pk = pk;
        bike.name = named(pk);
        NSString *brand = LBText(row, @"ZBRAND"), *model = LBText(row, @"ZMODEL");
        bike.make = brand ?: bike.name;
        bike.model = model ?: bike.name;
        if (!brand || !model)
            [leftOut addObject:[NSString stringWithFormat:@"Bicycle %@: no %@ in MainTrack; its name taken as it", bike.name,
                                                         !brand && !model ? @"brand or model" : !brand ? @"brand" : @"model"]];
        if (LBDouble(row, @"ZINITIALODOMETER") > 0) bike.odometer = [NSDecimalNumber decimalNumberWithString:LBDecimal(LBDouble(row, @"ZINITIALODOMETER"))];
        int32_t year = (int32_t)LBDouble(row, @"ZYEAR");
        bike.year = year >= 1886 ? year : 0;
        double price = LBDouble(row, @"ZPURCHASEVALUE");
        NSDate *bought = LBMoment(row, @"ZPURCHASEDATE");
        if (bought) bike.bought = [day dateFromString:[day stringFromDate:bought]];
        if (price > 0) bike.price = [NSDecimalNumber decimalNumberWithString:LBDecimal(price)];
        if ([row[@"ZRETIRED"] intValue]) [leftOut addObject:[NSString stringWithFormat:@"Bicycle %@: retired in MainTrack (Logbook keeps it as it is)", bike.name]];
        for (NSString *column in @[ @"ZSERIALNUMBER", @"ZSIZE", @"ZDEALER", @"ZNOTES", @"ZINVOICE" ]) {
            if (LBText(row, column))
                [leftOut addObject:[NSString stringWithFormat:@"Bicycle %@: its %@ '%@'", bike.name,
                                                             [[column substringFromIndex:1] lowercaseString], LBText(row, column)]];
        }
        if ([row[@"ZIMAGEDATA"] length]) photos++;
        if (LBText(row, @"ZSTRAVAID")) strava++;
        [bikes addObject:bike];
    }

    /* Each ride a trip of its bike. */
    NSUInteger routes = 0;
    for (NSNumber *bike in rides) {
        for (NSDictionary *ride in rides[bike]) {
            NSDate *start = LBMoment(ride, @"ZSTARTTIME");
            double from = readingAt(bike, start), km = LBKilometres(LBDouble(ride, @"ZDISTANCE"), LBText(ride, @"ZDISTANCEUNITRAWVALUE"));
            NSMutableArray *note = [NSMutableArray array];
            if (LBText(ride, @"ZTEXT")) [note addObject:LBText(ride, @"ZTEXT")];
            BOOL virtual = [LBText(ride, @"ZACTIVITYTYPERAWVALUE") isEqualToString:@"VirtualRide"] || [ride[@"ZTRAINNER"] intValue];
            if ([ride[@"ZCOMMUTE"] intValue]) [note addObject:@"(commute)"];
            if (LBText(ride, @"ZNOTES")) [note addObject:LBText(ride, @"ZNOTES")];
            if (LBText(ride, @"ZPOLYLINE") || LBText(ride, @"ZLOCATION") || LBDouble(ride, @"ZSTARTLATITUDE") != 0) routes++;
            if (ride[@"ZSTRAVAID"] && [ride[@"ZSTRAVAID"] longLongValue]) strava++;
            NSMutableDictionary *values = [@{ @"timestamp" : [write stringFromDate:start], @"mileageQuantity" : LBDecimal(from),
                                              @"mileageDistanceUnit" : @"km",
                                              @"moment" : [write stringFromDate:[start dateByAddingTimeInterval:MAX(0, LBDouble(ride, @"ZDURATION"))]],
                                              @"distanceQuantity" : LBDecimal(from + km), @"distanceDistanceUnit" : @"km",
                                              @"lengthQuantity" : LBDecimal(km), @"lengthDistanceUnit" : @"km",
                                              @"driver" : user.email ?: @"" } mutableCopy];
            if (note.count) values[@"note"] = [note componentsJoinedByString:@" "];
            if (virtual) values[@"isVirtual"] = @"true";
            LBEntry *entry = [[LBEntry alloc] init];
            entry.form = @"RecordTrip";
            entry.what = [NSString stringWithFormat:@"The ride of %@ on %@", named(bike), [day stringFromDate:start]];
            entry.kind = [Trip class];
            entry.moment = start;
            entry.mileage = [NSDecimalNumber decimalNumberWithString:LBDecimal(from)];
            entry.bike = bike;
            entry.values = values;
            [entries addObject:entry];
        }
    }

    /* Which bike a component was on at a moment: the bike it was assigned
       to then, or the bike the component it was assigned to (a tyre to a
       wheel) was on. */
    NSArray<NSDictionary *> *assignments = [_tables[@"ZMANAGEDASSIGNMENT"] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [LBMoment(a, @"ZSTARTDATE") ?: [NSDate distantPast] compare:LBMoment(b, @"ZSTARTDATE") ?: [NSDate distantPast]];
    }];
    __block NSNumber * (^bikeOf)(NSNumber *, NSDate *, NSUInteger);
    NSNumber * (^bikeOfAt)(NSNumber *, NSDate *, NSUInteger) = ^NSNumber *(NSNumber *pk, NSDate *moment, NSUInteger depth) {
        if (isBike(pk)) return pk;
        if (depth > 4) return nil;
        for (NSDictionary *a in assignments) {
            NSDate *from = LBMoment(a, @"ZSTARTDATE"), *until = LBMoment(a, @"ZENDDATE");
            if (![a[@"ZASSIGNEE"] isEqual:pk] || !from || [from compare:moment] == NSOrderedDescending) continue;
            if (until && [until compare:moment] == NSOrderedAscending) continue;
            return bikeOf(a[@"ZASSIGNOR"], moment, depth + 1);
        }
        return nil;
    };
    bikeOf = bikeOfAt;

    /* Each component a unit of an item of the catalog's (the item: its
       name, of the category of its part, by its brand); it is wherever its
       changes put it. */
    NSMutableArray<LBPart *> *parts = [NSMutableArray array];
    NSMutableSet<NSNumber *> *isPart = [NSMutableSet set];
    for (NSDictionary *row in _tables[@"ZMANAGEDGEAR"]) {
        NSNumber *pk = row[@"Z_PK"];
        if (![row[@"Z_ENT"] isEqual:_entities[@"ManagedComponent"]]) continue;
        LBPart *part = [[LBPart alloc] init];
        part.pk = pk;
        part.item = named(pk);
        part.category = LBText(row, @"ZPARTTYPERAW");
        if (!part.category) [leftOut addObject:[NSString stringWithFormat:@"Component %@: no part type in MainTrack; of no category", named(pk)]];
        part.manufacturer = LBText(row, @"ZBRAND");
        part.model = LBText(row, @"ZMODEL");
        part.serial = LBText(row, @"ZSERIALNUMBER");
        part.note = LBText(row, @"ZNOTES");
        double price = LBDouble(row, @"ZPURCHASEVALUE");
        if (price > 0) part.cost = [NSDecimalNumber decimalNumberWithString:LBDecimal(price)];
        NSDate *bought = LBMoment(row, @"ZPURCHASEDATE");
        if (bought) part.bought = [day dateFromString:[day stringFromDate:bought]];
        if ([row[@"ZIMAGEDATA"] length]) photos++;
        BOOL fitted = NO;
        for (NSDictionary *a in assignments) fitted = fitted || [a[@"ZASSIGNEE"] isEqual:pk];
        if (!fitted) [leftOut addObject:[NSString stringWithFormat:@"Component %@: never fitted; a unit of your stock at no place", named(pk)]];
        [parts addObject:part];
        [isPart addObject:pk];
    }

    /* Each assignment a change fitting the unit, to the bike it was on then
       (into the unit it was assigned to: a tyre into a wheel); one of the
       same part taken off that bike a little before or after (two days) is
       the one it removed. */
    NSMutableSet *paired = [NSMutableSet set];
    for (NSDictionary *a in assignments) {
        NSNumber *component = a[@"ZASSIGNEE"];
        NSDate *from = LBMoment(a, @"ZSTARTDATE");
        if (![isPart containsObject:component] || !from) continue;
        NSNumber *bike = bikeOf(component, from, 0);
        if (!bike) {
            [leftOut addObject:[NSString stringWithFormat:@"Component %@: fitted on %@ into %@, on no bike then", named(component),
                                                         [day stringFromDate:from], named(a[@"ZASSIGNOR"])]];
            continue;
        }
        NSNumber *retired = nil;
        for (NSDictionary *b in assignments) {
            NSDate *until = LBMoment(b, @"ZENDDATE");
            NSNumber *other = b[@"ZASSIGNEE"];
            if (!until || [other isEqual:component] || [paired containsObject:b[@"Z_PK"]] || ![isPart containsObject:other]) continue;
            if (![bikeOf(other, until, 0) isEqual:bike] && ![bikeOf(other, [until dateByAddingTimeInterval:-1], 0) isEqual:bike]) continue;
            if (fabs([until timeIntervalSinceDate:from]) > 2 * 86400) continue;
            if (![LBText(gear[other], @"ZPARTTYPERAW") ?: @"" isEqualToString:LBText(gear[component], @"ZPARTTYPERAW") ?: @""]) continue;
            retired = other;
            [paired addObject:b[@"Z_PK"]];
            break;
        }
        NSMutableDictionary *refers = [@{ @"stockUnit" : component } mutableCopy];
        if (retired) refers[@"removedStockUnit"] = retired;
        if ([isPart containsObject:a[@"ZASSIGNOR"]]) refers[@"host"] = a[@"ZASSIGNOR"];
        double reading = readingAt(bike, from);
        LBEntry *entry = [[LBEntry alloc] init];
        entry.form = @"RecordComponentChange";
        entry.what = [NSString stringWithFormat:@"%@ fitted to %@ on %@", named(component), named(bike), [day stringFromDate:from]];
        entry.kind = [ComponentChange class];
        entry.moment = from;
        entry.mileage = [NSDecimalNumber decimalNumberWithString:LBDecimal(reading)];
        entry.bike = bike;
        entry.refers = refers;
        entry.values = @{ @"timestamp" : [write stringFromDate:from], @"mileageQuantity" : LBDecimal(reading), @"mileageDistanceUnit" : @"km",
                          @"driver" : user.email ?: @"" };
        [entries addObject:entry];
    }
    for (NSDictionary *b in assignments) {
        NSDate *until = LBMoment(b, @"ZENDDATE");
        if (until && [isPart containsObject:b[@"ZASSIGNEE"]] && ![paired containsObject:b[@"Z_PK"]])
            [leftOut addObject:[NSString stringWithFormat:@"Component %@: taken off on %@ (Logbook retires one as another is fitted)",
                                                         named(b[@"ZASSIGNEE"]), [day stringFromDate:until]]];
    }

    /* Each invoice a service of the bike its log entries are of; each
       entry a task, the invoice's amount on the first. */
    NSMutableDictionary<NSNumber *, NSMutableArray<NSDictionary *> *> *logs = [NSMutableDictionary dictionary];
    NSUInteger plans = 0;
    for (NSDictionary *log in _tables[@"ZMANAGEDSERVICEHEADER"]) {
        if ([log[@"Z_ENT"] isEqual:_entities[@"ManagedServicePlan"]]) {
            plans++;
            continue;
        }
        NSNumber *invoice = log[@"ZINVOICE"];
        if (!invoice) {
            [leftOut addObject:[NSString stringWithFormat:@"A service log of %@ (%@ %@): on no invoice, so on no day",
                                                         log[@"ZGEAR"] ? named(log[@"ZGEAR"]) : @"no bike", LBText(log, @"ZSERVICETYPERAW") ?: @"",
                                                         LBText(log, @"ZPARTTYPERAW") ?: @""]];
            continue;
        }
        if (!logs[invoice]) logs[invoice] = [NSMutableArray array];
        [logs[invoice] addObject:log];
    }
    if (plans) [leftOut addObject:[NSString stringWithFormat:@"%lu service plans: not imported yet (Logbook's schedules)", (unsigned long)plans]];
    NSUInteger invoiceImages = 0;
    for (NSDictionary *invoice in _tables[@"ZMANAGEDINVOICE"]) {
        NSArray<NSDictionary *> *group = [logs[invoice[@"Z_PK"]] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"Z_PK"] compare:b[@"Z_PK"]];
        }];
        NSDate *when = LBMoment(invoice, @"ZDATE");
        NSString *what = [NSString stringWithFormat:@"The invoice of %@%@", when ? [day stringFromDate:when] : @"no day",
                                                    LBText(invoice, @"ZSHOP") ? [NSString stringWithFormat:@" at %@", LBText(invoice, @"ZSHOP")] : @""];
        NSNumber *bike = nil;
        for (NSDictionary *log in group) {
            if (log[@"ZGEAR"] && when) bike = bike ?: bikeOf(log[@"ZGEAR"], when, 0);
        }
        if (!when || !bike) {
            [leftOut addObject:[NSString stringWithFormat:@"%@: %@", what, !when ? @"on no day" : @"of no bike (it has no service log)"]];
            continue;
        }
        if ([invoice[@"ZIMAGEDATA"] length]) invoiceImages++;
        double reading = readingAt(bike, when);
        NSMutableDictionary *values = [@{ @"timestamp" : [write stringFromDate:when], @"mileageQuantity" : LBDecimal(reading),
                                          @"mileageDistanceUnit" : @"km", @"driver" : user.email ?: @"", @"currency" : currency,
                                          @"serviceKind" : @"Maintenance" } mutableCopy];
        if (LBText(invoice, @"ZSHOP")) values[@"garage"] = LBText(invoice, @"ZSHOP");
        NSMutableArray *note = [NSMutableArray array];
        if (LBText(invoice, @"ZNUMBER")) [note addObject:[NSString stringWithFormat:@"Invoice %@.", LBText(invoice, @"ZNUMBER")]];
        if (LBText(invoice, @"ZNOTES")) [note addObject:LBText(invoice, @"ZNOTES")];
        if (note.count) values[@"note"] = [note componentsJoinedByString:@" "];
        NSMutableArray *items = [NSMutableArray array];
        double amount = LBDouble(invoice, @"ZAMOUNT");
        for (NSDictionary *log in group) {
            NSString *task = [[NSString stringWithFormat:@"%@ %@", LBText(log, @"ZSERVICETYPERAW") ?: @"", LBText(log, @"ZPARTTYPERAW") ?: @""]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableDictionary *item = [@{ @"task" : task.length ? task : @"Service" } mutableCopy];
            NSMutableArray *said = [NSMutableArray array];
            for (NSString *column in @[ @"ZPRODUCTRAWVALUE", @"ZTEXT", @"ZNOTES" ]) if (LBText(log, column)) [said addObject:LBText(log, column)];
            if (said.count) item[@"note"] = [said componentsJoinedByString:@" "];
            if (!items.count && amount > 0) {
                item[@"costAmount"] = LBDecimal(amount);
                item[@"costCurrency"] = currency;
            }
            [items addObject:item];
        }
        LBEntry *entry = [[LBEntry alloc] init];
        entry.form = @"RecordService";
        entry.what = what;
        entry.kind = [Service class];
        entry.moment = when;
        entry.mileage = [NSDecimalNumber decimalNumberWithString:LBDecimal(reading)];
        entry.bike = bike;
        entry.values = values;
        entry.repeats = @{ @"serviceItems" : items };
        [entries addObject:entry];
    }
    if (logs.count) [leftOut addObject:@"MainTrack's services are entered as Maintenance (it says no kind)"];
    if (photos) [leftOut addObject:[NSString stringWithFormat:@"%lu photos of bikes and components", (unsigned long)photos]];
    if (invoiceImages) [leftOut addObject:[NSString stringWithFormat:@"%lu invoices' pictures", (unsigned long)invoiceImages]];
    if (routes) [leftOut addObject:[NSString stringWithFormat:@"%lu rides' routes and places", (unsigned long)routes]];
    if (strava) [leftOut addObject:@"Strava's ids of the bikes and rides"];
    if ([_tables[@"ZMANAGEDRULE"] count]) [leftOut addObject:[NSString stringWithFormat:@"%lu assignment rules", (unsigned long)[_tables[@"ZMANAGEDRULE"] count]]];

    /* Made in this order: components first (changes fit them), then what
       happened, in time's order. */
    [entries sortUsingComparator:^NSComparisonResult(LBEntry *a, LBEntry *b) { return [a.moment compare:b.moment]; }];
    _entries = entries;
    _bikes = bikes;
    _parts = parts;
    self.leftOut = leftOut;
    return YES;
}

/* The bike as a vehicle of the user's: the one of its name they own, else
   one made (saved as the vehicle's tab saves). */
- (Vehicle *)vehicleOfBike:(LBBike *)bike by:(User *)user context:(NSManagedObjectContext *)context saving:(LBImportSaving)saving
                      made:(BOOL *)made error:(NSError **)error {
    *made = NO;
    for (Vehicle *each in user.ownedVehicles) {
        if ([each.vehicleName isEqualToString:bike.name] && !each.isDeleted) return each;
    }
    Vehicle *vehicle = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Vehicle class]) inManagedObjectContext:context];
    vehicle.id = [NSUUID UUID];
    vehicle.vehicleName = bike.name;
    vehicle.vehicleKind = @"Bicycle";
    /* No meter: its readings, its rides added up (LBProcedures). */
    vehicle.hasNoMeter = YES;
    if (bike.odometer) {
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([DistanceUnit class])];
        fetch.predicate = [NSPredicate predicateWithFormat:@"code == %@", @"km"];
        vehicle.purchaseMileageQuantity = bike.odometer;
        vehicle.purchaseMileageDistanceUnit = [[context executeFetchRequest:fetch error:NULL] firstObject];
    }
    vehicle.make = bike.make;
    vehicle.carModel = bike.model;
    if (bike.year) vehicle.manufactureYear = bike.year;
    if (bike.bought) vehicle.purchaseDate = bike.bought;
    if (bike.price) {
        vehicle.purchasePriceAmount = bike.price;
        vehicle.purchasePriceCurrency = user.currency;
    }
    vehicle.owner = user;
    NSError *failure = nil;
    if (!saving(context, &failure)) {
        [context rollback];
        if (error) *error = LBImportError(@"Bicycle %@ refused: %@", bike.name, failure ? LBRefusal(failure) : @"not saved");
        return nil;
    }
    *made = YES;
    return vehicle;
}

/* The parts' units, in the catalog named (the user's of that name, else
   made): an item of each name (of its part's category, its brand's), and
   a unit of it each; an item had already keeps its units, the parts taken
   as them in order, and more made where there are more. Each part's unit's
   key in keys. */
- (BOOL)unitsOfParts:(NSMutableDictionary<NSNumber *, NSString *> *)keys by:(User *)user context:(NSManagedObjectContext *)context
              saving:(LBImportSaving)saving made:(NSUInteger *)made skipped:(NSUInteger *)skipped error:(NSError **)error {
    NSString *name = _catalogName.length ? _catalogName : @"Bike parts";
    Catalog *catalog = nil;
    for (Catalog *each in user.ownedCatalogs) {
        if ([each.catalogName isEqualToString:name] && !each.isDeleted) catalog = each;
    }
    if (!catalog) {
        catalog = [Catalog lb_newCatalogNamed:name owner:user inContext:context];
        catalog.currency = user.currency;
        if (made) (*made)++;
    }
    NSMutableDictionary<NSString *, Category *> *categories = [NSMutableDictionary dictionary];
    for (Category *each in catalog.categories) if (each.categoryName) categories[each.categoryName] = each;
    NSMutableDictionary<NSString *, StockItem *> *items = [NSMutableDictionary dictionary];
    for (StockItem *each in catalog.stockItems) if (each.itemName && !each.isDeleted) items[each.itemName] = each;
    NSMutableDictionary<NSString *, NSMutableArray<LBPart *> *> *byItem = [NSMutableDictionary dictionary];
    for (LBPart *part in [_parts sortedArrayUsingComparator:^NSComparisonResult(LBPart *a, LBPart *b) { return [a.pk compare:b.pk]; }]) {
        if (!byItem[part.item]) byItem[part.item] = [NSMutableArray array];
        [byItem[part.item] addObject:part];
    }
    for (NSString *itemName in [byItem.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray<LBPart *> *group = byItem[itemName];
        StockItem *item = items[itemName];
        if (!item) {
            item = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([StockItem class]) inManagedObjectContext:context];
            item.id = [NSUUID UUID];
            item.itemName = itemName;
            item.catalog = catalog;
            item.created = [NSDate date];
            item.sku = [catalog lb_nextSKU];
            LBPart *first = group.firstObject;
            if (first.category) {
                Category *category = categories[first.category];
                if (!category) {
                    category = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Category class]) inManagedObjectContext:context];
                    category.id = [NSUUID UUID];
                    category.categoryName = first.category;
                    category.catalog = catalog;
                    categories[first.category] = category;
                }
                item.category = category;
            }
            if (first.manufacturer) {
                item.manufacturer = first.manufacturer;
                if (first.model) item.mpn = first.model;
            }
            for (LBPart *part in group) {
                if (part.cost && !item.unitCostAmount) {
                    item.unitCostAmount = part.cost;
                    item.unitCostCurrency = user.currency;
                }
                if (part.bought && !item.purchased) item.purchased = part.bought;
            }
            if (made) (*made)++;
        } else if (skipped) {
            (*skipped)++;
        }
        NSArray<StockUnit *> *had = [item.stockUnits.allObjects sortedArrayUsingComparator:^NSComparisonResult(StockUnit *a, StockUnit *b) {
            return [a.id.UUIDString compare:b.id.UUIDString];
        }];
        for (NSUInteger i = 0; i < group.count; i++) {
            LBPart *part = group[i];
            /* By its serial where it has one, else in order. */
            StockUnit *unit = nil;
            for (StockUnit *each in had) if (part.serial && [each.serialNumber isEqualToString:part.serial]) unit = each;
            if (!unit && !part.serial && i < had.count && !had[i].serialNumber) unit = had[i];
            if (unit) {
                if (skipped) (*skipped)++;
            } else {
                unit = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([StockUnit class]) inManagedObjectContext:context];
                unit.id = [NSUUID UUID];
                unit.stockItem = item;
                unit.serialNumber = part.serial;
                unit.note = part.note;
                if (made) (*made)++;
            }
            keys[part.pk] = unit.id.UUIDString;
        }
    }
    NSError *failure = nil;
    if (!saving(context, &failure)) {
        [context rollback];
        if (error) *error = LBImportError(@"The parts' items and units refused: %@", failure ? LBRefusal(failure) : @"not saved");
        return NO;
    }
    return YES;
}

- (BOOL)importMainTrackBy:(User *)user context:(NSManagedObjectContext *)context saving:(LBImportSaving)saving
                     made:(NSUInteger *)made skipped:(NSUInteger *)skipped error:(NSError **)error {
    if (![self planMainTrackBy:user error:error]) return NO;
    NSMutableDictionary<NSNumber *, Vehicle *> *vehicles = [NSMutableDictionary dictionary];
    for (LBBike *bike in _bikes) {
        BOOL new = NO;
        Vehicle *vehicle = [self vehicleOfBike:bike by:user context:context saving:saving made:&new error:error];
        if (!vehicle) return NO;
        vehicles[bike.pk] = vehicle;
        if (new && made) (*made)++;
        if (!new && skipped) (*skipped)++;
    }
    NSMutableDictionary<NSNumber *, NSString *> *keys = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, ORMForm *> *forms = [NSMutableDictionary dictionary];
    if (_parts.count && ![self unitsOfParts:keys by:user context:context saving:saving made:made skipped:skipped error:error]) return NO;
    for (LBEntry *entry in _entries) {
        Vehicle *vehicle = vehicles[entry.bike];
        if (!vehicle) continue;
        NSMutableDictionary *values = [entry.values mutableCopy];
        BOOL missing = NO;
        for (NSString *element in entry.refers) {
            NSString *key = keys[entry.refers[element]];
            if (key) values[element] = key;
            else missing = YES;
        }
        if (missing) continue;
        if ([self vehicle:vehicle has:entry fitting:values[@"stockUnit"]]) {
            if (skipped) (*skipped)++;
            continue;
        }
        ORMForm *form = forms[entry.form] ?: [self form:entry.form error:error];
        if (!form) return NO;
        forms[entry.form] = form;
        ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form
                                                                 given:@{ @"vehicle" : vehicle.id.UUIDString ?: @"", @"enteredBy" : user.email ?: @"" }];
        /* The store's own refusal, kept: the session says only its summary. */
        __block NSError *refused = nil;
        [session useContext:context saving:^BOOL(NSManagedObjectContext *c, NSError **e) {
            NSError *why = nil;
            BOOL saved = saving(c, &why);
            if (!saved) refused = why;
            if (e) *e = why;
            return saved;
        }];
        NSError *failure = nil;
        if (![session open:&failure]) {
            if (error) *error = LBImportError(@"%@: its form %@ did not open: %@", entry.what, entry.form, failure.localizedDescription);
            return NO;
        }
        [values enumerateKeysAndObjectsUsingBlock:^(NSString *element, NSString *value, BOOL *stop) {
            [session setValue:value forElement:element];
        }];
        [entry.repeats enumerateKeysAndObjectsUsingBlock:^(NSString *repeat, NSArray *rows, BOOL *stop) {
            [session setRows:rows forRepeat:repeat];
        }];
        if (![session save:&failure]) {
            NSMutableArray *said = [NSMutableArray array];
            [session.errors enumerateKeysAndObjectsUsingBlock:^(NSString *element, NSString *message, BOOL *stop) {
                [said addObject:element.length ? [NSString stringWithFormat:@"%@: %@", element, message] : message];
            }];
            if (refused) [said setArray:@[ LBRefusal(refused) ]];
            else if (!said.count && failure) [said addObject:LBRefusal(failure)];
            [context rollback];
            if (error) *error = LBImportError(@"%@ refused: %@", entry.what, [said componentsJoinedByString:@"; "]);
            return NO;
        }
        if (made) (*made)++;
    }
    return YES;
}

@end
