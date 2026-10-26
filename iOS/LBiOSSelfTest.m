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
/* The stock steps' bolt, shelf and catalog: the parts steps' too. */
@property (nonatomic, copy) NSUUID *boltID;
@property (nonatomic, copy) NSUUID *shelfID;
@property (nonatomic, copy) NSUUID *catalogID;
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
    for (NSString *key in @[ LBServerDefaultsKey, LBEmailDefaultsKey, LBVehicleDefaultsKey, LBModeDefaultsKey, LBCatalogDefaultsKey ])
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    fprintf(stderr, "self-test: %s (%d failed)\n", LBFailed ? "FAILED" : "passed", LBFailed);
    exit(LBFailed);
}

/* Signed in by email to the self-test's server, as a user does: the
   logbook once it shows, synced. */
- (LBMainViewController *)signInAs:(NSString *)email {
    LBiOSAppDelegate *app = self.app;
    LBSignInViewController *signIn = app.signInController;
    signIn.serverText = LBSelfTestRoot.absoluteString;
    signIn.emailText = email;
    [signIn connect:nil];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!app.mainController && [until timeIntervalSinceNow] > 0) LBSpin(0.1);
    if (app.mainController) {
        LBSettle(app.store);
        [app.store syncAndWait:NULL];
        app.mainController.selectedIndex = 2;
        LBSpin(0.5);
    }
    return app.mainController;
}

- (LBVehicleViewController *)vehicleTabOf:(LBMainViewController *)main {
    return (LBVehicleViewController *)((UINavigationController *)main.viewControllers[2]).topViewController;
}

/* Signing out with changes waiting: warned, how many said, conflicts
   among them; each button does what it says. */
- (void)signOutSteps:(FillUp *)fillUp {
    LBiOSAppDelegate *app = self.app;
    LBLocalStore *store = app.store;
    LBMainViewController *main = app.mainController;
    LBVehicleViewController *vehicleTab = [self vehicleTabOf:main];
    main.selectedIndex = 2;
    LBSpin(0.5);
    [vehicleTab setSyncOn:NO];
    fillUp.note = @"Before signing out";
    NSError *error = nil;
    LBSay([store save:&error], [NSString stringWithFormat:@"a change saved, sync off (%@)", error.localizedDescription]);
    [store.appState recordConflictOfEntity:NSStringFromClass([FillUp class]) key:@{ NSStringFromSelector(@selector(id)): fillUp.id }
                                properties:@[ NSStringFromSelector(@selector(station)) ]
                                      mine:@{ NSStringFromSelector(@selector(station)): @"Aral" }
                                    theirs:@{ NSStringFromSelector(@selector(station)): fillUp.station ?: @"" }
                              deletedThere:NO deletedHere:NO];
    UIAlertController *warning = [vehicleTab signOutWarning];
    NSArray *buttons = [warning.actions valueForKey:NSStringFromSelector(@selector(title))];
    LBSay([warning.message hasPrefix:@"1 change not sent to the server yet and 1 conflict not settled would be lost"]
              && [warning.title isEqualToString:@"2 Changes Would Be Lost"],
          [NSString stringWithFormat:@"the warning says what would be lost (%@: %@)", warning.title, warning.message]);
    LBSay([buttons isEqualToArray:(@[ @"Sync Now", @"Sign Out Anyway", @"Cancel" ])]
              && warning.actions[1].style == UIAlertActionStyleDestructive && warning.actions[2].style == UIAlertActionStyleCancel,
          [NSString stringWithFormat:@"its buttons: %@", [buttons componentsJoinedByString:@", "]]);
    [vehicleTab signOut:nil];
    LBSpin(0.8);
    LBSay([vehicleTab.presentedViewController isKindOfClass:[UIAlertController class]], @"Sign Out warns first");
    [vehicleTab dismissViewControllerAnimated:NO completion:nil];
    [vehicleTab signOutChoosing:LBSignOutCancel];
    LBSpin(0.5);
    LBSay(app.mainController == main && [store pendingCount] > 0, @"Cancel: still signed in, the change waiting");

    /* Sync Now: synced; the conflict is still to lose, so said again. */
    [vehicleTab signOutChoosing:LBSignOutSyncFirst];
    LBSettle(store);
    LBSpin(0.5);
    UIAlertController *again = (UIAlertController *)vehicleTab.presentedViewController;
    LBSay(app.mainController == main && [store pendingCount] == 0
              && [LBServerHas([NSString stringWithFormat:@"Records(%@)", LBKey(fillUp.id)])[@"Note"] isEqual:@"Before signing out"],
          @"Sync Now: synced, with sync off");
    LBSay([again isKindOfClass:[UIAlertController class]] && [again.message hasPrefix:@"1 conflict not settled"],
          [NSString stringWithFormat:@"the conflict left to lose: warned again (%@)",
                                     [again isKindOfClass:[UIAlertController class]] ? again.message : again]);
    [vehicleTab dismissViewControllerAnimated:NO completion:nil];
    [store keepTheirs:[store pendingConflicts].firstObject];
    fillUp.note = @"Synced, then signed out";
    LBSay([store save:&error] && [store changesLostOnSignOut] == 1, @"the conflict settled; another change waiting");
    [vehicleTab signOutChoosing:LBSignOutSyncFirst];
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:60];
    while (app.mainController && [until timeIntervalSinceNow] > 0) LBSpin(0.1);
    LBSay(!app.mainController && app.signInController
              && [LBServerHas([NSString stringWithFormat:@"Records(%@)", LBKey(fillUp.id)])[@"Note"] isEqual:@"Synced, then signed out"],
          @"Sync Now: synced, then signed out");

    /* Nothing waiting: signed out at once. */
    main = [self signInAs:@"anna@example.org"];
    LBSay(main != nil && LBFetchID(app.store, [FillUp class], fillUp.id) != nil, @"signed in again: the logbook back from the server");
    if (!main) return;
    vehicleTab = [self vehicleTabOf:main];
    LBSay(![vehicleTab signOutWarning], @"nothing waiting: no warning");
    [vehicleTab signOut:nil];
    LBSpin(0.5);
    LBSay(!app.mainController && app.signInController, @"signed out at once");

    /* Sign Out Anyway: what waits is lost. */
    main = [self signInAs:@"anna@example.org"];
    if (!main) return;
    vehicleTab = [self vehicleTabOf:main];
    [vehicleTab setSyncOn:NO];
    FillUp *here = LBFetchID(app.store, [FillUp class], fillUp.id);
    here.note = @"Never sent";
    LBSay([app.store save:&error] && [vehicleTab signOutWarning] != nil, @"a change waiting: warned");
    [vehicleTab signOutChoosing:LBSignOutAnyway];
    LBSpin(0.5);
    LBSay(!app.mainController && app.signInController
              && [LBServerHas([NSString stringWithFormat:@"Records(%@)", LBKey(fillUp.id)])[@"Note"] isEqual:@"Synced, then signed out"],
          @"Sign Out Anyway: signed out, the change lost with the phone's logbook");
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
    LBSay(fillUp.mileageDistanceUnit && fillUp.mileageDistanceUnit == store.user.distanceUnit
              && fillUp.volumeVolumeUnit && fillUp.volumeVolumeUnit == store.user.volumeUnit
              && store.user.currency.length && [fillUp.totalCurrency isEqualToString:store.user.currency] && fillUp.driver == store.user,
          [NSString stringWithFormat:@"in the user's units and currency, the phone's taken at the first sync (%@), by the user, now",
                                     fillUp.totalCurrency]);
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

    [self stockSteps];
    [self signOutSteps:fillUp];
    [self partsSteps];
}

static BOOL LBSame(id number, NSString *value) {
    if (!number || number == [NSNull null]) return NO;
    return [[NSDecimalNumber decimalNumberWithString:[number description]] compare:[NSDecimalNumber decimalNumberWithString:value]] == NSOrderedSame;
}

/* Stock on the phone (docs/STOCK.md): a catalog set up here as the desktop
   would (its warehouse Main and Default; Shelf A; a customer, Bob), and
   synced; then, in stock's tabs, as a user: an item added and priced, 20
   brought in, 5 moved to Shelf A; a sale of 3 shipped from Shelf A, a line
   then the rest; Default counted, one short; the overview. Synced: the
   server agrees. The logbook again. */
- (void)stockSteps {
    LBiOSAppDelegate *app = self.app;
    LBLocalStore *store = app.store;
    NSManagedObjectContext *context = store.context;
    NSError *error = nil;
    Catalog *catalog = [Catalog lb_newCatalogNamed:@"Phone Workshop" owner:store.user inContext:context];
    catalog.currency = @"USD";
    catalog.documentPrefix = @"PH";
    Warehouse *main = catalog.warehouses.anyObject;
    Location *defaultPlace = main.locations.anyObject;
    Location *shelf = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Location class]) inManagedObjectContext:context];
    shelf.id = [NSUUID UUID];
    shelf.locationName = @"Shelf A";
    shelf.warehouse = main;
    LBSay([store save:&error], [NSString stringWithFormat:@"a catalog set up, as the desktop would (%@)", error.localizedDescription]);
    LBSync(store, @"synced");
    LBSay(LBServerHas([NSString stringWithFormat:@"Catalogs(%@)", LBKey(catalog.id)]) != nil, @"the server has the catalog");
    /* Its customer, Bob, made at the server, as the desktop makes one: a
       contact and its customer, which refer to each other. */
    NSUUID *bobID = [NSUUID UUID], *customerID = [NSUUID UUID];
    NSString *ofCatalog = [NSString stringWithFormat:@"Catalogs(%@)", LBKey(catalog.id)];
    NSInteger made = LBAsk(@"POST", @"Contacts", @{ @"Id": LBKey(bobID), @"ContactName": @"Bob's Garage", @"IsACompany": @YES,
                                                    @"Catalog@odata.bind": ofCatalog }, NULL);
    NSInteger madeCustomer = LBAsk(@"POST", @"Customers", @{ @"Id": LBKey(customerID), @"Catalog@odata.bind": ofCatalog,
                                                             @"Contact@odata.bind": [NSString stringWithFormat:@"Contacts(%@)", LBKey(bobID)] }, NULL);
    LBSay(made == 201 && madeCustomer == 201, [NSString stringWithFormat:@"a customer, Bob, made at the server (%ld, %ld)", (long)made, (long)madeCustomer]);
    LBSync(store, @"synced: Bob comes down");
    Contact *bob = LBFetchID(store, [Contact class], bobID);
    LBSay(bob.customer != nil, @"the phone has Bob, a customer");

    [app showStock:nil];
    LBStockTabBarController *tabs = app.stockController;
    NSArray *titles = [tabs.viewControllers valueForKeyPath:@"tabBarItem.title"];
    LBSay(tabs && app.window.rootViewController == tabs && [titles isEqualToArray:@[ @"Items", @"Orders", @"Overview", @"Settings" ]],
          [NSString stringWithFormat:@"stock shown in place of the logbook: %@", [titles componentsJoinedByString:@", "]]);
    LBSay([[[NSUserDefaults standardUserDefaults] stringForKey:LBModeDefaultsKey] isEqualToString:@"stock"], @"and kept so for the next launch");
    tabs.selectedIndex = 0;
    LBSpin(0.5);
    LBStockItemsViewController *items = [tabs tabNamed:@"Items"];
    LBStockItemViewController *card = [items addItem];
    LBSay([card.item.sku isEqualToString:@"PH-00001"], [NSString stringWithFormat:@"a new item, its SKU the catalog's next (%@)", card.item.sku]);
    [card enter:@"Bolt" intoField:@"Name"];
    [card enter:@"0.5" intoField:@"Price"];
    NSArray *problems = nil;
    LBSay([card saveProblems:&problems] && [card.item.priceCurrency isEqualToString:@"USD"],
          [NSString stringWithFormat:@"named, priced and saved, in the catalog's currency (%@)", [problems componentsJoinedByString:@"; "]]);
    StockItem *bolt = card.item;
    LBSay([card adjust:@"20" at:defaultPlace reason:@"Opening" problems:&problems] && [[card quantityRows].firstObject isEqualToString:@"On hand: 20"],
          [NSString stringWithFormat:@"20 brought in at Default (%@)", [problems componentsJoinedByString:@"; "] ?: [card quantityRows].firstObject]);
    LBSay([card transfer:@"5" from:defaultPlace to:shelf problems:&problems]
              && [[card holdingRows] isEqualToArray:@[ @"Main / Default: 15", @"Main / Shelf A: 5" ]],
          [NSString stringWithFormat:@"5 moved to Shelf A (%@)", [[card holdingRows] componentsJoinedByString:@"; "]]);
    LBSay(![card adjust:@"-30" at:defaultPlace reason:@"Lost" problems:&problems] && [[problems componentsJoinedByString:@" "] containsString:@"15"],
          [NSString stringWithFormat:@"30 lost of the 15 there: refused, in the procedure's words (%@)", [problems componentsJoinedByString:@"; "]]);
    LBSpin(0.5);
    LBSay([[items shownRows] isEqualToArray:@[ @"PH-00001 Bolt: 20" ]], [NSString stringWithFormat:@"the items list it (%@)", [items shownRows]]);

    SaleOrder *sale = [catalog lb_newSaleOrderTo:bob.customer on:LBNow()];
    SaleLine *line = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([SaleLine class]) inManagedObjectContext:context];
    line.id = [NSUUID UUID];
    line.saleOrder = sale;
    line.stockItem = bolt;
    line.quantity = [NSDecimalNumber decimalNumberWithString:@"3"];
    line.linePriceAmount = bolt.priceAmount;
    line.linePriceCurrency = bolt.priceCurrency;
    LBSay([sale lb_confirm:&error] && [store save:&error], [NSString stringWithFormat:@"a sale of 3 bolts to Bob, confirmed (%@)", error.localizedDescription]);
    tabs.selectedIndex = 1;
    LBSpin(0.5);
    LBStockOrdersViewController *orders = [tabs tabNamed:@"Orders"];
    LBSay([[orders shownRows] containsObject:@"SO-PH-0001 Bob's Garage: Confirmed"], [NSString stringWithFormat:@"Orders lists it (%@)", [orders shownRows]]);
    LBStockOrderViewController *order = [orders openOrder:sale];
    order.moveAt = shelf;
    LBSay([order moveLine:order.lines.firstObject quantity:@"2" problems:&problems] && [[order lineRows].firstObject isEqualToString:@"Bolt: 3, shipped 2"],
          [NSString stringWithFormat:@"2 of its line shipped from Shelf A (%@)", [problems componentsJoinedByString:@"; "] ?: [order lineRows].firstObject]);
    LBSay([order moveAllProblems:&problems] && [sale.lbFilled isEqualToString:@"Shipped"] && sale.shipments.count == 2,
          [NSString stringWithFormat:@"the rest shipped: fully, in two shipments (%@)", [problems componentsJoinedByString:@"; "] ?: sale.lbFilled]);

    tabs.selectedIndex = 2;
    LBSpin(0.5);
    LBStockOverviewViewController *overview = [tabs tabNamed:@"Overview"];
    LBStockCountViewController *counting = [overview beginCount];
    for (LBCountPlace *place in [app.stockController.phone countPlaces]) {
        if (place.location == defaultPlace) counting.countPlace = place;
    }
    LBPhoneCountRow *row = counting.rows.firstObject;
    LBSay(counting.rows.count == 1 && row.item == bolt && LBSame(row.expected, @"15"),
          [NSString stringWithFormat:@"a count of Default: the bolts held there, 15 (%lu rows)", (unsigned long)counting.rows.count]);
    row.found = @"14";
    StockCount *count = [counting postProblems:&problems];
    LBSay(count && [count.lbNumber isEqualToString:@"CT-PH-0001"] && LBSame(bolt.totalQuantity, @"16"),
          [NSString stringWithFormat:@"posted, one short: CT-PH-0001, 16 on hand (%@)", [problems componentsJoinedByString:@"; "] ?: bolt.totalQuantity]);
    LBSpin(0.5);
    NSArray *figures = [overview figureRows];
    LBSay([figures containsObject:@"Items: 1"] && [figures containsObject:@"On hand: 16"] && [figures containsObject:@"Value at price: 8 USD"],
          [NSString stringWithFormat:@"the overview (%@)", [figures componentsJoinedByString:@"; "]]);

    LBSync(store, @"stock synced");
    NSDictionary *boltThere = LBServerHas([NSString stringWithFormat:@"StockItems(%@)", LBKey(bolt.id)]);
    NSDictionary *shipments = LBServerHas([NSString stringWithFormat:@"SaleOrders(%@)/Shipments", LBKey(sale.id)]);
    NSDictionary *counts = LBServerHas([NSString stringWithFormat:@"StockCounts(%@)", LBKey(count.id)]);
    LBSay(LBSame(boltThere[@"TotalQuantity"], @"16") && [shipments[@"value"] count] == 2 && counts != nil,
          [NSString stringWithFormat:@"the server has it all: 16 bolts, two shipments, the count (%@)", boltThere[@"TotalQuantity"]]);
    LBSay([store pendingCount] == 0 && store.issues.count == 0 && [store pendingConflicts].count == 0,
          [NSString stringWithFormat:@"nothing waits, nothing refused (%@)", [[store.issues valueForKey:@"message"] componentsJoinedByString:@"; "]]);

    LBStockSettingsViewController *settings = [tabs tabNamed:@"Settings"];
    LBSay([[settings shownSections] containsObject:@"Logbook"], @"Settings offers the logbook");
    [app showLogbook:nil];
    LBSay(app.window.rootViewController == app.mainController && !app.stockController
              && ![[NSUserDefaults standardUserDefaults] stringForKey:LBModeDefaultsKey],
          @"the logbook again, and kept so");
    self.boltID = bolt.id;
    self.shelfID = shelf.id;
    self.catalogID = catalog.id;
}

/* Whether the sync sends two new objects that refer to each other: a
   service and the sale of its parts (ODataKit#61). Not yet: what the
   server has of them is checked once it does. */
static BOOL const LBSyncSendsCycles = NO;

/* A service's parts, on a phone of Anna's (a store of its own, so what it
   cannot send yet waits there): 2 bolts of the stock steps' Shelf A used,
   shipped as it is saved, to the Golf's owner; more than Shelf A holds,
   refused. Anna's contact in the catalog is made at the server, as the
   desktop would: one made on a phone with its customer is the same cycle. */
- (void)partsSteps {
    NSString *email = @"anna@example.org";
    NSString *ofCatalog = [NSString stringWithFormat:@"Catalogs(%@)", LBKey(_catalogID)];
    NSUUID *annaID = [NSUUID UUID];
    NSInteger made = LBAsk(@"POST", @"Contacts", @{ @"Id": LBKey(annaID), @"ContactName": @"Anna", @"Catalog@odata.bind": ofCatalog,
                                                    @"User@odata.bind": [NSString stringWithFormat:@"Users('%@')", email] }, NULL);
    NSInteger customer = LBAsk(@"POST", @"Customers", @{ @"Id": LBKey([NSUUID UUID]), @"Catalog@odata.bind": ofCatalog,
                                                         @"Contact@odata.bind": [NSString stringWithFormat:@"Contacts(%@)", LBKey(annaID)] }, NULL);
    LBSay(made == 201 && customer == 201, @"Anna a customer in the catalog, at the server");
    NSURL *other = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                               [NSString stringWithFormat:@"lb-selftest-parts-%@", [NSProcessInfo processInfo].globallyUniqueString]]
                              isDirectory:YES];
    NSError *error = nil;
    LBLocalStore *phone = [[LBLocalStore alloc] initWithDirectory:other modelURL:nil error:&error];
    phone.email = email;
    phone.serviceRoot = LBSelfTestRoot;
    LBSync(phone, @"her other phone syncs");
    LBPhone *hers = [[LBPhone alloc] initWithStore:phone];
    StockItem *bolts = LBFetchID(phone, [StockItem class], _boltID);
    Location *shelfA = LBFetchID(phone, [Location class], _shelfID);

    LBRecordFormViewController *form = [[LBRecordFormViewController alloc]
        initWithObject:[LBRecordFormViewController newRecordOfKind:@"Service" phone:hers] phone:hers];
    [form enter:@"Garage Müller" intoField:@"Garage"];
    [form enter:@"149000" intoField:@"Odometer"];
    form.partsLocation = shelfA;
    NSArray *problems = nil;
    LBSay([form usePart:bolts quantity:[NSDecimalNumber decimalNumberWithString:@"2"] problems:&problems]
              && [[form partRows] isEqualToArray:@[ @"2 × Bolt, from Main / Shelf A" ]],
          [NSString stringWithFormat:@"a service uses 2 bolts of Shelf A (%@)", [[form partRows] componentsJoinedByString:@"; "] ?: problems]);
    BOOL saved = [form saveIgnoringWarnings:YES];
    SaleOrder *sale = ((Service *)form.object).lb_partsSale;
    LBSay(saved && sale.shipments.count == 1 && LBSame(bolts.totalQuantity, @"14") && [sale.customer.contact.contactName isEqualToString:@"Anna"],
          [NSString stringWithFormat:@"saved: shipped as it was, to Anna; 14 bolts left (%@)", [form.problems componentsJoinedByString:@"; "]]);
    if (LBSyncSendsCycles) {
        LBSync(phone, @"synced");
        NSDictionary *shipments = LBServerHas([NSString stringWithFormat:@"SaleOrders(%@)/Shipments", LBKey(sale.id)]);
        NSDictionary *boltThere = LBServerHas([NSString stringWithFormat:@"StockItems(%@)", LBKey(_boltID)]);
        LBSay([shipments[@"value"] count] == 1 && LBSame(boltThere[@"TotalQuantity"], @"14") && [phone pendingCount] == 0 && phone.issues.count == 0,
              [NSString stringWithFormat:@"the server has the service's parts shipped: 14 bolts (%@; %@)", boltThere[@"TotalQuantity"],
                                         [[phone.issues valueForKey:@"message"] componentsJoinedByString:@"; "]]);
    }

    form = [[LBRecordFormViewController alloc] initWithObject:[LBRecordFormViewController newRecordOfKind:@"Service" phone:hers] phone:hers];
    [form enter:@"Garage Müller" intoField:@"Garage"];
    [form enter:@"149500" intoField:@"Odometer"];
    form.partsLocation = shelfA;
    [form usePart:bolts quantity:[NSDecimalNumber decimalNumberWithString:@"5"] problems:&problems];
    LBSay(![form saveIgnoringWarnings:YES] && [[form.problems componentsJoinedByString:@" "] containsString:@"holds 0"],
          [NSString stringWithFormat:@"5 bolts of the none left on Shelf A: refused at saving (%@)", [form.problems componentsJoinedByString:@"; "]]);
    [phone.context rollback];
    [[NSFileManager defaultManager] removeItemAtURL:other error:NULL];
}

@end

void LBStartSelfTest(LBiOSAppDelegate *app) {
    LBSelfTest *test = [[LBSelfTest alloc] init];
    test.app = app;
    [NSTimer scheduledTimerWithTimeInterval:1 target:test selector:@selector(fire:) userInfo:nil repeats:NO];
}
