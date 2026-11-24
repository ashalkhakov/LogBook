#import "LBImport.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "VehicleDriver+CoreDataClass.h"
#import "Record+CoreDataClass.h"
#import "Event+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"

NSErrorDomain const LBImportErrorDomain = @"LBImportErrorDomain";

static NSError *LBImportError(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static NSError *LBImportError(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *said = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    return [NSError errorWithDomain:LBImportErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey : said }];
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
@end

@implementation LBEntry
@end

@implementation LBImport {
    NSDictionary<NSString *, LBSection *> *_sections;
    NSArray<LBEntry *> *_entries;
}

+ (instancetype)importOfFile:(NSURL *)file error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:file options:0 error:error];
    return data ? [self importOfData:data named:file.lastPathComponent error:error] : nil;
}

+ (instancetype)importOfData:(NSData *)data named:(NSString *)name error:(NSError **)error {
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
    for (Record *record in vehicle.records) {
        if (![record isKindOfClass:entry.kind] || record.isDeleted) continue;
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
        [session useContext:context saving:saving];
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
            if (!said.count && failure.localizedDescription) [said addObject:failure.localizedDescription];
            [context rollback];
            if (error) *error = LBImportError(@"%@ refused: %@", entry.what, [said componentsJoinedByString:@"; "]);
            return NO;
        }
        if (made) (*made)++;
    }
    return YES;
}

@end
