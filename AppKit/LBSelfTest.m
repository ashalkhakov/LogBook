#import "LBSelfTest.h"
#import "LBMainWindowController.h"
#import "LBStore.h"
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "LBDisplay.h"
#import "LBObjectPopUpButton.h"

NSURL *LBSelfTestRoot;

static NSUInteger LBFailures;

static void LBCheck(NSString *what, BOOL ok, id detail) {
    printf("%s %s%s\n", ok ? "ok  " : "FAIL", what.UTF8String, ok || !detail ? "" : [NSString stringWithFormat:@": %@", detail].UTF8String);
    fflush(stdout);
    if (!ok) LBFailures++;
}

/* The control of the identifier, in the view or under it. */
static NSView *LBControl(NSView *view, NSString *identifier) {
    if ([view.identifier isEqualToString:identifier]) return view;
    for (NSView *each in view.subviews) {
        NSView *found = LBControl(each, identifier);
        if (found) return found;
    }
    return nil;
}

/* The run loop let turn, as between a user's events: an array
   controller's add: is done at the next turn. */
static void LBSpin(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
}

/* Typed into a field, as a user does: its editor's text, then elsewhere. */
static void LBType(NSWindow *window, NSString *identifier, NSString *text) {
    NSTextField *field = (NSTextField *)LBControl(window.contentView, identifier);
    LBCheck([NSString stringWithFormat:@"a field %@", identifier], field != nil, nil);
    if (!field) return;
    [window makeFirstResponder:field];
    NSTextView *editor = (NSTextView *)[window fieldEditor:NO forObject:field];
    [editor selectAll:nil];
#ifdef GNUSTEP
    [editor insertText:text];
#else
    [editor insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
#endif
    [window makeFirstResponder:nil];
    LBSpin();
}

static void LBClick(NSWindow *window, NSString *identifier) {
    NSButton *button = (NSButton *)LBControl(window.contentView, identifier);
    LBCheck([NSString stringWithFormat:@"a button %@", identifier], button != nil && button.isEnabled, nil);
    [button performClick:nil];
    LBSpin();
}

/* What the server has: read through a store of its own, kept while its
   objects are looked at. */
static LBStore *LBServerSide;

static Vehicle *LBVehicleNamed(NSString *name) {
    if (!LBServerSide) {
        LBServerSide = [[LBStore alloc] initWithServiceRoot:LBSelfTestRoot signIn:nil];
        if (![LBServerSide open:NULL]) return nil;
    }
    LBStore *other = LBServerSide;
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Vehicle class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(vehicleName)), name];
    return [[other.context executeFetchRequest:fetch error:NULL] firstObject];
}

/* The pop-up's item of the object titled so, chosen as a user does. */
static void LBChoose(NSWindow *window, NSString *identifier, NSString *title) {
    LBObjectPopUpButton *popUp = (LBObjectPopUpButton *)LBControl(window.contentView, identifier);
    NSInteger index = [popUp indexOfItemWithTitle:title];
    LBCheck([NSString stringWithFormat:@"%@ offers %@", identifier, title], index >= 0, [popUp itemTitles]);
    if (index < 0) return;
    [popUp selectItemAtIndex:index];
    [popUp sendAction:popUp.action to:popUp.target];
    LBSpin();
}

/* A fill-up of the vehicle saved: a record of the Add menu's kind, filled
   in, its form typed into. */
static void LBRecordSteps(LBMainWindowController *controller, Vehicle *kept) {
    NSWindow *window = controller.window;
    User *user = controller.store.user;
    NSTabView *tabs = (NSTabView *)LBControl(window.contentView, @"tabs");
    [tabs selectTabViewItemWithIdentifier:@"records"];
    LBSpin();
    NSPopUpButton *add = (NSPopUpButton *)LBControl(window.contentView, @"addRecord");
    NSArray<NSString *> *kinds = [Record lbKinds];
    LBCheck(@"Add offers each kind of record", add.numberOfItems == (NSInteger)kinds.count + 1, add.itemTitles);
    NSMenuItem *fillUpItem = [add itemAtIndex:(NSInteger)[kinds indexOfObject:NSStringFromClass([FillUp class])] + 1];
    [NSApp sendAction:fillUpItem.action to:fillUpItem.target from:fillUpItem];
    LBSpin();
    FillUp *fillUp = controller.records.selectedObjects.firstObject;
    LBCheck(@"a new fill-up, chosen, its form shown",
            [fillUp isKindOfClass:[FillUp class]] && [controller.recordForms.selectedTabViewItem.identifier isEqual:@"FillUp"],
            controller.recordForms.selectedTabViewItem.identifier);
    LBCheck(@"filled in: now, its driver the user, in km and litres",
            fillUp.timestamp && fillUp.driver == user && [fillUp.mileageDistanceUnit.code isEqualToString:@"km"]
                && [fillUp.volumeVolumeUnit.code isEqualToString:@"L"] && fillUp.vehicle && fillUp.enteredBy == user,
            [NSString stringWithFormat:@"%@ %@ %@ %@", fillUp.timestamp, fillUp.driver.email, fillUp.mileageDistanceUnit.code,
                                       fillUp.volumeVolumeUnit.code]);
    LBObjectPopUpButton *driver = (LBObjectPopUpButton *)LBControl(window.contentView, @"FillUpDriver");
    LBCheck(@"the driver's pop-up shows the user", driver.selectedItem.representedObject == user, driver.titleOfSelectedItem);
    NSTextField *date = (NSTextField *)LBControl(window.contentView, @"FillUpTimestamp");
    LBCheck(@"its date shown", date.stringValue.length > 0 && [date.formatter isKindOfClass:[NSDateFormatter class]], date.stringValue);
    LBType(window, @"FillUpMileage", @"12345");
    LBType(window, @"FillUpVolume", @"40");
    LBType(window, @"FillUpFuel", @"Petrol 95");
    LBType(window, @"FillUpTotal", @"60");
    LBType(window, @"FillUpStation", @"Shell");
    LBCheck(@"numbers typed are decimals of the fill-up",
            [fillUp.mileageQuantity isKindOfClass:[NSDecimalNumber class]] && fillUp.mileageQuantity.integerValue == 12345
                && fillUp.volumeQuantity.integerValue == 40 && fillUp.totalAmount.integerValue == 60,
            [NSString stringWithFormat:@"%@ (%@) %@ %@", fillUp.mileageQuantity, [fillUp.mileageQuantity class], fillUp.volumeQuantity,
                                       fillUp.totalAmount]);
    LBChoose(window, @"FillUpMileageUnit", @"mi");
    LBCheck(@"a unit chosen is the fill-up's", [fillUp.mileageDistanceUnit.code isEqualToString:@"mi"], fillUp.mileageDistanceUnit.code);
    LBChoose(window, @"FillUpMileageUnit", @"km");
    LBCheck(@"and another", [fillUp.mileageDistanceUnit.code isEqualToString:@"km"], fillUp.mileageDistanceUnit.code);
    LBCheck(@"listed with its cost", [fillUp.lbCost hasPrefix:@"60"], fillUp.lbCost);
    /* LB_SCREENSHOT=file.png: the window as it is now, to look at (macOS). */
    if (getenv("LB_SCREENSHOT")) system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%s'", (long)window.windowNumber, getenv("LB_SCREENSHOT")].UTF8String);
    LBClick(window, @"save");
    LBCheck(@"the fill-up saved", !controller.store.context.hasChanges && !controller.lastError,
            controller.lastError.localizedRecoverySuggestion ?: controller.lastError);
    [LBServerSide.context refreshObject:kept mergeChanges:NO];
    FillUp *sent = nil;
    for (Record *record in kept.records) {
        if ([record isKindOfClass:[FillUp class]]) sent = (FillUp *)record;
    }
    LBCheck(@"the server has the fill-up",
            sent && sent.volumeQuantity.integerValue == 40 && [sent.station isEqualToString:@"Shell"] && sent.filledTheTank
                && [sent.driver.email isEqualToString:user.email] && [sent.mileageDistanceUnit.code isEqualToString:@"km"],
            [NSString stringWithFormat:@"%@ %@ %@ %@", sent, sent.volumeQuantity, sent.station, sent.mileageDistanceUnit.code]);
}

static void LBSteps(LBMainWindowController *controller) {
    NSWindow *window = controller.window;
    controller.quiet = YES;
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    LBCheck(@"the window", window.isVisible, nil);
    NSUInteger before = [controller.vehicles.arrangedObjects count];
    LBEntityController *vehicles = (LBEntityController *)controller.vehicles;
    LBCheck(@"the vehicles' controller has its entity and context", vehicles.modelEntityName && vehicles.context,
            [NSString stringWithFormat:@"%@ %@ canAdd %d content %@", vehicles.modelEntityName, vehicles.context, vehicles.canAdd,
                                       [vehicles.content class]]);

    LBClick(window, @"addVehicle");
    LBCheck(@"a new vehicle, chosen", [controller.vehicles.arrangedObjects count] == before + 1
                                          && controller.vehicles.selectedObjects.count == 1, nil);
    LBType(window, @"vehicleName", @"Self-test Golf");
    LBType(window, @"make", @"Volkswagen");
    LBType(window, @"carModel", @"Golf VII");
    LBType(window, @"manufactureYear", @"2016");
    LBType(window, @"fuel", @"Petrol");
    Vehicle *chosen = controller.vehicles.selectedObjects.firstObject;
    LBCheck(@"what was typed is the vehicle's", [chosen.vehicleName isEqualToString:@"Self-test Golf"] && chosen.manufactureYear == 2016,
            chosen.vehicleName);
    LBClick(window, @"save");
    LBCheck(@"saved", !controller.store.context.hasChanges && !controller.lastError,
            controller.lastError.localizedRecoverySuggestion ?: controller.store.context.insertedObjects);
    Vehicle *kept = LBVehicleNamed(@"Self-test Golf");
    LBCheck(@"the server has it", [kept.make isEqualToString:@"Volkswagen"] && [kept.carModel isEqualToString:@"Golf VII"], kept);
    LBCheck(@"its owner the user", [kept.owner.email isEqualToString:controller.store.user.email], kept.owner.email);
    LBRecordSteps(controller, kept);
}

void LBRunSelfTest(LBMainWindowController *window) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            LBSteps(window);
        } @catch (NSException *e) {
            LBCheck(@"no exception", NO, e.reason);
        }
        printf("self-test done: %lu failed\n", (unsigned long)LBFailures);
        fflush(stdout);
        exit(LBFailures ? 1 : 0);
    });
}
