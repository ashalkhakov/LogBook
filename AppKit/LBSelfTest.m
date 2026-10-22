#import "LBSelfTest.h"
#import "LBMainWindowController.h"
#import "LBStore.h"
#import "Vehicle+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "VehicleDriver+CoreDataClass.h"
#import "LBDisplay.h"
#import "Answer+CoreDataClass.h"
#import "Inspection+CoreDataClass.h"
#import "MeterReading+CoreDataClass.h"
#import "Document+CoreDataClass.h"
#import "TyreChange+CoreDataClass.h"
#import "TyreSet+CoreDataClass.h"
#import "Income+CoreDataClass.h"
#import "Trip+CoreDataClass.h"
#import "Expense+CoreDataClass.h"
#import "LBAppController.h"
#import "LBReportData.h"
#import "LBReportsController.h"
#import "LBRemindersController.h"
#import "LBListsController.h"
#import "LBAnswersController.h"
#import "LBCalendarController.h"
#import "UDCalendarView.h"
#import "LBCalendar.h"
#import "LBProcedures.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"
#import "ExpenseKind+CoreDataClass.h"
#import "Option+CoreDataClass.h"
#import "ExchangeRate+CoreDataClass.h"

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
    LBCheck(@"filled in: now, here (this Mac's time zone), its driver the user, in km and litres",
            fillUp.timestamp && [fillUp.timeZone isEqualToString:[NSTimeZone localTimeZone].name] && fillUp.driver == user
                && [fillUp.mileageDistanceUnit.code isEqualToString:@"km"]
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

/* A receipt attached to the fill-up elsewhere (a phone's photo, synced to
   the server): listed with the record, opened as a file of its name. */
static void LBAttachmentSteps(LBMainWindowController *controller, Vehicle *kept) {
    NSWindow *window = controller.window;
    [LBServerSide.context refreshObject:kept mergeChanges:NO];
    FillUp *there = nil;
    for (Record *record in kept.records) {
        if ([record isKindOfClass:[FillUp class]]) there = (FillUp *)record;
    }
    Attachment *receipt = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Attachment class])
                                                        inManagedObjectContext:LBServerSide.context];
    receipt.id = [NSUUID UUID];
    receipt.fileName = @"receipt-0914.jpg";
    receipt.content = [@"the receipt's photo" dataUsingEncoding:NSUTF8StringEncoding];
    receipt.record = there;
    NSError *error = nil;
    LBCheck(@"a receipt attached to the fill-up elsewhere", there && [LBServerSide save:&error], error);
    [controller readAgain];
    LBSpin();
    FillUp *fillUp = nil;
    for (Record *record in controller.records.arrangedObjects) {
        if ([record isKindOfClass:[FillUp class]]) fillUp = (FillUp *)record;
    }
    [controller.records setSelectedObjects:fillUp ? @[ fillUp ] : @[]];
    LBSpin();
    NSArray *names = [controller.attachments.arrangedObjects valueForKey:NSStringFromSelector(@selector(fileName))];
    NSTableView *table = (NSTableView *)LBControl(window.contentView, @"attachmentsTable");
    LBCheck(@"the record's attachment listed beside it", [names isEqualToArray:@[ @"receipt-0914.jpg" ]] && table.numberOfRows == 1, names);
    [controller.attachments setSelectionIndexes:[NSIndexSet indexSet]];
    LBSpin();
    NSButton *open = (NSButton *)LBControl(window.contentView, @"openAttachment");
    LBCheck(@"nothing to open with no attachment chosen", open && !open.isEnabled, nil);
    [controller.attachments setSelectionIndex:0];
    LBSpin();
    LBClick(window, @"openAttachment");
    Attachment *listed = controller.attachments.selectedObjects.firstObject;
    NSURL *file = listed ? [controller fileOfAttachment:listed error:&error] : nil;
    LBCheck(@"opened as a file of its name, its content", [file.lastPathComponent isEqualToString:@"receipt-0914.jpg"]
                && [[NSData dataWithContentsOfURL:file] isEqualToData:receipt.content] && !controller.lastError,
            error ?: controller.lastError ?: file);
}

static NSArray *LBServerObjects(Class cls, NSPredicate *predicate);

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
    NSString *localeCurrency = [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode] ?: @"EUR";
    User *there = [LBServerObjects([User class], [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(email)),
                                                                controller.store.user.email]) firstObject];
    LBCheck(@"a user who preferred no currency took this Mac's at sign-in, on the server too",
            [controller.store.user.currency isEqualToString:localeCurrency] && [there.currency isEqualToString:localeCurrency],
            [NSString stringWithFormat:@"here %@, there %@", controller.store.user.currency, there.currency]);
    NSString *zone = [NSTimeZone localTimeZone].name;
    LBCheck(@"and this Mac's time zone, as they had none", [there.timeZone isEqualToString:zone], there.timeZone);
    LBType(preferences, @"currency", @"EUR");
    LBClick(preferences, @"done");
    LBCheck(@"saved and closed", !preferences.isVisible && !controller.lastError && !controller.store.context.hasChanges,
            controller.lastError.localizedRecoverySuggestion ?: controller.lastError);
    LBCheck(@"the user's currency", [controller.store.user.currency isEqualToString:@"EUR"], controller.store.user.currency);
}

/* The objects of an entity the server has, as the predicate says. */
static NSArray *LBServerObjects(Class cls, NSPredicate *predicate) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = predicate;
    NSArray *objects = [LBServerSide.context executeFetchRequest:fetch error:NULL] ?: @[];
    for (NSManagedObject *object in objects) [LBServerSide.context refreshObject:object mergeChanges:NO];
    return objects;
}

/* Typed over the name a list's new row is ready with, as a user does. */
static void LBTypeInRow(NSWindow *window, NSString *what, NSString *text) {
    NSTextView *editor = (NSTextView *)window.firstResponder;
    BOOL editing = [editor isKindOfClass:[NSTextView class]];
    LBCheck([NSString stringWithFormat:@"%@ ready to be typed", what], editing, window.firstResponder);
    if (!editing) return;
    [editor selectAll:nil];
    [editor insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
    [window makeFirstResponder:nil];
    LBSpin();
}

static NSWindow *LBListsWindow(void) {
    for (NSWindow *window in NSApp.windows) {
        if (window.isVisible && [window.windowController isKindOfClass:NSClassFromString(@"LBListsController")]) return window;
    }
    return nil;
}

/* The users' own lists, written in their window: a kind of expense, a
   checklist of two questions, one any-of with two options, put in order;
   saved, and offered where a form picks from them. */
static void LBListSteps(LBMainWindowController *controller) {
    [NSApp sendAction:@selector(showExpenseKinds:) to:nil from:nil];
    LBSpin();
    NSWindow *lists = LBListsWindow();
    LBListsController *owner = lists.windowController;
    LBCheck(@"the lists' window, at the kinds of expense", lists && [owner.tabs.selectedTabViewItem.identifier isEqual:@"expenseKinds"], nil);
    if (!lists) return;
    LBClick(lists, @"addExpenseKind");
    LBTypeInRow(lists, @"a new kind", @"Car wash");
    LBCheck(@"a kind of expense named", [[owner.expenseKinds.selectedObjects.firstObject name] isEqualToString:@"Car wash"],
            owner.expenseKinds.selectedObjects);

    [owner.tabs selectTabViewItemWithIdentifier:@"checklists"];
    LBSpin();
    LBClick(lists, @"addChecklist");
    LBTypeInRow(lists, @"a new checklist", @"Monthly check");
    LBClick(lists, @"addQuestion");
    LBTypeInRow(lists, @"a new question", @"Are the tyres fine?");
    LBCheck(@"a question takes no options until it is any-of", !((NSButton *)LBControl(lists.contentView, @"addOption")).isEnabled, nil);
    LBClick(lists, @"addQuestion");
    LBTypeInRow(lists, @"another question", @"Which lights are out?");
    LBChoose(lists, @"answerKind", @"Any of");
    LBClick(lists, @"addOption");
    LBTypeInRow(lists, @"an option", @"Low beams");
    LBClick(lists, @"addOption");
    LBTypeInRow(lists, @"another option", @"High beams");
    LBClick(lists, @"moveQuestionUp");
    NSArray *texts = [owner.questions.arrangedObjects valueForKey:NSStringFromSelector(@selector(questionText))];
    LBCheck(@"the questions in the order put", [texts isEqualToArray:(@[ @"Which lights are out?", @"Are the tyres fine?" ])], texts);

    [owner.tabs selectTabViewItemWithIdentifier:@"exchangeRates"];
    LBSpin();
    LBClick(lists, @"addExchangeRate");
    LBTypeInRow(lists, @"a new rate's currency", @"USD");
    NSTableView *rates = owner.exchangeRatesTable;
    ExchangeRate *rate = owner.exchangeRates.selectedObjects.firstObject;
    [rates editColumn:[rates columnWithIdentifier:NSStringFromSelector(@selector(factor))]
                  row:(NSInteger)[owner.exchangeRates.arrangedObjects indexOfObjectIdenticalTo:rate] withEvent:nil select:YES];
    LBTypeInRow(lists, @"its factor", @"0.9");
    NSString *mine = controller.store.user.currency;
    LBCheck(@"a rate of today: 1 USD is worth 0.9 in the user's currency", [rate.baseCurrency isEqualToString:@"USD"]
                && [rate.quoteCurrency isEqualToString:mine] && [rate.factor isEqual:[NSDecimalNumber decimalNumberWithString:@"0.9"]],
            rate);
    LBClick(lists, @"done");
    LBCheck(@"saved and closed", !lists.isVisible && !controller.lastError && !controller.store.context.hasChanges,
            controller.lastError.localizedRecoverySuggestion ?: controller.lastError);

    NSString *name = NSStringFromSelector(@selector(name));
    LBCheck(@"the server has the kind",
            [LBServerObjects([ExpenseKind class], [NSPredicate predicateWithFormat:@"%K == %@", name, @"Car wash"]) count] == 1, nil);
    Checklist *kept = [LBServerObjects([Checklist class], [NSPredicate predicateWithFormat:@"%K == %@",
                                                                       NSStringFromSelector(@selector(checklistName)), @"Monthly check"])
        firstObject];
    NSArray<Question *> *questions = [kept.questions.allObjects
        sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(position)) ascending:YES] ]];
    LBCheck(@"and the checklist, the user's, its questions in order, the first any-of of two options",
            [kept.user.email isEqualToString:controller.store.user.email] && questions.count == 2
                && [questions[0].questionText isEqualToString:@"Which lights are out?"] && [questions[0].answerKind isEqualToString:LBAnyOf]
                && questions[0].options.count == 2 && [questions[1].answerKind isEqualToString:LBYesOrNo],
            kept);
    ExchangeRate *keptRate = [LBServerObjects([ExchangeRate class], [NSPredicate predicateWithFormat:@"%K == %@",
                                                                      NSStringFromSelector(@selector(baseCurrency)), @"USD"]) firstObject];
    LBCheck(@"and the rate", [keptRate.quoteCurrency isEqualToString:controller.store.user.currency]
                && [keptRate.factor isEqual:[NSDecimalNumber decimalNumberWithString:@"0.9"]],
            keptRate);
    [NSApp sendAction:@selector(showExchangeRates:) to:nil from:nil];
    LBSpin();
    LBCheck(@"saved, a rate is not typed over", ![owner tableView:owner.exchangeRatesTable shouldEditTableColumn:nil row:0], nil);
    [owner.exchangeRates setSelectionIndex:0];
    LBClick(lists, @"removeExchangeRate");
    LBCheck(@"nor removed: refused, and said", [owner.exchangeRates.arrangedObjects count] == 1
                && [controller.lastError.localizedDescription containsString:@"kept once saved"],
            controller.lastError);
    [lists close];
    NSPopUpButton *kinds = (NSPopUpButton *)LBControl(controller.window.contentView, @"scheduleExpenseKind");
    NSPopUpButton *checklists = (NSPopUpButton *)LBControl(controller.window.contentView, @"scheduleChecklist");
    LBCheck(@"a schedule's form offers both", [kinds indexOfItemWithTitle:@"Car wash"] >= 0
                && [checklists indexOfItemWithTitle:@"Monthly check"] >= 0,
            [[kinds itemTitles] arrayByAddingObjectsFromArray:[checklists itemTitles]]);
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
    /* A field of a model day itself, in UTC: the day as it is. */
    if (((NSDateFormatter *)field.formatter).timeZone.secondsFromGMT == 0) {
        LBType(window, identifier, [field.formatter stringForObjectValue:day] ?: @"");
        return;
    }
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
    /* The kinds of service, the model's (every store starts with them):
       no kind of expense, nor a fill-up's 'Fuel'. */
    NSPopUpButton *kinds = (NSPopUpButton *)LBControl(window.contentView, @"ServiceKind");
    NSMutableArray *offered = [NSMutableArray array];
    for (NSMenuItem *item in kinds.itemArray) {
        if (item.representedObject) [offered addObject:item.title];
    }
    LBCheck(@"a service's kinds are the model's two", [offered isEqualToArray:(@[ @"Maintenance", @"Repair" ])], [kinds itemTitles]);
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
            [first.lbStatus hasPrefix:@"Done"] && [first.lbStatus hasSuffix:@"by Service"] && [first.event.id isEqual:service.id]
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

    /* The schedule changed: another task, every 6 months. Not in place: a
       new schedule goes on from it, listed instead; its open reminder, a
       replacement (touched), is cancelled and the new one started. */
    [tab.schedules setSelectedObjects:@[ schedule ]];
    LBSpin();
    LBClick(window, @"editSchedule");
    NSTextField *task = (NSTextField *)LBControl(window.contentView, @"scheduleTask");
    LBCheck(@"Edit Schedule shows it in its form, and asks no last done",
            [tab.forms.selectedTabViewItem.identifier isEqual:@"schedule"] && [task.stringValue isEqualToString:@"Oil change"]
                && LBControl(window.contentView, @"scheduleDate").isHidden,
            task.stringValue);
    LBClick(window, @"scheduleChecklistEdit");
    NSWindow *lists = LBListsWindow();
    LBCheck(@"Edit… beside the checklists shows them", lists
                && [((LBListsController *)lists.windowController).tabs.selectedTabViewItem.identifier isEqual:@"checklists"],
            nil);
    [lists close];
    [window makeKeyAndOrderFront:nil];
    LBType(window, @"scheduleTask", @"Oil and filter");
    LBType(window, @"scheduleMonths", @"6");
    LBClick(window, @"scheduleSave");
    Schedule *changed = [tab.schedules.arrangedObjects firstObject];
    LBCheck(@"changed: a new schedule going on from it, listed instead, the old one as it was",
            [tab.schedules.arrangedObjects count] == 1 && changed != schedule && changed.continued == schedule
                && [changed.task isEqualToString:@"Oil and filter"] && changed.duration == 6 && changed.intervalQuantity.integerValue == 15000
                && [schedule.task isEqualToString:@"Oil change"] && schedule.duration == 12 && !controller.lastError
                && [tab.forms.selectedTabViewItem.identifier isEqual:@"none"],
            controller.lastError ?: [tab.schedules.arrangedObjects valueForKey:NSStringFromSelector(@selector(lbWork))]);
    Reminder *wasOpen = LBServerReminder(replacementID);
    Reminder *nowOpen = nil;
    for (Reminder *reminder in tab.reminders.arrangedObjects) {
        if (reminder.schedule == changed && reminder.lb_isOpen) nowOpen = reminder;
    }
    LBCheck(@"its open reminder, touched, cancelled today; the new one started, due 6 months on from where that was counted from",
            wasOpen.cancelDate && [wasOpen.schedule.id isEqual:schedule.id] && nowOpen
                && [nowOpen.dueDate isEqualToDate:LBAddMonths(wasOpen.countedFromDate, 6)],
            nowOpen ? nowOpen.lbDue : wasOpen.lbStatus);
    Schedule *there = [LBServerObjects([Schedule class], [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(id)),
                                                                      changed.id]) firstObject];
    LBCheck(@"the server has it, going on from the old one", [there.continued.id isEqual:schedule.id] && there.duration == 6, there);
    if (getenv("LB_SCREENSHOT")) {
        NSString *path = [[@(getenv("LB_SCREENSHOT")) stringByDeletingPathExtension] stringByAppendingString:@"-reminders.png"];
        system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%@'", (long)window.windowNumber, path].UTF8String);
    }
}

/* A record of the Add menu's kind, added as a user adds one: chosen, its
   form shown. */
static Record *LBAddRecord(LBMainWindowController *controller, Class kind) {
    NSWindow *window = controller.window;
    NSPopUpButton *add = (NSPopUpButton *)LBControl(window.contentView, @"addRecord");
    NSMenuItem *item = [add itemAtIndex:(NSInteger)[[Record lbKinds] indexOfObject:NSStringFromClass(kind)] + 1];
    [NSApp sendAction:item.action to:item.target from:item];
    LBSpin();
    Record *record = controller.records.selectedObjects.firstObject;
    LBCheck([NSString stringWithFormat:@"a new %@, its form shown", [Record lbKindOfEntityNamed:NSStringFromClass(kind)]],
            [record isKindOfClass:kind] && [controller.recordForms.selectedTabViewItem.identifier isEqual:NSStringFromClass(kind)], record);
    return record;
}

/* Saved as a user saves, and what the server has of the record. */
static id LBSaved(LBMainWindowController *controller, Record *record, NSString *what) {
    LBClick(controller.window, @"save");
    LBCheck(what, !controller.store.context.hasChanges && !controller.lastError,
            controller.lastError.localizedRecoverySuggestion ?: controller.lastError);
    LBCheck(@"still the one chosen", [controller.records.selectedObjects isEqualToArray:@[ record ]], controller.records.selectedObjects);
    return [LBServerObjects([record class], [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(id)), record.id])
        firstObject];
}

static void LBChooseRecord(LBMainWindowController *controller, Record *record) {
    [controller.records setSelectedObjects:@[ record ]];
    LBSpin();
}

static BOOL LBIs(NSDecimalNumber *number, NSString *value) {
    return number && [number compare:[NSDecimalNumber decimalNumberWithString:value]] == NSOrderedSame;
}

/* Every kind of record the Add menu offers, as a user: added, its form
   filled in, saved; then corrected, and saved again. The server has each
   as typed. An income for a trip, an inspection's answers, a fill-up
   charged in another currency, a file attached and removed, a record
   removed. */
static void LBKindSteps(LBMainWindowController *controller) {
    NSWindow *window = controller.window;
    NSTabView *tabs = (NSTabView *)LBControl(window.contentView, @"tabs");
    [tabs selectTabViewItemWithIdentifier:@"records"];
    LBSpin();

    Expense *expense = (Expense *)LBAddRecord(controller, [Expense class]);
    LBChoose(window, @"ExpenseKind", @"Car wash");
    LBType(window, @"ExpenseMileage", @"14100");
    LBType(window, @"ExpenseTotal", @"12.50");
    LBType(window, @"ExpenseCharged", @"13.90");
    LBType(window, @"ExpenseChargedCurrency", @"USD");
    Expense *keptExpense = LBSaved(controller, expense, @"the expense saved");
    LBCheck(@"the server has it: its kind, odometer, cost and what was charged",
            [keptExpense.expenseKind.name isEqualToString:@"Car wash"] && LBIs(keptExpense.mileageQuantity, @"14100")
                && LBIs(keptExpense.totalAmount, @"12.5") && LBIs(keptExpense.chargedAmount, @"13.9")
                && [keptExpense.chargedCurrency isEqualToString:@"USD"],
            keptExpense);
    LBChooseRecord(controller, expense);
    LBType(window, @"ExpenseTotal", @"15");
    keptExpense = LBSaved(controller, expense, @"the expense corrected");
    LBCheck(@"the server has the cost corrected", LBIs(keptExpense.totalAmount, @"15"), keptExpense.totalAmount);

    Trip *trip = (Trip *)LBAddRecord(controller, [Trip class]);
    LBType(window, @"TripMileage", @"14200");
    LBType(window, @"TripPlace", @"Berlin");
    LBType(window, @"TripDistance", @"14450");
    LBType(window, @"TripWentTo", @"Hamburg");
    LBType(window, @"TripPurpose", @"Delivery");
    Trip *keptTrip = LBSaved(controller, trip, @"the trip saved");
    LBCheck(@"the server has it, from and to", [keptTrip.place isEqualToString:@"Berlin"] && [keptTrip.wentToPlace isEqualToString:@"Hamburg"]
                && LBIs(keptTrip.distanceQuantity, @"14450"),
            keptTrip);
    LBChooseRecord(controller, trip);
    LBType(window, @"TripPurpose", @"Customer visit");
    keptTrip = LBSaved(controller, trip, @"the trip corrected");
    LBCheck(@"the server has its purpose corrected", [keptTrip.purpose isEqualToString:@"Customer visit"], keptTrip.purpose);

    Income *income = (Income *)LBAddRecord(controller, [Income class]);
    LBType(window, @"IncomeKind", @"Delivery fee");
    LBType(window, @"IncomeEarned", @"80");
    LBType(window, @"IncomeEarnedCurrency", @"EUR");
    LBChoose(window, @"IncomeTrip", trip.lbTitle);
    Income *keptIncome = LBSaved(controller, income, @"the income saved");
    LBCheck(@"the server has it, for the trip", [keptIncome.incomeKind isEqualToString:@"Delivery fee"] && LBIs(keptIncome.earnedAmount, @"80")
                && [keptIncome.trip.id isEqual:trip.id],
            keptIncome);
    LBChooseRecord(controller, trip);
    NSTextField *earned = (NSTextField *)LBControl(window.contentView, @"TripIncome");
    LBCheck(@"the trip shows what it earned", [earned.stringValue isEqualToString:@"80.00 EUR"], earned.stringValue);
    LBChooseRecord(controller, income);
    LBType(window, @"IncomeEarned", @"90");
    keptIncome = LBSaved(controller, income, @"the income corrected");
    LBCheck(@"the server has it corrected", LBIs(keptIncome.earnedAmount, @"90"), keptIncome.earnedAmount);

    TyreSet *tyres = (TyreSet *)LBAddRecord(controller, [TyreSet class]);
    LBType(window, @"TyreSetName", @"Winter set");
    LBType(window, @"TyreSetSeason", @"Winter");
    LBType(window, @"TyreSetModel", @"Alpin 6");
    LBType(window, @"TyreSetSize", @"205/55 R16");
    LBTypeDay(window, @"TyreSetDate", LBDay([NSDate date]));
    LBType(window, @"TyreSetTotal", @"400");
    LBType(window, @"TyreSetTotalCurrency", @"EUR");
    TyreSet *keptTyres = LBSaved(controller, tyres, @"the tyre set saved");
    LBCheck(@"the server has it, bought for 400", [keptTyres.tyreSetName isEqualToString:@"Winter set"] && keptTyres.date
                && LBIs(keptTyres.totalAmount, @"400"),
            keptTyres);
    LBChooseRecord(controller, tyres);
    LBType(window, @"TyreSetModel", @"Alpin 7");
    keptTyres = LBSaved(controller, tyres, @"the tyre set corrected");
    LBCheck(@"the server has its model corrected", [keptTyres.tyreModel isEqualToString:@"Alpin 7"], keptTyres.tyreModel);

    TyreChange *change = (TyreChange *)LBAddRecord(controller, [TyreChange class]);
    LBType(window, @"TyreChangeMileage", @"14500");
    LBChoose(window, @"TyreChangeTyreSet", @"Winter set");
    LBType(window, @"TyreChangeTread", @"7.5");
    TyreChange *keptChange = LBSaved(controller, change, @"the tyre change saved");
    LBCheck(@"the server has it: the set fitted, its tread", [keptChange.tyreSet.id isEqual:tyres.id] && LBIs(keptChange.tread, @"7.5"),
            keptChange);
    LBChooseRecord(controller, change);
    LBType(window, @"TyreChangeTread", @"7");
    keptChange = LBSaved(controller, change, @"the tyre change corrected");
    LBCheck(@"the server has its tread corrected", LBIs(keptChange.tread, @"7"), keptChange.tread);

    Document *document = (Document *)LBAddRecord(controller, [Document class]);
    LBType(window, @"DocumentKind", @"Insurance");
    LBType(window, @"DocumentIssuer", @"Allianz");
    LBType(window, @"DocumentNumber", @"P-1234");
    LBTypeDay(window, @"DocumentDate", LBDay([NSDate date]));
    LBTypeDay(window, @"DocumentExpires", LBAddMonths(LBDay([NSDate date]), 12));
    LBType(window, @"DocumentTotal", @"300");
    LBType(window, @"DocumentTotalCurrency", @"EUR");
    Document *keptDocument = LBSaved(controller, document, @"the document saved");
    LBCheck(@"the server has it, issued today, valid a year", [keptDocument.issuer isEqualToString:@"Allianz"]
                && [keptDocument.date isEqualToDate:LBDay([NSDate date])]
                && [keptDocument.expiresOnDate isEqualToDate:LBAddMonths(LBDay([NSDate date]), 12)] && LBIs(keptDocument.totalAmount, @"300"),
            [NSString stringWithFormat:@"%@ to %@", keptDocument.date, keptDocument.expiresOnDate]);
    LBChooseRecord(controller, document);
    LBType(window, @"DocumentNumber", @"P-1235");
    keptDocument = LBSaved(controller, document, @"the document corrected");
    LBCheck(@"the server has its number corrected", [keptDocument.documentNumber isEqualToString:@"P-1235"], keptDocument.documentNumber);

    MeterReading *reading = (MeterReading *)LBAddRecord(controller, [MeterReading class]);
    LBType(window, @"MeterReadingMileage", @"14600");
    MeterReading *keptReading = LBSaved(controller, reading, @"the meter reading saved");
    LBCheck(@"the server has it", LBIs(keptReading.mileageQuantity, @"14600"), keptReading);
    LBChooseRecord(controller, reading);
    LBType(window, @"MeterReadingMileage", @"14650");
    keptReading = LBSaved(controller, reading, @"the meter reading corrected");
    LBCheck(@"the server has it corrected", LBIs(keptReading.mileageQuantity, @"14650"), keptReading.mileageQuantity);

    /* A file attached to it, saved; then removed. */
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"odometer.txt"]];
    [[@"14650 km" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:file atomically:YES];
    NSError *error = nil;
    LBCheck(@"a file attached to it", [controller attachFileAtURL:file toRecord:reading error:&error] != nil, error);
    LBSaved(controller, reading, @"saved with it");
    NSArray *files = LBServerObjects([Attachment class], [NSPredicate predicateWithFormat:@"%K == %@",
                                                                       NSStringFromSelector(@selector(fileName)), @"odometer.txt"]);
    LBCheck(@"the server has the file", files.count == 1 && [[files.firstObject content] length] == 8, files);
    LBCheck(@"listed beside it, saved", [[controller.attachments.arrangedObjects valueForKey:NSStringFromSelector(@selector(fileName))]
                                            isEqualToArray:@[ @"odometer.txt" ]],
            controller.attachments.arrangedObjects);
    [controller.attachments setSelectionIndex:0];
    LBSpin();
    NSButton *removeFile = (NSButton *)LBControl(window.contentView, @"removeAttachment");
    LBCheck(@"Remove enabled for the file chosen", removeFile.isEnabled,
            [NSString stringWithFormat:@"canRemove %d, chosen %lu of %lu, button %@", controller.attachments.canRemove,
                                       (unsigned long)controller.attachments.selectionIndexes.count,
                                       (unsigned long)[controller.attachments.arrangedObjects count], removeFile]);
    LBClick(window, @"removeAttachment");
    LBSaved(controller, reading, @"saved without it");
    LBCheck(@"the server has it no more", [LBServerObjects([Attachment class], [NSPredicate predicateWithFormat:@"%K == %@",
                                                                                 NSStringFromSelector(@selector(fileName)), @"odometer.txt"])
                                              count] == 0,
            nil);

    Inspection *inspection = (Inspection *)LBAddRecord(controller, [Inspection class]);
    LBType(window, @"InspectionMileage", @"14700");
    LBChoose(window, @"InspectionChecklist", @"Monthly check");
    NSArray<LBAnswerRow *> *rows = controller.answersController.rows;
    LBCheck(@"its checklist's questions, in order, to answer", rows.count == 2 && [rows[0].questionText isEqualToString:@"Which lights are out?"],
            [rows valueForKey:NSStringFromSelector(@selector(questionText))]);
    NSTableView *answers = (NSTableView *)LBControl(window.contentView, @"answersTable");
    [answers selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    LBSpin();
    NSTableView *options = (NSTableView *)LBControl(window.contentView, @"answerOptionsTable");
    LBCheck(@"an any-of question offers its options", options.numberOfRows == 2, @(options.numberOfRows));
    rows[0].choices[0].chosen = YES;
    [answers selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    LBSpin();
    LBChoose(window, @"answerYesNo", @"Yes");
    rows[1].note = @"front left worn";
    LBCheck(@"answered: an option, and yes", [rows[0].answerText isEqualToString:@"Low beams"] && [rows[1].answerText isEqualToString:@"Yes"],
            [rows valueForKey:NSStringFromSelector(@selector(answerText))]);
    Inspection *keptInspection = LBSaved(controller, inspection, @"the inspection saved");
    NSMutableDictionary *said = [NSMutableDictionary dictionary];
    for (Answer *answer in keptInspection.answers) {
        said[answer.question.questionText ?: @"?"] = answer.yesNo ?: [[answer.options valueForKey:@"optionText"] anyObject] ?: @"";
    }
    LBCheck(@"the server has its answers", [said isEqualToDictionary:(@{ @"Which lights are out?": @"Low beams", @"Are the tyres fine?": @"Yes" })],
            said);
    LBChooseRecord(controller, inspection);
    [answers selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
    LBSpin();
    LBChoose(window, @"answerYesNo", @"No");
    keptInspection = LBSaved(controller, inspection, @"the inspection corrected");
    NSString *tyresFine = nil;
    for (Answer *answer in LBServerObjects([Answer class], [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(inspection)),
                                                                          keptInspection])) {
        if ([answer.question.questionText isEqualToString:@"Are the tyres fine?"]) tyresFine = answer.yesNo;
    }
    LBCheck(@"the server has the answer corrected", [tyresFine isEqualToString:@"No"], tyresFine);

    /* The first fill-up, corrected: what was charged for it, in dollars. */
    FillUp *fillUp = nil;
    for (Record *record in controller.records.arrangedObjects) {
        if ([record isKindOfClass:[FillUp class]]) fillUp = (FillUp *)record;
    }
    LBChooseRecord(controller, fillUp);
    LBType(window, @"FillUpCharged", @"65");
    LBType(window, @"FillUpChargedCurrency", @"USD");
    FillUp *keptFillUp = LBSaved(controller, fillUp, @"the fill-up corrected");
    LBCheck(@"the server has what was charged", LBIs(keptFillUp.chargedAmount, @"65") && [keptFillUp.chargedCurrency isEqualToString:@"USD"],
            keptFillUp.chargedAmount);

    /* The meter reading removed, a file attached to it again: the file
       goes with it. */
    LBChooseRecord(controller, reading);
    LBCheck(@"a file attached again", [controller attachFileAtURL:file toRecord:reading error:&error] != nil, error);
    LBSaved(controller, reading, @"saved with it");
    NSUUID *readingID = reading.id;
    LBClick(window, @"removeRecord");
    NSMutableArray *deleting = [NSMutableArray array];
    for (NSManagedObject *object in controller.store.context.deletedObjects) {
        [deleting addObject:[NSString stringWithFormat:@"%@%@", object.entity.name,
                                                       [object isKindOfClass:[Answer class]] ? [NSString stringWithFormat:@" of %@", ((Answer *)object).inspection.entity.name] : @""]];
    }
    LBClick(window, @"save");
    LBCheck(@"a record removed, its file with it, on the server too", !controller.lastError
                && [LBServerObjects([MeterReading class], [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(id)),
                                                                         readingID]) count] == 0
                && [LBServerObjects([Attachment class], [NSPredicate predicateWithFormat:@"%K == %@",
                                                                      NSStringFromSelector(@selector(fileName)), @"odometer.txt"]) count] == 0,
            [NSString stringWithFormat:@"%@ deleting %@", controller.lastError.localizedDescription, deleting]);
}

/* The view drawn into a bitmap, as it is now. */
static BOOL LBDrawn(NSView *view) {
    NSBitmapImageRep *drawn = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:drawn];
    return drawn.pixelsWide > 0;
}

/* A calendar item of nothing of Logbook's, for the view alone. */
@interface LBPlainItem : NSObject <UDCalendarItem>
@property (nonatomic, copy) NSDate *calendarDate;
@property (nonatomic, copy) NSString *calendarTitle;
@property (nonatomic, strong) NSColor *calendarColor;
@property (nonatomic) BOOL calendarAllDay;
@end

@implementation LBPlainItem
@end

@interface LBPlainItems : NSObject <UDCalendarViewDataSource>
@property (nonatomic, copy) NSArray<LBPlainItem *> *all;
@property (nonatomic, copy) NSDate *askedFrom;
@property (nonatomic, copy) NSDate *askedTo;
@end

@implementation LBPlainItems
- (NSArray<id<UDCalendarItem>> *)calendarView:(UDCalendarView *)view itemsFrom:(NSDate *)start to:(NSDate *)end {
    self.askedFrom = start;
    self.askedTo = end;
    NSMutableArray *those = [NSMutableArray array];
    for (LBPlainItem *item in _all) {
        NSDate *day = [view dayOfItem:item];
        if ([day compare:start] != NSOrderedAscending && [day compare:end] == NSOrderedAscending) [those addObject:item];
    }
    return those;
}
@end

/* UDCalendarView alone, made in code, pointed at a data source of plain
   items: what it asks for, shows, and draws in each mode. */
static void LBCalendarViewAlone(void) {
    NSCalendar *gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    gregorian.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Almaty"];
    gregorian.firstWeekday = 2;
    NSDateComponents *parts = [[NSDateComponents alloc] init];
    parts.year = 2026;
    parts.month = 10;
    parts.day = 21;
    parts.hour = 9;
    parts.minute = 30;
    LBPlainItem *timed = [[LBPlainItem alloc] init];
    timed.calendarDate = [gregorian dateFromComponents:parts];
    timed.calendarTitle = @"Dentist";
    timed.calendarColor = [NSColor blueColor];
    NSCalendar *utc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    utc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    parts.hour = 0;
    parts.minute = 0;
    parts.day = 23;
    LBPlainItem *allDay = [[LBPlainItem alloc] init];
    allDay.calendarDate = [utc dateFromComponents:parts];
    allDay.calendarTitle = @"Holiday";
    allDay.calendarColor = [NSColor redColor];
    allDay.calendarAllDay = YES;
    LBPlainItems *source = [[LBPlainItems alloc] init];
    source.all = @[ timed, allDay ];

    UDCalendarView *view = [[UDCalendarView alloc] initWithFrame:NSMakeRect(0, 0, 700, 420)];
    /* In a window of its own, never shown, as a view is drawn. */
    NSWindow *host = [[NSWindow alloc] initWithContentRect:view.frame styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered
                                                     defer:NO];
    host.releasedWhenClosed = NO;
    [host.contentView addSubview:view];
    view.calendar = gregorian;
    view.allDayTimeZone = utc.timeZone;
    view.dataSource = source;
    view.date = timed.calendarDate;
    parts.day = 23;
    LBCheck(@"alone: an all-day item's day read in its zone", [[view dayOfItem:allDay] isEqualToDate:[gregorian dateFromComponents:parts]],
            [view dayOfItem:allDay]);
    LBCheck(@"alone: a month asks for its six weeks, from a Monday", view.mode == UDCalendarModeMonth
                && [gregorian component:NSCalendarUnitWeekday fromDate:source.askedFrom] == 2
                && [gregorian components:NSCalendarUnitDay fromDate:source.askedFrom toDate:source.askedTo options:0].day == 42
                && view.items.count == 2 && LBDrawn(view),
            view.rangeTitle);
    view.mode = UDCalendarModeWeek;
    LBCheck(@"alone: a week asks for its seven days, both items in it", [gregorian components:NSCalendarUnitDay fromDate:source.askedFrom
                                                                                       toDate:source.askedTo options:0].day == 7
                && view.items.count == 2 && LBDrawn(view),
            view.rangeTitle);
    view.mode = UDCalendarModeDay;
    LBCheck(@"alone: a day, its item at its time", view.items.count == 1 && view.items.firstObject == timed && LBDrawn(view)
                && [view.rangeTitle containsString:@"21"],
            view.rangeTitle);
    [view goForward:nil];
    [view goForward:nil];
    LBCheck(@"alone: two days on, the all-day item", view.items.count == 1 && view.items.firstObject == allDay, view.rangeTitle);
    [view removeFromSuperview];
    [host close];
}

/* The kinds of the month's entries, a set. */
static NSSet<NSNumber *> *LBKindsOf(NSArray<LBCalendarEntry *> *entries) {
    return [NSSet setWithArray:[entries valueForKey:NSStringFromSelector(@selector(kind))]];
}

/* The Calendar tab, as a user: this month's done and cancelled reminders
   and records, each on its day; months on, the open one and what the
   schedule plans; a day chosen. */
static void LBCalendarSteps(LBMainWindowController *controller) {
    NSWindow *window = controller.window;
    NSTabView *tabs = (NSTabView *)LBControl(window.contentView, @"tabs");
    [tabs selectTabViewItemWithIdentifier:@"calendar"];
    LBSpin();
    LBCalendarController *calendar = controller.calendarController;
    LBClick(window, @"calendarToday");
    NSArray<LBCalendarEntry *> *month = calendar.entries;
    NSSet *kinds = LBKindsOf(month);
    LBCheck(@"this month: reminders done, cancelled, and records", [kinds containsObject:@(LBCalendarDone)]
                && [kinds containsObject:@(LBCalendarCancelled)] && [kinds containsObject:@(LBCalendarRecord)],
            [month valueForKey:NSStringFromSelector(@selector(kindText))]);
    LBCalendarEntry *done = nil;
    for (LBCalendarEntry *entry in month) {
        if (entry.kind == LBCalendarDone && [entry.title isEqualToString:@"Oil change"]) done = entry;
    }
    LBCheck(@"the oil change done by the service, whose driver is said", [done.detail hasPrefix:@"by Service"]
                && [done.detail containsString:controller.store.user.lbTitle],
            done.detail);
    NSTextField *title = (NSTextField *)LBControl(window.contentView, @"calendarTitle");
    NSTableView *list = (NSTableView *)LBControl(window.contentView, @"calendarEntries");
    LBCheck(@"its month said, its entries listed", title.stringValue.length && list.numberOfRows == (NSInteger)calendar.listed.count
                && calendar.listed.count > 0,
            title.stringValue);
    UDCalendarView *view = calendar.calendarView;
    LBCheck(@"the month drawn", LBDrawn(view), nil);
    NSDate *doneDay = [view.calendar startOfDayForDate:done.moment];
    view.chosenDay = doneDay;
    [calendar calendarView:view didChooseDay:doneDay];
    BOOL onlyThatDay = calendar.listed.count > 0;
    for (LBCalendarEntry *entry in calendar.listed) {
        if (entry.moment && ![[view.calendar startOfDayForDate:entry.moment] isEqualToDate:doneDay]) onlyThatDay = NO;
    }
    LBCheck(@"a day chosen: its entries listed, only", onlyThatDay, [calendar.listed valueForKey:NSStringFromSelector(@selector(dayText))]);
    view.chosenDay = nil;
    [calendar calendarView:view didChooseDay:nil];

    /* A week, a day: the same items at their times. */
    NSSegmentedControl *modes = (NSSegmentedControl *)LBControl(window.contentView, @"calendarMode");
    view.date = doneDay;
    [modes setSelectedSegment:UDCalendarModeWeek];
    [modes sendAction:modes.action to:modes.target];
    LBSpin();
    NSInteger days = [view.calendar components:NSCalendarUnitDay fromDate:view.rangeStart toDate:view.rangeEnd options:0].day;
    BOOL timed = NO;
    for (id<UDCalendarItem> item in view.items) {
        if (![item respondsToSelector:@selector(calendarAllDay)] || !item.calendarAllDay) timed = YES;
    }
    LBCheck(@"Week: seven days, the done service and the records at their times", view.mode == UDCalendarModeWeek && days == 7 && timed
                && LBDrawn(view) && [title.stringValue isEqualToString:view.rangeTitle],
            title.stringValue);
    if (getenv("LB_SCREENSHOT")) {
        NSString *path = [[@(getenv("LB_SCREENSHOT")) stringByDeletingPathExtension] stringByAppendingString:@"-week.png"];
        system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%@'", (long)window.windowNumber, path].UTF8String);
    }
    NSDate *weekStart = view.rangeStart;
    LBClick(window, @"calendarForward");
    LBCheck(@"forward a week", [view.calendar components:NSCalendarUnitDay fromDate:weekStart toDate:view.rangeStart options:0].day == 7,
            view.rangeTitle);
    LBClick(window, @"calendarBack");
    [modes setSelectedSegment:UDCalendarModeDay];
    [modes sendAction:modes.action to:modes.target];
    LBSpin();
    days = [view.calendar components:NSCalendarUnitDay fromDate:view.rangeStart toDate:view.rangeEnd options:0].day;
    LBCheck(@"Day: the day, its items listed", view.mode == UDCalendarModeDay && days == 1 && [view.rangeStart isEqualToDate:doneDay]
                && calendar.listed.count == view.items.count && view.items.count > 0 && LBDrawn(view),
            view.rangeTitle);
    if (getenv("LB_SCREENSHOT")) {
        NSString *path = [[@(getenv("LB_SCREENSHOT")) stringByDeletingPathExtension] stringByAppendingString:@"-day.png"];
        system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%@'", (long)window.windowNumber, path].UTF8String);
    }
    LBClick(window, @"calendarForward");
    LBCheck(@"forward a day", [view.calendar components:NSCalendarUnitDay fromDate:doneDay toDate:view.rangeStart options:0].day == 1,
            view.rangeTitle);

    /* Back to the month; a day double-clicked there is shown. */
    [modes setSelectedSegment:UDCalendarModeMonth];
    [modes sendAction:modes.action to:modes.target];
    view.date = doneDay;
    NSPoint inDay = NSZeroPoint;
    for (CGFloat y = 30; y < NSHeight(view.bounds) && NSEqualPoints(inDay, NSZeroPoint); y += 10) {
        for (CGFloat x = 10; x < NSWidth(view.bounds); x += 10) {
            if ([[view dayAtPoint:NSMakePoint(x, y)] isEqualToDate:doneDay]) {
                inDay = NSMakePoint(x, y);
                break;
            }
        }
    }
    NSPoint at = [view convertPoint:inDay toView:nil];
    NSEvent *twice = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:at modifierFlags:0 timestamp:0
                                     windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:2 pressure:1];
    [view mouseDown:twice];
    LBCheck(@"a day double-clicked in the month: that day shown, the mode said", view.mode == UDCalendarModeDay
                && [view.rangeStart isEqualToDate:doneDay] && modes.selectedSegment == UDCalendarModeDay,
            view.rangeTitle);
    [modes setSelectedSegment:UDCalendarModeMonth];
    [modes sendAction:modes.action to:modes.target];
    if (getenv("LB_SCREENSHOT")) {
        NSString *path = [[@(getenv("LB_SCREENSHOT")) stringByDeletingPathExtension] stringByAppendingString:@"-calendar.png"];
        system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%@'", (long)window.windowNumber, path].UTF8String);
    }
    NSMutableSet *ahead = [NSMutableSet set];
    for (NSInteger i = 0; i < 12; i++) {
        LBClick(window, @"calendarForward");
        BOOL firstPlanned = ![ahead containsObject:@(LBCalendarPlanned)] && [LBKindsOf(calendar.entries) containsObject:@(LBCalendarPlanned)];
        [ahead unionSet:LBKindsOf(calendar.entries)];
        if (firstPlanned && getenv("LB_SCREENSHOT")) {
            NSString *path = [[@(getenv("LB_SCREENSHOT")) stringByDeletingPathExtension] stringByAppendingString:@"-planned.png"];
            system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%@'", (long)window.windowNumber, path].UTF8String);
        }
    }
    LBCheck(@"months on: the open reminder, and what the schedule plans", [ahead containsObject:@(LBCalendarOpen)]
                && [ahead containsObject:@(LBCalendarPlanned)],
            ahead);
    LBClick(window, @"calendarToday");

    /* Another vehicle of the user's, read today elsewhere: All Vehicles
       shows both, each entry with its vehicle. */
    NSManagedObjectContext *there = LBServerSide.context;
    /* What it read before, read again: the model's rules check it all. */
    for (NSManagedObject *object in there.registeredObjects.allObjects) [there refreshObject:object mergeChanges:NO];
    User *user = [LBServerObjects([User class], [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(email)),
                                                                  controller.store.user.email]) firstObject];
    Vehicle *polo = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Vehicle class]) inManagedObjectContext:there];
    polo.id = [NSUUID UUID];
    polo.vehicleName = @"Self-test Polo";
    polo.make = @"Volkswagen";
    polo.carModel = @"Polo VI";
    polo.manufactureYear = 2019;
    polo.fuel = @"Petrol";
    polo.owner = user;
    MeterReading *read = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([MeterReading class])
                                                       inManagedObjectContext:there];
    read.id = [NSUUID UUID];
    read.vehicle = polo;
    read.enteredBy = user;
    read.driver = user;
    read.timestamp = [NSDate date];
    read.mileageQuantity = [NSDecimalNumber decimalNumberWithString:@"80000"];
    read.mileageDistanceUnit = [LBServerObjects([DistanceUnit class], [NSPredicate predicateWithFormat:@"%K == %@",
                                                                                 NSStringFromSelector(@selector(code)), @"km"]) firstObject];
    NSError *error = nil;
    LBCheck(@"another vehicle of the user's, read today, elsewhere", [LBServerSide save:&error], error);
    [controller.vehicles fetch:nil];
    LBSpin();
    [controller readAgain];
    LBClick(window, @"calendarAllVehicles");
    NSSet *vehicles = [NSSet setWithArray:[calendar.entries valueForKey:NSStringFromSelector(@selector(vehicleTitle))]];
    BOOL said = NO;
    for (id<UDCalendarItem> item in view.items) {
        if ([item.calendarTitle hasPrefix:@"Self-test Polo: "]) said = YES;
    }
    LBCheck(@"All Vehicles: both vehicles' entries in the month, each said with its vehicle",
            calendar.allVehicles && said && [vehicles containsObject:@"Self-test Golf"] && [vehicles containsObject:@"Self-test Polo"],
            vehicles);
    if (getenv("LB_SCREENSHOT")) {
        NSString *path = [[@(getenv("LB_SCREENSHOT")) stringByDeletingPathExtension] stringByAppendingString:@"-all.png"];
        system([NSString stringWithFormat:@"screencapture -x -o -l %ld '%@'", (long)window.windowNumber, path].UTF8String);
    }
    LBClick(window, @"calendarAllVehicles");
    vehicles = [NSSet setWithArray:[calendar.entries valueForKey:NSStringFromSelector(@selector(vehicleTitle))]];
    LBCheck(@"and off: the chosen vehicle's only", !calendar.allVehicles && [vehicles isEqualToSet:[NSSet setWithObject:@"Self-test Golf"]],
            vehicles);
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
    LBAttachmentSteps(controller, kept);
    LBPreferenceSteps(controller);
    LBListSteps(controller);
    LBReportDataSteps(controller, @"Self-test Golf");
    LBReportSteps(controller);
    LBReminderSteps(controller, kept);
    LBKindSteps(controller);
    LBCalendarViewAlone();
    LBCalendarSteps(controller);
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
