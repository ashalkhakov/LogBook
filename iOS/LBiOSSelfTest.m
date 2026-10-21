#import "LBiOSSelfTest.h"
#import "LBDisplay.h"
#import "LBProcedures.h"
#import "LogbookValidation.h"
#import "FillUp+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "Schedule+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"

NSURL *LBSelfTestRoot;

static int LBFailed;

static void LBSay(BOOL ok, NSString *what) {
    fprintf(stderr, "%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    if (!ok) LBFailed++;
}

/* The run loop let turn, as between a user's taps. */
static void LBSpin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

/* A sync begun by the app (a switch, a save) run to its end. */
static void LBSettle(LBLocalStore *store) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:60];
    LBSpin(2.5);
    while (store.isSyncing && [until timeIntervalSinceNow] > 0) LBSpin(0.1);
}

static BOOL LBSync(LBLocalStore *store, NSString *what) {
    NSError *error = nil;
    BOOL ok = [store syncAndWait:&error];
    LBSay(ok, error ? [NSString stringWithFormat:@"%@: %@", what, error.localizedDescription] : what);
    return ok;
}

/* The server asked over HTTP, as any client: what it has. */
static NSInteger LBAsk(NSString *method, NSString *path, NSDictionary *body, id *json) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path relativeToURL:LBSelfTestRoot]];
    request.HTTPMethod = method;
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (body) {
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    }
    __block NSInteger status = 0;
    __block NSData *answer = nil;
    __block BOOL done = NO;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        status = [(NSHTTPURLResponse *)response statusCode];
        answer = data;
        done = YES;
    }] resume];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done && [until timeIntervalSinceNow] > 0) LBSpin(0.05);
    if (json) *json = answer.length ? [NSJSONSerialization JSONObjectWithData:answer options:0 error:NULL] : nil;
    return status;
}

static NSDictionary *LBServerHas(NSString *path) {
    id json = nil;
    return LBAsk(@"GET", path, nil, &json) == 200 && [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

static NSString *LBKey(NSUUID *uuid) {
    return uuid.UUIDString.lowercaseString;
}

/* Edm.Binary as OData's JSON writes it: base64url, unpadded. */
static NSData *LBDataOfBase64URL(NSString *text) {
    NSMutableString *base64 = [[[text stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                                   stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    while (base64.length % 4) [base64 appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

/* An object of the store by its id. */
static id LBFetchID(LBLocalStore *store, Class cls, NSUUID *uuid) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(id)), uuid];
    return [[store.context executeFetchRequest:fetch error:NULL] firstObject];
}

/* A phone's photo of a receipt, 3024 by 4032 (Tests/receipt-photo.jpg, in
   the simulator's app). */
static UIImage *LBReceiptPhoto(void) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"SelfTestReceipt" ofType:@"jpg"];
    return path ? [UIImage imageWithContentsOfFile:path] : nil;
}

@interface LBSelfTest : NSObject
@property (nonatomic, strong) LBiOSAppDelegate *app;
@end

@implementation LBSelfTest

/* An exception is a failure, not a hang. */
- (void)fire:(NSTimer *)timer {
    @try {
        [self run];
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL %s: %s\nFAIL   %s\nself-test: FAILED\n", e.name.UTF8String, e.reason.UTF8String,
                [e.callStackSymbols componentsJoinedByString:@"\nFAIL   "].UTF8String);
        exit(1);
    }
    /* The app as it was: the self-test's server and email not kept. */
    for (NSString *key in @[ LBServerDefaultsKey, LBEmailDefaultsKey, LBVehicleDefaultsKey ])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    fprintf(stderr, "self-test: %s (%d failed)\n", LBFailed ? "FAILED" : "passed", LBFailed);
    exit(LBFailed);
}

/* The form the + (or another) presented, once it shows. */
- (LBRecordFormViewController *)presentedFormOver:(UIViewController *)controller {
    LBSpin(0.8);
    UINavigationController *navigation = (UINavigationController *)controller.presentedViewController;
    id form = [navigation isKindOfClass:[UINavigationController class]] ? navigation.viewControllers.firstObject : nil;
    return [form isKindOfClass:[LBRecordFormViewController class]] ? form : nil;
}

/* A field of the fill-up changed here, with sync off, and another way at
   the server; sync on: the server's stands, this side's a pending
   conflict. */
- (LBPendingConflict *)conflictOn:(FillUp *)fillUp field:(NSString *)title wire:(NSString *)wire mine:(NSString *)mine theirs:(NSString *)theirs
                          vehicle:(LBVehicleViewController *)vehicle {
    LBiOSAppDelegate *app = self.app;
    [vehicle setSyncOn:NO];
    LBRecordFormViewController *form = [[LBRecordFormViewController alloc] initWithObject:fillUp phone:app.phone];
    [form enter:mine intoField:title];
    LBSay([form saveIgnoringWarnings:YES], [NSString stringWithFormat:@"%@ changed here, offline", title]);
    NSInteger status = LBAsk(@"PATCH", [NSString stringWithFormat:@"Records(%@)", LBKey(fillUp.id)],
                             @{ @"@odata.type": @"#Default.FillUp", wire: theirs }, NULL);
    LBSay(status >= 200 && status < 300, [NSString stringWithFormat:@"and at the server (%ld)", (long)status]);
    [vehicle setSyncOn:YES];
    LBSettle(app.store);
    [app.store.context refreshObject:fillUp mergeChanges:YES];
    NSString *now = [fillUp valueForKey:wire.lowercaseString];
    LBSay([now isEqualToString:theirs], [NSString stringWithFormat:@"the server's %@ stands (%@)", title, now]);
    NSArray<LBPendingConflict *> *pending = [app.store pendingConflicts];
    LBSay(pending.count == 1, [NSString stringWithFormat:@"a pending conflict (%lu)", (unsigned long)pending.count]);
    LBSay([app.mainController.viewControllers.lastObject.tabBarItem.badgeValue isEqualToString:@"1"], @"the Vehicle tab's badge says so");
    LBConflictsViewController *conflicts = [[LBConflictsViewController alloc] initWithPhone:app.phone];
    NSString *expected = [NSString stringWithFormat:@"Fill-up: %@ — mine %@, theirs %@", wire.lowercaseString, mine, theirs];
    LBSay([[conflicts shownRows] containsObject:expected],
          [NSString stringWithFormat:@"it shows mine and theirs (%@)", [[conflicts shownRows] componentsJoinedByString:@"; "]]);
    return pending.firstObject;
}

- (void)run {
    LBiOSAppDelegate *app = self.app;

    /* Signed in: a server with no sign-in, as the user's email. */
    LBSignInViewController *signIn = app.signInController;
    LBSay(signIn != nil, @"the sign-in shows first");
    signIn.serverText = LBSelfTestRoot.absoluteString;
    signIn.emailText = @"Anna@Example.org";
    [signIn connect:nil];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!app.mainController && [until timeIntervalSinceNow] > 0) LBSpin(0.1);
    LBMainViewController *main = app.mainController;
    LBSay(main != nil, [NSString stringWithFormat:@"signed in, with no sign-in, as an email (%@)", signIn.status]);
    if (!main) return;
    LBLocalStore *store = app.store;
    LBSettle(store);
    LBSync(store, @"the first sync");
    LBSay([store.user.email isEqualToString:@"anna@example.org"], @"the user is the email's");
    NSFetchRequest *units = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([DistanceUnit class])];
    LBSay([store.context countForFetchRequest:units error:NULL] >= 2, @"the units came down");

    /* A vehicle added: the owner's. */
    LBVehicleViewController *vehicleTab = (LBVehicleViewController *)((UINavigationController *)main.viewControllers[2]).topViewController;
    main.selectedIndex = 2;
    LBSay(![[vehicleTab shownSections] containsObject:@"Sharing"], @"no vehicle: nothing to share");
    [vehicleTab addVehicle:nil];
    LBRecordFormViewController *form = [self presentedFormOver:vehicleTab];
    LBSay(form != nil, @"Add a Vehicle shows its form");
    [form enter:@"Golf" intoField:@"Name"];
    [form enter:@"Volkswagen" intoField:@"Make"];
    [form enter:@"Golf VII" intoField:@"Model"];
    [form enter:@"2016" intoField:@"Year"];
    [form save:nil];
    LBSpin(1);
    Vehicle *golf = app.phone.vehicle;
    LBSay([golf.vehicleName isEqualToString:@"Golf"] && golf.owner == store.user && !vehicleTab.presentedViewController,
          @"saved, chosen, the user's");
    LBSay([vehicleTab showsSharing] && [[vehicleTab shownSections] containsObject:@"Sharing"], @"its owner is offered sharing");

    /* A fill-up, offline: first and fastest. */
    LBSay([[LBMainViewController loggedKinds].firstObject isEqualToString:@"FillUp"], @"the + offers a fill-up first");
    [vehicleTab setSyncOn:NO];
    main.selectedIndex = 0;
    form = (LBRecordFormViewController *)[main logKind:@"FillUp"];
    LBSpin(0.8);
    LBSay([[form fieldTitles] isEqualToArray:@[ @"When", @"Odometer", @"Volume", @"Cost", @"Full tank", @"Station", @"Note" ]],
          [NSString stringWithFormat:@"its form: %@", [[form fieldTitles] componentsJoinedByString:@", "]]);
    [form enter:@"148000" intoField:@"Odometer"];
    [form enter:@"40.5" intoField:@"Volume"];
    [form enter:@"68.40" intoField:@"Cost"];
    [form enter:@"Shell" intoField:@"Station"];
    [form save:nil];
    LBSpin(1);
    FillUp *fillUp = (FillUp *)form.object;
    LBSay(!main.presentedViewController && !fillUp.isInserted && fillUp.managedObjectContext,
          [NSString stringWithFormat:@"saved, offline (%@)", [form.problems componentsJoinedByString:@"; "]]);
    LBSay([fillUp.mileageDistanceUnit.code isEqualToString:@"km"] && [fillUp.volumeVolumeUnit.code isEqualToString:@"L"]
              && [fillUp.totalCurrency isEqualToString:@"EUR"] && fillUp.driver == store.user,
          @"in the user's units, by the user, now");
    LBTimelineViewController *timeline = (LBTimelineViewController *)((UINavigationController *)main.viewControllers[0]).topViewController;
    LBSay([[timeline shownRows].firstObject hasSuffix:@": Fill-up"], [NSString stringWithFormat:@"the timeline has it (%@)", [timeline shownRows]]);
    LBSay([store pendingCount] > 0 && [store.status hasPrefix:@"Sync is off"], [NSString stringWithFormat:@"it waits (%@)", store.status]);
    LBSay(!LBServerHas([NSString stringWithFormat:@"Records(%@)", LBKey(fillUp.id)]), @"the server has none of it yet");
    [vehicleTab setSyncOn:YES];
    LBSettle(store);
    NSDictionary *there = LBServerHas([NSString stringWithFormat:@"Records(%@)", LBKey(fillUp.id)]);
    LBSay([there[@"@odata.type"] hasSuffix:@"FillUp"] && [there[@"Station"] isEqual:@"Shell"] && [store pendingCount] == 0,
          [NSString stringWithFormat:@"sync on: it reached the server (%@, %lu waiting)", there[@"Station"], (unsigned long)[store pendingCount]]);

    /* A schedule's reminder closed by a service: here, and the server agrees. */
    Schedule *oil = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Schedule class]) inManagedObjectContext:store.context];
    oil.vehicle = golf;
    oil.enteredBy = store.user;
    oil.task = @"Oil change";
    oil.intervalQuantity = [NSDecimalNumber decimalNumberWithString:@"15000"];
    oil.intervalDistanceUnit = fillUp.mileageDistanceUnit;
    oil.duration = 12;
    oil.id = [NSUUID UUID];
    NSError *error = nil;
    Reminder *first = [oil lb_startFrom:nil mileage:nil unit:nil by:store.user at:LBNow() error:&error];
    LBSay(first && [store save:&error], [NSString stringWithFormat:@"an oil change every 15000 km or 12 months (%@)", error.localizedDescription]);
    LBSync(store, @"synced");
    LBSpin(1);
    form = (LBRecordFormViewController *)[main logKind:@"Service"];
    LBSpin(0.8);
    [form enter:@"Garage Müller" intoField:@"Garage"];
    [form enter:@"148500" intoField:@"Odometer"];
    [form addItemTask:@"Oil change" cost:[NSDecimalNumber decimalNumberWithString:@"89.90"]];
    LBSay([form saveIgnoringWarnings:YES], [NSString stringWithFormat:@"a service of an oil change saved (%@)", [form.problems componentsJoinedByString:@"; "]]);
    [main dismissViewControllerAnimated:NO completion:nil];
    Service *service = (Service *)form.object;
    LBSay(first.event == service && first.doneAt, @"the reminder closed by it, on the phone");
    NSUUID *nextID = LBNamedUUID([@"next of " stringByAppendingString:LBKey(first.id)]);
    LBSay([first.lb_nextReminder.id isEqual:nextID] && first.lb_nextReminder.lb_isOpen, @"the next made, named by it");
    LBRemindersViewController *reminders = (LBRemindersViewController *)((UINavigationController *)main.viewControllers[1]).topViewController;
    main.selectedIndex = 1;
    LBSpin(0.5);
    NSArray *rows = [reminders shownRows];
    LBSay(rows.count == 2 && [rows[0] isEqual:@"Oil change — Open"] && [rows[1] hasPrefix:@"Oil change — Done"] && [rows[1] hasSuffix:@"by Service"],
          [NSString stringWithFormat:@"Reminders: the open first, the done by what (%@)", [rows componentsJoinedByString:@"; "]]);
    LBSync(store, @"synced");
    NSDictionary *closed = LBServerHas([NSString stringWithFormat:@"Records(%@)/Default.Reminder/Event", LBKey(first.id)]);
    LBSay([[closed[@"Id"] lowercaseString] isEqual:LBKey(service.id)], [NSString stringWithFormat:@"the server has it closed by the service (%@)", closed[@"Id"]]);
    NSDictionary *next = LBServerHas([NSString stringWithFormat:@"Records(%@)", LBKey(nextID)]);
    LBSay(next != nil && next[@"DoneAt"] == [NSNull null], @"and the same next reminder, open, by its id");
    LBSay([store pendingCount] == 0 && store.issues.count == 0 && [store pendingConflicts].count == 0,
          @"nothing waits, nothing refused, no conflict of what both made alike");

    /* Moved to another day. */
    NSArray *problems = nil;
    Reminder *open = [reminders shownReminders].firstObject;
    NSDate *later = [open.dueDate dateByAddingTimeInterval:30 * 86400];
    LBSay([reminders reschedule:open toDate:later mileage:nil note:@"away" problems:&problems] && [open.dueDate isEqual:later],
          [NSString stringWithFormat:@"a reminder moved (%@)", [problems componentsJoinedByString:@"; "]]);

    /* Conflicts, each settled its way. */
    main.selectedIndex = 2;
    LBPendingConflict *conflict = [self conflictOn:fillUp field:@"Station" wire:@"Station" mine:@"Aral" theirs:@"Esso" vehicle:vehicleTab];
    LBConflictsViewController *conflicts = [[LBConflictsViewController alloc] initWithPhone:app.phone];
    [conflicts keepTheirs:conflict];
    LBSay([store pendingConflicts].count == 0 && [fillUp.station isEqualToString:@"Esso"], @"keep theirs: theirs it is");
    conflict = [self conflictOn:fillUp field:@"Note" wire:@"Note" mine:@"Tyres checked" theirs:@"Washed" vehicle:vehicleTab];
    LBSay([conflicts keepMine:conflict problems:&problems] && [fillUp.note isEqualToString:@"Tyres checked"],
          [NSString stringWithFormat:@"keep mine: mine written back (%@)", [problems componentsJoinedByString:@"; "]]);
    LBSettle(store);
    LBSay([LBServerHas([NSString stringWithFormat:@"Records(%@)", LBKey(fillUp.id)])[@"Note"] isEqual:@"Tyres checked"],
          @"and the server has mine");
    conflict = [self conflictOn:fillUp field:@"Station" wire:@"Station" mine:@"Aral" theirs:@"Total" vehicle:vehicleTab];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:conflicts];
    form = [conflicts editByHand:conflict];
    [form enter:@"Total, pump 4" intoField:@"Station"];
    LBSay([form saveIgnoringWarnings:YES] && [store pendingConflicts].count == 0, @"edited by hand: saved, settled");
    LBSettle(store);
    LBSay([LBServerHas([NSString stringWithFormat:@"Records(%@)", LBKey(fillUp.id)])[@"Station"] isEqual:@"Total, pump 4"],
          @"and the server has it");
    (void)navigation;

    /* A receipt's photo, as one taken: kept smaller, synced with its record. */
    UIImage *photo = LBReceiptPhoto();
    LBSay(photo.size.width == 3024 && photo.size.height == 4032, @"a photo of a receipt, 3024 by 4032");
    form = [[LBRecordFormViewController alloc] initWithObject:fillUp phone:app.phone];
    [form imagePickerController:nil didFinishPickingMediaWithInfo:@{ UIImagePickerControllerOriginalImage: photo ?: [[UIImage alloc] init] }];
    LBSay([form saveIgnoringWarnings:YES], @"a receipt's photo attached");
    LBSettle(store);
    Attachment *receipt = fillUp.attachments.anyObject;
    UIImage *kept = receipt.content ? [UIImage imageWithData:receipt.content] : nil;
    LBSay(kept && MAX(kept.size.width * kept.scale, kept.size.height * kept.scale) == LBPhotoLongestSide
              && [receipt.fileName hasSuffix:@".jpg"],
          [NSString stringWithFormat:@"kept as a JPEG of %.0f by %.0f, %lu KB", kept.size.width * kept.scale, kept.size.height * kept.scale,
                                     (unsigned long)receipt.content.length / 1024]);
    NSDictionary *attached = LBServerHas([NSString stringWithFormat:@"Attachments(%@)", LBKey(receipt.id)]);
    NSData *served = [attached[@"Content"] isKindOfClass:[NSString class]] ? LBDataOfBase64URL(attached[@"Content"]) : nil;
    LBSay([served isEqualToData:receipt.content] && [store pendingCount] == 0,
          [NSString stringWithFormat:@"synced: the server has the photo (%lu bytes)", (unsigned long)served.length]);

    /* Shared by its owner; a driver is offered no sharing. */
    LBSay([vehicleTab shareWithEmail:@"Ben@Example.org" problems:&problems],
          [NSString stringWithFormat:@"shared with Ben by email (%@)", [problems componentsJoinedByString:@"; "]]);
    LBSettle(store);
    NSDictionary *drivers = LBServerHas(@"VehicleDrivers?$expand=User");
    NSArray *value = drivers[@"value"];
    LBSay(value.count == 1 && [value.firstObject[@"User"][@"Email"] isEqual:@"ben@example.org"], @"the server has Ben driving it");
    NSURL *bens = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                              [NSString stringWithFormat:@"lb-selftest-ben-%@", [NSProcessInfo processInfo].globallyUniqueString]]
                             isDirectory:YES];
    LBLocalStore *benStore = [[LBLocalStore alloc] initWithDirectory:bens modelURL:nil error:&error];
    benStore.email = @"ben@example.org";
    benStore.serviceRoot = LBSelfTestRoot;
    LBSync(benStore, @"Ben's phone syncs");
    LBPhone *benPhone = [[LBPhone alloc] initWithStore:benStore];
    LBSay([[[benPhone vehicles] valueForKey:NSStringFromSelector(@selector(vehicleName))] containsObject:@"Golf"], @"Ben has the Golf, shared");
    Attachment *receiptThere = LBFetchID(benStore, [Attachment class], receipt.id);
    LBSay(receiptThere.content.length > 0 && [receiptThere.content isEqualToData:receipt.content], @"and the receipt's photo, on his phone");
    LBVehicleViewController *benVehicle = [[LBVehicleViewController alloc] initWithPhone:benPhone];
    LBSay(![benVehicle showsSharing] && ![[benVehicle shownSections] containsObject:@"Sharing"],
          [NSString stringWithFormat:@"a driver is offered no sharing (%@)", [[benVehicle shownSections] componentsJoinedByString:@", "]]);

    /* What ought not to be, said before saving; what may not be, refused. */
    form = [[LBRecordFormViewController alloc] initWithObject:[LBRecordFormViewController newRecordOfKind:@"FillUp" phone:app.phone] phone:app.phone];
    [form enter:@"1000" intoField:@"Odometer"];
    [form enter:@"30" intoField:@"Volume"];
    [form enter:@"50" intoField:@"Cost"];
    LBSay(![form saveIgnoringWarnings:NO] && form.warnings.count > 0 && !form.problems.count,
          [NSString stringWithFormat:@"the meter going down: said before saving (%@)", [form.warnings componentsJoinedByString:@"; "]]);
    [form enter:@"" intoField:@"Volume"];
    [form enter:@"148900" intoField:@"Odometer"];
    LBSay(![form saveIgnoringWarnings:YES] && form.problems.count > 0,
          [NSString stringWithFormat:@"a fill-up of no volume: refused, the rule said (%@)", [form.problems componentsJoinedByString:@"; "]]);
    [store.context rollback];
}

@end

void LBStartSelfTest(LBiOSAppDelegate *app) {
    LBSelfTest *test = [[LBSelfTest alloc] init];
    test.app = app;
    [NSTimer scheduledTimerWithTimeInterval:1 target:test selector:@selector(fire:) userInfo:nil repeats:NO];
}
