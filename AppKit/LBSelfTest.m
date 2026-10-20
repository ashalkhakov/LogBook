#import "LBSelfTest.h"
#import "LBMainWindowController.h"
#import "LBStore.h"
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "VehicleDriver+CoreDataClass.h"
#import "LBDisplay.h"
#import "LBAppController.h"
#import "LBReportData.h"
#import "LBReportsController.h"
#import "LBRemindersController.h"
#import "LBProcedures.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"

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
    [editor insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
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

/* Who the server says drives a vehicle besides its owner. */
static NSArray<NSString *> *LBSharedWith(Vehicle *kept) {
    [LBServerSide.context refreshObject:kept mergeChanges:NO];
    NSMutableArray *emails = [NSMutableArray array];
    for (VehicleDriver *sharing in kept.vehicleDrivers) {
        if (sharing.user.email) [emails addObject:sharing.user.email];
    }
    return emails;
}

/* The vehicle shared with Ben, who is not yet in the logbook, and the
   sharing ended: each saved, each on the server. */
static void LBSharingSteps(LBMainWindowController *controller, Vehicle *kept) {
    NSWindow *window = controller.window;
    LBType(window, @"shareEmail", @"Ben@Example.org");
    LBClick(window, @"share");
    LBCheck(@"shared, the email as a user of the logbook", [controller.vehicleDrivers.arrangedObjects count] == 1
                && [[controller.drivers valueForKey:NSStringFromSelector(@selector(email))] containsObject:@"ben@example.org"],
            controller.drivers);
    LBClick(window, @"save");
    LBCheck(@"the sharing saved", !controller.store.context.hasChanges && !controller.lastError,
            controller.lastError.localizedRecoverySuggestion ?: controller.lastError);
    LBCheck(@"the server has Ben driving it", [LBSharedWith(kept) isEqualToArray:@[ @"ben@example.org" ]], LBSharedWith(kept));
    [controller.vehicleDrivers setSelectionIndex:0];
    LBClick(window, @"unshare");
    LBClick(window, @"save");
    LBCheck(@"the sharing ended, on the server too", [controller.vehicleDrivers.arrangedObjects count] == 0
                && LBSharedWith(kept).count == 0 && controller.drivers.count == 1, LBSharedWith(kept));
}

/* The pop-up's item of the object titled so, chosen as a user does. */
static void LBChoose(NSWindow *window, NSString *identifier, NSString *title) {
    NSPopUpButton *popUp = (NSPopUpButton *)LBControl(window.contentView, identifier);
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
    LBCheck(@"listed once", [controller.records.arrangedObjects count] == 1, controller.records.arrangedObjects);
    LBCheck(@"a new fill-up, chosen, its form shown",
            [fillUp isKindOfClass:[FillUp class]] && [controller.recordForms.selectedTabViewItem.identifier isEqual:@"FillUp"],
            controller.recordForms.selectedTabViewItem.identifier);
    LBCheck(@"filled in: now, its driver the user, in km and litres",
            fillUp.timestamp && fillUp.driver == user && [fillUp.mileageDistanceUnit.code isEqualToString:@"km"]
                && [fillUp.volumeVolumeUnit.code isEqualToString:@"L"] && fillUp.vehicle && fillUp.enteredBy == user,
            [NSString stringWithFormat:@"%@ %@ %@ %@", fillUp.timestamp, fillUp.driver.email, fillUp.mileageDistanceUnit.code,
                                       fillUp.volumeVolumeUnit.code]);
    NSPopUpButton *driver = (NSPopUpButton *)LBControl(window.contentView, @"FillUpDriver");
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

/* The user's currency set in the Preferences window, as a user does. */
static void LBPreferenceSteps(LBMainWindowController *controller) {
    [NSApp sendAction:@selector(showPreferences:) to:nil from:nil];
    LBSpin();
    NSWindow *preferences = nil;
    for (NSWindow *window in NSApp.windows) {
        if (window.isVisible && [window.windowController isKindOfClass:NSClassFromString(@"LBPreferencesController")]) preferences = window;
    }
    LBCheck(@"the Preferences window", preferences != nil, nil);
    if (!preferences) return;
    LBType(preferences, @"currency", @"EUR");
    LBClick(preferences, @"done");
    LBCheck(@"saved and closed", !preferences.isVisible && !controller.lastError && !controller.store.context.hasChanges,
            controller.lastError.localizedRecoverySuggestion ?: controller.lastError);
    LBCheck(@"the user's currency", [controller.store.user.currency isEqualToString:@"EUR"], controller.store.user.currency);
}

/* What each report would show, from the logbook as it is now. */
static void LBReportDataSteps(LBMainWindowController *controller, NSString *vehicleName) {
    LBReportData *data = [[LBReportData alloc] initWithContext:controller.context];
    Vehicle *vehicle = controller.vehicles.selectedObjects.firstObject;
    NSError *error = nil;
    NSArray *costs = [data costsByMonth:&error];
    NSDictionary *mine = nil;
    for (NSDictionary *row in costs) {
        if ([row[@"Vehicle"] isEqual:vehicleName]) mine = row;
    }
    LBCheck(@"costs by month: the vehicle's month, in the owner's currency", [mine[@"Currency"] isEqual:@"EUR"]
                && [mine[@"Total"] doubleValue] > 0, error ?: costs);
    NSArray *fillUps = [data fillUpsOfVehicle:vehicle error:&error];
    LBCheck(@"fuel: the fill-up, its unit's price", fillUps.count == 1 && [fillUps[0][@"Price"] doubleValue] == 1.5
                && [fillUps[0][@"Volume"] integerValue] == 40, error ?: fillUps);
    NSArray *records = [data recordsOfVehicle:vehicle from:[NSDate dateWithTimeIntervalSinceNow:-86400] to:[NSDate date]];
    LBCheck(@"logbook: today's records", records.count == 1 && [records[0][@"Kind"] isEqual:@"Fill-up"], records);
    LBCheck(@"none before", [data recordsOfVehicle:vehicle from:nil to:[NSDate dateWithTimeIntervalSinceNow:-86400 * 2]].count == 0,
            nil);
    NSString *json = [LBReportData JSONOfRows:fillUps];
    LBCheck(@"rows as JSON", [json hasPrefix:@"[{"] && [json containsString:@"\"Price\":1.5"], json);
}

/* A report picked in the Reports tab, as a user does; what its viewer
   rendered, as HTML's text. */
static NSString *LBShowReport(LBMainWindowController *controller, NSString *title) {
    LBReportsController *reports = controller.reports;
    NSInteger index = [reports.reportPicker indexOfItemWithTitle:title];
    LBCheck([NSString stringWithFormat:@"the Reports tab offers %@", title], index >= 0, reports.reportPicker.itemTitles);
    if (index < 0) return @"";
    [reports.reportPicker selectItemAtIndex:index];
    [reports.reportPicker sendAction:reports.reportPicker.action to:reports.reportPicker.target];
    LBSpin();
    NSData *html = [reports.viewer dataUsingBackendNamed:@"HTML"];
    LBCheck([NSString stringWithFormat:@"%@ shown, a page at least", title], reports.viewer.pageCount >= 1 && html.length > 0,
            @(reports.viewer.pageCount));
    return [[NSString alloc] initWithData:html ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
}

static void LBReportSteps(LBMainWindowController *controller) {
    NSTabView *tabs = (NSTabView *)LBControl(controller.window.contentView, @"tabs");
    [tabs selectTabViewItemWithIdentifier:@"reports"];
    LBSpin();
    NSString *costs = LBShowReport(controller, @"Costs by Month");
    LBCheck(@"costs: the vehicle, its month's total in EUR", [costs containsString:@"Self-test Golf"] && [costs containsString:@"60.00"]
                && [costs containsString:@"EUR"], nil);
    NSString *fuel = LBShowReport(controller, @"Fuel");
    /* LB_SCREENSHOT=file.png: the Reports tab too, beside it (macOS). */
    if (getenv("LB_SCREENSHOT")) {
        NSString *path = [[@(getenv("LB_SCREENSHOT")) stringByDeletingPathExtension] stringByAppendingString:@"-reports.png"];
        system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%@'", (long)controller.window.windowNumber, path].UTF8String);
    }
    LBCheck(@"fuel: the fill-up, a litre's price, the station", [fuel containsString:@"1.500"] && [fuel containsString:@"Shell"]
                && [fuel containsString:@"Self-test Golf"], nil);
    NSString *logbook = LBShowReport(controller, @"Logbook");
    LBCheck(@"logbook: the fill-up, by kind", [logbook containsString:@"Fill-up"] && [logbook containsString:@"By kind"], nil);
    [controller.reports.viewer setValue:@"2001-01-01" forParameter:@"To"];
    LBSpin();
    NSString *before = [[NSString alloc] initWithData:[controller.reports.viewer dataUsingBackendNamed:@"HTML"] ?: [NSData data]
                                             encoding:NSUTF8StringEncoding];
    LBCheck(@"logbook to a day long past: the fill-up asked for again, and not there", ![before containsString:@"Fill-up"]
                && [before containsString:@"By kind"], nil);
}

/* A day typed into a date field as its formatter says one: the model's
   day (UTC) as the calendar here has it. */
static void LBTypeDay(NSWindow *window, NSString *identifier, NSDate *day) {
    NSTextField *field = (NSTextField *)LBControl(window.contentView, identifier);
    NSCalendar *utc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    utc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDate *local = [[NSCalendar currentCalendar]
        dateFromComponents:[utc components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day]];
    LBType(window, identifier, [field.formatter stringForObjectValue:local] ?: @"");
}

/* The reminder of the id among those the tab lists. */
static Reminder *LBListed(LBMainWindowController *controller, NSUUID *uuid) {
    for (Reminder *reminder in controller.remindersController.reminders.arrangedObjects) {
        if ([reminder.id isEqual:uuid]) return reminder;
    }
    return nil;
}

/* What the server has of a reminder. */
static Reminder *LBServerReminder(NSUUID *uuid) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([Reminder class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(id)), uuid];
    Reminder *reminder = [[LBServerSide.context executeFetchRequest:fetch error:NULL] firstObject];
    if (reminder) [LBServerSide.context refreshObject:reminder mergeChanges:NO];
    return reminder;
}

static void LBChooseReminder(LBMainWindowController *controller, Reminder *reminder) {
    [controller.remindersController.reminders setSelectedObjects:reminder ? @[ reminder ] : @[]];
    LBSpin();
}

/* The Reminders tab, as a user: an oil change scheduled, and started; a
   service of it logged in the Records tab (warned while it has no
   odometer reading), which closes the reminder on the server and makes the
   next; the next moved, then cancelled for a replacement; a one-off set
   after the service, marked done by it. */
static void LBReminderSteps(LBMainWindowController *controller, Vehicle *kept) {
    NSWindow *window = controller.window;
    LBRemindersController *tab = controller.remindersController;
    /* A kind of service to log one of: the app's, not the user's to add. */
    CostKind *maintenance = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([CostKind class])
                                                          inManagedObjectContext:controller.context];
    maintenance.name = @"Maintenance";
    LBCheck(@"a kind of service", [controller saveChanges], controller.lastError);
    NSTabView *tabs = (NSTabView *)LBControl(window.contentView, @"tabs");
    [tabs selectTabViewItemWithIdentifier:@"reminders"];
    LBSpin();
    LBClick(window, @"newSchedule");
    LBCheck(@"New Schedule shows its form", [tab.forms.selectedTabViewItem.identifier isEqual:@"schedule"], nil);
    LBType(window, @"scheduleTask", @"Oil change");
    LBType(window, @"scheduleEvery", @"15000");
    LBType(window, @"scheduleMonths", @"12");
    LBClick(window, @"scheduleSave");
    Schedule *schedule = [tab.schedules.arrangedObjects firstObject];
    LBCheck(@"the schedule saved and listed: 15000 km or 12 months",
            [tab.schedules.arrangedObjects count] == 1 && [schedule.task isEqualToString:@"Oil change"] && !controller.lastError
                && [tab.forms.selectedTabViewItem.identifier isEqual:@"none"],
            controller.lastError ?: schedule.lbEvery);
    NSUUID *firstID = schedule.id ? LBNamedUUID([@"start of " stringByAppendingString:schedule.id.UUIDString.lowercaseString]) : nil;
    Reminder *first = LBListed(controller, firstID);
    LBCheck(@"started on the server: its first reminder listed, due 12 months on and at the fill-up's distance plus 15000 km",
            first && first.lb_isOpen && [first.dueDate isEqualToDate:LBAddMonths(LBDay([NSDate date]), 12)]
                && first.dueMileageQuantity.integerValue == 27345 && [first.lbStatus isEqualToString:@"Open"],
            first ? first.lbDue : tab.reminders.arrangedObjects);
    LBCheck(@"the schedule's next due shown", [schedule.lbNextDue isEqualToString:first.lbDue], schedule.lbNextDue);

    /* A service of the task, logged as any record. */
    [tabs selectTabViewItemWithIdentifier:@"records"];
    LBSpin();
    NSPopUpButton *add = (NSPopUpButton *)LBControl(window.contentView, @"addRecord");
    NSMenuItem *serviceItem = [add itemAtIndex:(NSInteger)[[Record lbKinds] indexOfObject:NSStringFromClass([Service class])] + 1];
    [NSApp sendAction:serviceItem.action to:serviceItem.target from:serviceItem];
    LBSpin();
    Service *service = controller.records.selectedObjects.firstObject;
    LBCheck(@"a new service, its form shown", [service isKindOfClass:[Service class]]
                && [controller.recordForms.selectedTabViewItem.identifier isEqual:@"Service"], service);
    LBType(window, @"ServiceGarage", @"Garage Müller");
    LBChoose(window, @"ServiceKind", @"Maintenance");
    LBClick(window, @"addServiceItem");
    ServiceItem *item = controller.serviceItems.selectedObjects.firstObject;
    LBCheck(@"an item of it, in its currency", item && item.service == service && [item.costCurrency isEqualToString:service.currency],
            item);
    LBType(window, @"ServiceItemTask", @"Oil change");
    LBType(window, @"ServiceItemCost", @"50");
    LBCheck(@"its task and cost typed", [item.task isEqualToString:@"Oil change"] && item.costAmount.integerValue == 50, item.task);
    LBCheck(@"with no odometer reading yet, a warning that no next reminder would be made",
            [controller reminderWarnings].count == 1 && [[controller reminderWarnings].firstObject.localizedDescription containsString:@"Oil change"],
            [controller reminderWarnings]);
    LBType(window, @"ServiceMileage", @"13000");
    LBClick(window, @"save");
    LBCheck(@"the service saved", !controller.store.context.hasChanges && !controller.lastError,
            controller.lastError.localizedRecoverySuggestion ?: controller.lastError);
    [tabs selectTabViewItemWithIdentifier:@"reminders"];
    LBSpin();
    NSUUID *nextID = LBNamedUUID([@"next of " stringByAppendingString:firstID.UUIDString.lowercaseString]);
    Reminder *next = LBListed(controller, nextID);
    LBCheck(@"the reminder shows done by the service, closed on the server as it saved",
            [first.lbStatus hasPrefix:@"Done"] && ![first.lbStatus hasSuffix:@"by hand"] && [first.event.id isEqual:service.id]
                && first.doneMileageQuantity.integerValue == 13000,
            first.lbStatus);
    LBCheck(@"and the next appears, open, due from the service", next && next.lb_isOpen && next.dueMileageQuantity.integerValue == 28000
                && [tab.reminders.arrangedObjects firstObject] == next,
            next ? next.lbDue : tab.reminders.arrangedObjects);

    /* Moved a month on. */
    LBChooseReminder(controller, next);
    LBClick(window, @"reschedule");
    NSDate *was = next.dueDate;
    NSDate *moved = LBAddMonths(was, 1);
    LBTypeDay(window, @"rescheduleDate", moved);
    LBType(window, @"rescheduleNote", @"away");
    LBClick(window, @"rescheduleSave");
    Rescheduling *move = [tab.reschedulings.arrangedObjects firstObject];
    LBCheck(@"rescheduled: due a month on, the move listed with what it was due on", [next.dueDate isEqualToDate:moved]
                && [tab.reschedulings.arrangedObjects count] == 1 && [move.fromDate isEqualToDate:was] && [move.note isEqualToString:@"away"]
                && !controller.lastError,
            controller.lastError ?: next.lbDue);
    LBCheck(@"the server has the move", LBServerReminder(nextID).reschedulings.count == 1, nil);

    /* Cancelled, replaced. */
    LBChooseReminder(controller, next);
    LBClick(window, @"cancelReminder");
    LBClick(window, @"cancelReplace");
    NSDate *replacementDue = LBAddMonths(LBDay([NSDate date]), 2);
    LBTypeDay(window, @"cancelReplacementDate", replacementDue);
    LBClick(window, @"cancelSave");
    NSUUID *replacementID = LBNamedUUID([@"replacement of " stringByAppendingString:nextID.UUIDString.lowercaseString]);
    Reminder *replacement = LBListed(controller, replacementID);
    LBCheck(@"cancelled, and a replacement listed, open, from the schedule",
            [next.lbStatus hasPrefix:@"Cancelled"] && replacement.lb_isOpen && replacement.replaced == next
                && replacement.schedule == schedule && [replacement.dueDate isEqualToDate:replacementDue],
            controller.lastError ?: next.lbStatus);

    LBCheck(@"the reminder's warning gone once read", [controller reminderWarnings].count == 0, [controller reminderWarnings]);

    /* A one-off, set after the service, marked done by it. */
    LBClick(window, @"newReminder");
    LBType(window, @"reminderTask", @"Oil change");
    LBTypeDay(window, @"reminderDate", LBAddMonths(LBDay([NSDate date]), 1));
    LBClick(window, @"reminderSave");
    Reminder *oneOff = nil;
    for (Reminder *reminder in tab.reminders.arrangedObjects) {
        if (!reminder.schedule) oneOff = reminder;
    }
    LBCheck(@"a one-off saved, open", oneOff.lb_isOpen && !controller.lastError, controller.lastError ?: tab.reminders.arrangedObjects);
    LBChooseReminder(controller, oneOff);
    LBClick(window, @"markDone");
    NSPopUpButton *events = (NSPopUpButton *)LBControl(window.contentView, @"doneEvent");
    LBCheck(@"Mark Done offers the service, and no by hand", events.numberOfItems == 1 && [tab.form.event.id isEqual:service.id],
            events.itemTitles);
    LBClick(window, @"doneSave");
    LBCheck(@"marked done by the service", [oneOff.lbStatus hasPrefix:@"Done"] && [oneOff.event.id isEqual:service.id] && !controller.lastError,
            controller.lastError ?: oneOff.lbStatus);
    Reminder *onServer = LBServerReminder(oneOff.id);
    LBCheck(@"the server has it done by the service", onServer.doneAt && [onServer.event.id isEqual:service.id], onServer);
    if (getenv("LB_SCREENSHOT")) {
        NSString *path = [[@(getenv("LB_SCREENSHOT")) stringByDeletingPathExtension] stringByAppendingString:@"-reminders.png"];
        system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%@'", (long)window.windowNumber, path].UTF8String);
    }
}

static void LBSteps(LBMainWindowController *controller) {
    NSWindow *window = controller.window;
    controller.quiet = YES;
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    LBCheck(@"the window", window.isVisible, nil);
    NSUInteger before = [controller.vehicles.arrangedObjects count];
    NSArrayController *vehicles = controller.vehicles;
    LBCheck(@"the vehicles' controller is in entity mode, over the context", [vehicles.entityName isEqualToString:@"Vehicle"]
                                                                                 && vehicles.managedObjectContext == controller.context,
            [NSString stringWithFormat:@"%@ %@ canAdd %d", vehicles.entityName, vehicles.managedObjectContext, vehicles.canAdd]);

    LBClick(window, @"addVehicle");
    LBCheck(@"a new vehicle, chosen", [controller.vehicles.arrangedObjects count] == before + 1
                                          && controller.vehicles.selectedObjects.count == 1,
            [NSString stringWithFormat:@"%lu listed (%lu before), %lu chosen", (unsigned long)[controller.vehicles.arrangedObjects count],
                                       (unsigned long)before, (unsigned long)controller.vehicles.selectedObjects.count]);
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
            [NSString stringWithFormat:@"%@ / %@ / %@", controller.lastError, controller.store.context.updatedObjects,
                                       controller.store.context.insertedObjects]);
    Vehicle *kept = LBVehicleNamed(@"Self-test Golf");
    LBCheck(@"the server has it", [kept.make isEqualToString:@"Volkswagen"] && [kept.carModel isEqualToString:@"Golf VII"], kept);
    LBCheck(@"its owner the user", [kept.owner.email isEqualToString:controller.store.user.email], kept.owner.email);
    LBSharingSteps(controller, kept);
    LBRecordSteps(controller, kept);
    LBPreferenceSteps(controller);
    LBReportDataSteps(controller, @"Self-test Golf");
    LBReportSteps(controller);
    LBReminderSteps(controller, kept);
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
