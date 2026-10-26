// The offline store (Shared/LBLocalStore.h) checked against a server:
// devices, each a store of its own in a temporary directory, syncing with
// the server at the root given, signed in as their users (LB_TOKENS; an
// expense kind of a user's seeded: Tests/sync-check.sh), so that what
// they send is kept to the permissions. Anna's phone and her tablet, then
// Ben's phone. Each check a line, "ok" or "FAIL"; 1 when one failed.
//
//   lb-sync-check <service root> build/Logbook.momd build/Logbook.ormplans [photo.jpg]
//
// - the reference data comes down (the units, the kinds of cost the
//   model's, the service kinds among them); a vehicle made on one device
//   reaches the other;
// - a fill-up saved with sync off waits, and goes once it is on;
// - a service with an item of a schedule's task closes its reminder as it
//   is saved, the next made, named by it: the other device has the same
//   reminders, of the same ids, as the server settled them;
// - a record changed on both devices: the server's version stands, the
//   other side's kept as a pending conflict, and each way of settling it:
//   keep theirs, keep mine (written back, and synced), edited by hand;
// - a receipt's photo (Tests/receipt-photo.jpg): its Attachment synced
//   with its content, through the server to the other device;
// - a change a rule refuses is not saved, each rule said;
// - shared: Ben sees no vehicle of Anna's until she shares it with him;
//   then he has it and its records, adds a fill-up of it, entered by him;
//   a change of his to her record the server refuses, kept as an issue.

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "LogbookValidation.h"
#import "LBLocalStore.h"
#import "LBProcedures.h"
#import "LBVehicleSummary.h"
#import "LBDisplay.h"
#import "Vehicle+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "Schedule+CoreDataClass.h"
#import "Reminder+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"
#import "VolumeUnit+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"
#import "VehicleDriver+CoreDataClass.h"
#import "User+CoreDataClass.h"

static NSUInteger LBFailures;

static void LBCheck(NSString *what, BOOL ok, id detail) {
    printf("%s %s%s\n", ok ? "ok  " : "FAIL", what.UTF8String,
           ok || !detail ? "" : [[NSString stringWithFormat:@": %@", detail] UTF8String]);
    fflush(stdout);
    if (!ok) LBFailures++;
}

static NSURL *LBRoot, *LBModelURL;

/* LB_DEBUG: what a device sends, said. */
@interface LBLoggingTransport : NSObject <ODataTransport>
@property (nonatomic, copy) NSString *who;
@end

@implementation LBLoggingTransport
- (void)startExchange:(ODataExchange *)exchange {
    NSString *body = exchange.request.HTTPBody ? [[NSString alloc] initWithData:exchange.request.HTTPBody encoding:NSUTF8StringEncoding] : @"";
    if (![exchange.request.HTTPMethod isEqual:@"GET"]) printf("debug %s: %s %s %s\n", self.who.UTF8String, exchange.request.HTTPMethod.UTF8String,
                                                          exchange.request.URL.absoluteString.UTF8String, body.UTF8String);
    [ODataDefaultTransport() startExchange:exchange];
}
@end

/* Secrets kept nowhere: a check's sign-in keeps none. */
@interface LBNoSecrets : NSObject <ODataSecretStoring>
@end

@implementation LBNoSecrets
- (NSDictionary<NSString *, id> *)secretsForAccount:(NSString *)account { return nil; }
- (BOOL)setSecrets:(NSDictionary<NSString *, id> *)secrets forAccount:(NSString *)account { return YES; }
@end

/* Signed in as a user already: the access token the issuer gave them
   (sync-check.sh), sent with every request, as a sign-in's tokens are. */
@interface LBTokenSignIn : ODataSignIn
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy) NSString *token;
@end

@implementation LBTokenSignIn

+ (instancetype)signInAs:(NSString *)email token:(NSString *)token {
    LBTokenSignIn *signIn = [[self alloc] initWithServiceRoot:LBRoot secrets:[[LBNoSecrets alloc] init]];
    signIn.email = email;
    signIn.token = token;
    return signIn;
}

- (BOOL)isSignedIn { return YES; }
- (NSString *)userName { return _email; }

- (ODataConfiguration *)configuration {
    ODataConfiguration *c = [[ODataConfiguration alloc] initWithURL:LBRoot options:nil];
    c.accessToken = _token;
    return c;
}

@end

/* The users' access tokens, when the server asks who is asking
   (LB_TOKENS: the issuer's file, sync-check.sh). */
static NSDictionary<NSString *, NSString *> *LBTokens(void) {
    const char *path = getenv("LB_TOKENS");
    NSData *data = path ? [NSData dataWithContentsOfFile:@(path)] : nil;
    NSDictionary *read = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [read isKindOfClass:[NSDictionary class]] ? read[@"tokens"] : nil;
}

static LBLocalStore *LBDevice(NSString *email) {
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                                   [NSString stringWithFormat:@"lb-sync-%@", [NSProcessInfo processInfo].globallyUniqueString]]
                                  isDirectory:YES];
    NSError *error = nil;
    LBLocalStore *store = [[LBLocalStore alloc] initWithDirectory:directory modelURL:LBModelURL error:&error];
    if (!store) {
        printf("FAIL %s's store: %s\n", email.UTF8String, error.localizedDescription.UTF8String);
        exit(1);
    }
    store.email = email;
    NSString *token = LBTokens()[email];
    if (token) store.signIn = [LBTokenSignIn signInAs:email token:token];
    store.serviceRoot = LBRoot;
    if (getenv("LB_DEBUG")) {
        LBLoggingTransport *logging = [[LBLoggingTransport alloc] init];
        logging.who = email;
        store.engine.remotes.firstObject.transport = logging;
    }
    return store;
}

static BOOL LBSync(LBLocalStore *store, NSString *what) {
    NSError *error = nil;
    BOOL ok = [store syncAndWait:&error];
    LBCheck(what, ok, error.localizedDescription);
    return ok;
}

/* A sync the store began of itself (some seconds after a save) let end,
   before sync is turned off: one running then still sends what is saved
   meanwhile. */
static void LBSyncEnded(LBLocalStore *store) {
    for (int i = 0; i < 300 && store.isSyncing; i++) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

static BOOL LBSave(LBLocalStore *store, NSString *what) {
    NSError *error = nil;
    BOOL ok = [store save:&error];
    LBCheck(what, ok, [[LBLocalStore sentencesOfError:error] componentsJoinedByString:@"; "]);
    return ok;
}

static id LBInsert(Class cls, LBLocalStore *store) {
    return [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass(cls) inManagedObjectContext:store.context];
}

static id LBFetch(Class cls, SEL key, id value, LBLocalStore *store) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(key), value];
    return [[store.context executeFetchRequest:fetch error:NULL] firstObject];
}

/* What the server refused, said: each change and why. */
static NSString *LBIssues(LBLocalStore *store) {
    NSMutableArray *said = [NSMutableArray array];
    for (ODataSyncIssue *issue in store.issues) {
        [said addObject:[NSString stringWithFormat:@"%@ %@ op %ld %@: %ld %@", issue.entityName, issue.key, (long)issue.operation,
                                                   issue.properties ?: @"(all)", (long)issue.status, issue.message]];
    }
    return [said componentsJoinedByString:@"; "];
}

static NSDecimalNumber *LBNumber(NSString *text) {
    return [NSDecimalNumber decimalNumberWithString:text];
}

/* A fill-up of the vehicle, now, as the phone's form makes one. */
static FillUp *LBFillUp(LBLocalStore *store, Vehicle *vehicle, NSString *km) {
    FillUp *fillUp = LBInsert([FillUp class], store);
    fillUp.vehicle = vehicle;
    fillUp.enteredBy = store.user;
    fillUp.driver = store.user;
    fillUp.timestamp = LBNow();
    fillUp.mileageQuantity = LBNumber(km);
    fillUp.mileageDistanceUnit = LBFetch([DistanceUnit class], @selector(code), @"km", store);
    fillUp.volumeQuantity = LBNumber(@"40.5");
    fillUp.volumeVolumeUnit = LBFetch([VolumeUnit class], @selector(code), @"L", store);
    fillUp.totalAmount = LBNumber(@"68.40");
    fillUp.totalCurrency = @"EUR";
    fillUp.filledTheTank = YES;
    fillUp.fuel = vehicle.fuel;
    fillUp.station = @"Shell";
    return fillUp;
}

/* The same object on the other device, read afresh. */
static id LBThere(LBLocalStore *store, Class cls, NSUUID *uuid) {
    id object = LBFetch(cls, @selector(id), uuid, store);
    if (object) [store.context refreshObject:object mergeChanges:NO];
    return object;
}

/* What the server has at the path, as the user reads it (their token):
   read afresh, as GNUstep's plain read keeps an http answer in a cache. */
static NSData *LBServerRead(NSString *path, NSString *email) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path relativeToURL:LBRoot]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    NSString *token = LBTokens()[email];
    if (token) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    __block NSData *read = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        read = data;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return read;
}

/* A field of a fill-up changed on both devices, the tablet's synced first: Anna's
   sync takes the tablet's, and keeps hers as a pending conflict. */
static LBPendingConflict *LBConflict(LBLocalStore *anna, LBLocalStore *tablet, NSUUID *fillUpID, SEL field, NSString *hers,
                                     NSString *his) {
    FillUp *there = LBThere(tablet, [FillUp class], fillUpID);
    [there setValue:his forKey:NSStringFromSelector(field)];
    LBSave(tablet, @"the tablet's change saved");
    if (getenv("LB_DEBUG")) {
        for (ODataSyncChange *change in tablet.engine.pendingChanges)
            printf("debug: the tablet waits %s %ld %s; versions %s\n", change.entityName.UTF8String, (long)change.operation,
                   change.properties.description.UTF8String, [[there valueForKey:@"syncVersions"] description].UTF8String);
    }
    LBSync(tablet, @"and synced");
    LBCheck(@"the tablet's went", [tablet pendingCount] == 0 && !tablet.issues.count, LBIssues(tablet));
    NSData *row = LBServerRead([NSString stringWithFormat:@"Records(%@)", fillUpID.UUIDString], @"anna@example.org");
    NSDictionary *json = row ? [NSJSONSerialization JSONObjectWithData:row options:0 error:NULL] : nil;
    NSString *wire = [NSStringFromSelector(field) capitalizedString];
    LBCheck(@"the server has the tablet's", [json[wire] isEqual:his], json);
    anna.syncEnabled = NO;
    FillUp *here = LBThere(anna, [FillUp class], fillUpID);
    [here setValue:hers forKey:NSStringFromSelector(field)];
    LBSave(anna, @"Anna's saved, offline");
    anna.syncEnabled = YES;
    LBSync(anna, @"Anna syncs");
    here = LBThere(anna, [FillUp class], fillUpID);
    NSString *now = [here valueForKey:NSStringFromSelector(field)];
    LBCheck(@"the server's version stands", [now isEqualToString:his], now);
    NSArray<LBPendingConflict *> *pending = [anna pendingConflicts];
    LBPendingConflict *conflict = pending.firstObject;
    LBCheck(@"Anna's kept as a pending conflict, of the fill-up and the field",
            pending.count == 1 && [conflict.objectEntityName isEqualToString:NSStringFromClass([FillUp class])]
                && [conflict.properties isEqualToArray:@[ NSStringFromSelector(field) ]]
                && [conflict.mine[NSStringFromSelector(field)] isEqual:hers] && [conflict.theirs[NSStringFromSelector(field)] isEqual:his]
                && [anna objectOfConflict:conflict] == here,
            pending.count ? [NSString stringWithFormat:@"%@ %@ mine %@ theirs %@", conflict.objectEntityName, conflict.properties, conflict.mine,
                                                       conflict.theirs]
                          : @"none");
    return conflict;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 4) {
            fprintf(stderr, "usage: lb-sync-check <service root> Logbook.momd Logbook.ormplans [photo.jpg]\n");
            return 2;
        }
        LBRoot = [NSURL URLWithString:@(argv[1])];
        LBModelURL = [NSURL fileURLWithPath:@(argv[2])];
        NSError *error = nil;
        NSData *plans = [NSData dataWithContentsOfFile:@(argv[3])];
        id list = plans ? [NSPropertyListSerialization propertyListWithData:plans options:0 format:NULL error:&error] : nil;
        ORMTables *tables = list ? [ORMTables tablesWithPropertyList:list error:&error] : nil;
        if (!tables) {
            printf("FAIL the tables: %s\n", error.localizedDescription.UTF8String ?: argv[3]);
            return 1;
        }
        [ORMTables registerTables:tables named:@"Logbook"];

        LBLocalStore *anna = LBDevice(@"anna@example.org");
        LBLocalStore *tablet = LBDevice(@"anna@example.org");
        LBSync(anna, @"Anna's device syncs");
        LBCheck(@"the units came down", LBFetch([DistanceUnit class], @selector(code), @"km", anna) != nil, nil);
        NSFetchRequest *kinds = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([CostKind class])];
        NSArray *names = [[anna.context executeFetchRequest:kinds error:NULL] valueForKey:NSStringFromSelector(@selector(name))];
        BOOL allKinds = YES;
        for (NSString *name in @[ @"Fuel", @"Maintenance", @"Repair", @"Tyres", @"Documents" ]) allKinds = allKinds && [names containsObject:name];
        LBCheck(@"and the model's kinds of cost", allKinds, names);
        NSArray *serviceKinds = [[CostKind lbServiceKindsInContext:anna.context] valueForKey:NSStringFromSelector(@selector(name))];
        LBCheck(@"the kinds of service, as the model's rule finds them", [serviceKinds isEqualToArray:(@[ @"Maintenance", @"Repair" ])],
                serviceKinds);

        Vehicle *golf = LBInsert([Vehicle class], anna);
        golf.vehicleName = @"Golf";
        golf.make = @"Volkswagen";
        golf.carModel = @"Golf VII";
        golf.manufactureYear = 2016;
        golf.fuel = @"Petrol";
        golf.owner = anna.user;
        LBSave(anna, @"a vehicle saved");
        LBSync(anna, @"and synced");
        LBCheck(@"nothing waits", [anna pendingCount] == 0, @([anna pendingCount]));
        LBSync(tablet, @"her tablet syncs");
        Vehicle *golfThere = LBThere(tablet, [Vehicle class], golf.id);
        LBCheck(@"the tablet has the vehicle, Anna's", [golfThere.owner.email isEqualToString:@"anna@example.org"], golfThere.owner.email);

        /* Offline. */
        LBSyncEnded(anna);
        anna.syncEnabled = NO;
        FillUp *fillUp = LBFillUp(anna, golf, @"148000");
        LBSave(anna, @"a fill-up saved, sync off");
        LBCheck(@"it waits", [anna pendingCount] > 0 && [anna.status hasPrefix:@"Sync is off"], anna.status);
        anna.syncEnabled = YES;
        LBSync(anna, @"sync on");
        LBCheck(@"it went", [anna pendingCount] == 0, @([anna pendingCount]));
        LBSync(tablet, @"the tablet syncs");
        LBCheck(@"the tablet has the fill-up", LBThere(tablet, [FillUp class], fillUp.id) != nil, nil);

        /* A schedule's reminder closed by a service, here and there alike. */
        Schedule *oil = LBInsert([Schedule class], anna);
        oil.vehicle = golf;
        oil.enteredBy = anna.user;
        oil.task = @"Oil change";
        oil.intervalQuantity = LBNumber(@"15000");
        oil.intervalDistanceUnit = LBFetch([DistanceUnit class], @selector(code), @"km", anna);
        oil.duration = 12;
        oil.id = [NSUUID UUID];
        Reminder *first = [oil lb_startFrom:nil mileage:nil unit:nil by:anna.user at:LBNow() error:&error];
        LBCheck(@"a schedule started", first != nil, error.localizedDescription);
        LBSave(anna, @"saved");
        LBSync(anna, @"synced");
        Service *service = LBInsert([Service class], anna);
        service.vehicle = golf;
        service.enteredBy = anna.user;
        service.driver = anna.user;
        service.timestamp = [LBNow() dateByAddingTimeInterval:60];
        service.mileageQuantity = LBNumber(@"148500");
        service.mileageDistanceUnit = LBFetch([DistanceUnit class], @selector(code), @"km", anna);
        service.garage = @"Garage Müller";
        service.serviceKind = [CostKind lbServiceKindsInContext:anna.context].firstObject;
        service.currency = @"EUR";
        ServiceItem *item = LBInsert([ServiceItem class], anna);
        item.service = service;
        item.task = @"Oil change";
        item.costAmount = LBNumber(@"89.90");
        item.costCurrency = @"EUR";
        LBSave(anna, @"a service of an oil change saved");
        LBCheck(@"the reminder closed by it, here", first.event == service && first.doneAt != nil, first.doneAt);
        NSUUID *nextID = LBNamedUUID([@"next of " stringByAppendingString:first.id.UUIDString.lowercaseString]);
        LBCheck(@"the next made, named by it", first.lb_nextReminder && [first.lb_nextReminder.id isEqual:nextID],
                first.lb_nextReminder.id);
        LBSync(anna, @"synced");
        LBCheck(@"nothing waits, nothing refused", [anna pendingCount] == 0 && anna.issues.count == 0,
                [NSString stringWithFormat:@"%lu waiting, refused: %@", (unsigned long)[anna pendingCount],
                                           LBIssues(anna)]);
        LBCheck(@"no conflict of what the server settled alike", [anna pendingConflicts].count == 0,
                [[anna pendingConflicts] valueForKey:NSStringFromSelector(@selector(properties))]);
        LBSync(tablet, @"the tablet syncs");
        Reminder *firstThere = LBThere(tablet, [Reminder class], first.id);
        LBCheck(@"the tablet has the reminder done by the service", [firstThere.event.id isEqual:service.id] && firstThere.doneAt,
                firstThere.event.id);
        Reminder *nextThere = LBThere(tablet, [Reminder class], nextID);
        LBCheck(@"and the same next, open", nextThere && nextThere.lb_isOpen && [nextThere.schedule.id isEqual:oil.id], nextThere);
        NSUInteger reminders = 0;
        for (Record *record in golfThere.records) reminders += [record isKindOfClass:[Reminder class]] ? 1 : 0;
        LBCheck(@"and no other", reminders == 2, @(reminders));
        LBVehicleSummary *summary = [[LBVehicleSummary alloc] initWithVehicle:golf];
        LBCheck(@"the summary's next due is the next", [[summary nextDue] hasPrefix:@"Oil change: "], [summary nextDue]);
        LBCheck(@"its timeline has the service and the fill-up", [[summary months].firstObject.records count] == 2,
                [summary months].firstObject.records);

        /* Conflicts, each settled its way. */
        LBPendingConflict *conflict = LBConflict(anna, tablet, fillUp.id, @selector(note), @"Anna's note", @"the tablet's note");
        [anna keepTheirs:conflict];
        LBCheck(@"keep theirs: settled, theirs kept", [anna pendingConflicts].count == 0
                    && [((FillUp *)LBThere(anna, [FillUp class], fillUp.id)).note isEqualToString:@"the tablet's note"], nil);

        conflict = LBConflict(anna, tablet, fillUp.id, @selector(station), @"Aral", @"Esso");
        BOOL kept = [anna keepMine:conflict error:&error];
        LBCheck(@"keep mine: written back", kept && [anna pendingConflicts].count == 0
                    && [((FillUp *)LBThere(anna, [FillUp class], fillUp.id)).station isEqualToString:@"Aral"], error);
        LBSync(anna, @"synced");
        LBSync(tablet, @"the tablet syncs");
        LBCheck(@"the tablet has Anna's", [((FillUp *)LBThere(tablet, [FillUp class], fillUp.id)).station isEqualToString:@"Aral"],
                ((FillUp *)LBThere(tablet, [FillUp class], fillUp.id)).station);

        conflict = LBConflict(anna, tablet, fillUp.id, @selector(note), @"Tyres checked", @"Washed");
        FillUp *here = (FillUp *)[anna objectOfConflict:conflict];
        here.note = @"Washed, tyres checked";
        LBSave(anna, @"edited by hand, saved");
        [anna settleConflict:conflict];
        LBSync(anna, @"synced");
        LBSync(tablet, @"the tablet syncs");
        LBCheck(@"settled by hand: the tablet has it", [anna pendingConflicts].count == 0
                    && [((FillUp *)LBThere(tablet, [FillUp class], fillUp.id)).note isEqualToString:@"Washed, tyres checked"],
                ((FillUp *)LBThere(tablet, [FillUp class], fillUp.id)).note);

        /* A receipt's photo: its content synced, through the server. */
        NSData *jpeg = argc > 4 ? [NSData dataWithContentsOfFile:@(argv[4])] : nil;
        LBCheck(@"a photo of a receipt", jpeg.length > 0, argc > 4 ? @(argv[4]) : @"none given");
        if (!jpeg) jpeg = [@"a JPEG's bytes" dataUsingEncoding:NSUTF8StringEncoding];
        Attachment *receipt = [anna attachImage:jpeg toRecord:fillUp];
        LBSave(anna, @"a receipt attached");
        LBSync(anna, @"synced");
        LBCheck(@"it went", [anna pendingCount] == 0 && anna.issues.count == 0, LBIssues(anna));
        LBSync(tablet, @"the tablet syncs");
        Attachment *receiptThere = LBThere(tablet, [Attachment class], receipt.id);
        LBCheck(@"the tablet has the attachment, of the fill-up", [receiptThere.record.id isEqual:fillUp.id]
                    && [receiptThere.fileName isEqualToString:receipt.fileName], receiptThere);
        LBCheck(@"and the photo, byte for byte", [receiptThere.content isEqualToData:jpeg],
                [NSString stringWithFormat:@"%lu bytes of %lu", (unsigned long)receiptThere.content.length, (unsigned long)jpeg.length]);

        /* A rule refuses. */
        FillUp *half = LBFillUp(anna, golf, @"149000");
        half.volumeVolumeUnit = nil;
        BOOL saved = [anna save:&error];
        NSArray *sentences = [LBLocalStore sentencesOfError:error];
        LBCheck(@"a fill-up of a volume without its unit is refused, the rule said", !saved && sentences.count > 0, sentences);
        [anna.context rollback];

        /* Shared: Ben's phone, signed in as him. */
        LBLocalStore *ben = LBDevice(@"ben@example.org");
        LBSync(ben, @"Ben's phone syncs");
        LBCheck(@"he has no vehicle of Anna's: not shared", LBThere(ben, [Vehicle class], golf.id) == nil, nil);
        User *benUser = (User *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([User class])
                                                              inManagedObjectContext:anna.context];
        benUser.email = @"ben@example.org";
        VehicleDriver *sharing = LBInsert([VehicleDriver class], anna);
        sharing.vehicle = golf;
        sharing.user = benUser;
        LBSave(anna, @"Anna shares the Golf with Ben");
        LBSync(anna, @"synced");
        LBCheck(@"it went", [anna pendingCount] == 0 && anna.issues.count == 0, LBIssues(anna));
        LBSync(ben, @"Ben's phone syncs");
        Vehicle *shared = LBThere(ben, [Vehicle class], golf.id);
        LBCheck(@"he has the Golf now, and its fill-up", shared && LBThere(ben, [FillUp class], fillUp.id), nil);
        FillUp *his = LBFillUp(ben, shared, @"149500");
        LBSave(ben, @"he adds a fill-up of it");
        LBSync(ben, @"synced");
        LBCheck(@"it went: whoever drives a vehicle adds records to it", [ben pendingCount] == 0 && ben.issues.count == 0, LBIssues(ben));
        LBSync(anna, @"Anna syncs");
        FillUp *hisThere = LBThere(anna, [FillUp class], his.id);
        LBCheck(@"Anna has it, entered by Ben", [hisThere.enteredBy.email isEqualToString:@"ben@example.org"], hisThere.enteredBy.email);
        FillUp *hers = LBThere(ben, [FillUp class], fillUp.id);
        hers.note = @"Ben's note";
        LBSave(ben, @"he changes Anna's fill-up");
        [ben syncAndWait:NULL];
        LBCheck(@"the server refuses it: only a vehicle's owner changes its records; kept as an issue", ben.issues.count > 0, LBIssues(ben));
        LBSync(anna, @"Anna syncs");
        LBCheck(@"hers stands", ![((FillUp *)LBThere(anna, [FillUp class], fillUp.id)).note isEqualToString:@"Ben's note"], nil);

        printf("sync: %lu failed\n", (unsigned long)LBFailures);
        return LBFailures ? 1 : 0;
    }
}
