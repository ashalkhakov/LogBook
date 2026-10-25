#import "LBSelfTest.h"
#import "LBConnectPanel.h"
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
#import "UDQuantityField.h"
#import "LBCalendar.h"
#import "LBProcedures.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"
#import "ExpenseKind+CoreDataClass.h"
#import "Option+CoreDataClass.h"
#import "ExchangeRate+CoreDataClass.h"
#import "LBStockWindowController.h"
#import "LBStockItemWindowController.h"
#import "LBStockOrderWindowController.h"
#import "LBStockCountWindowController.h"
#import "LBCatalogSettingsWindowController.h"
#import "LBStockDisplay.h"

NSURL *LBSelfTestRoot;
/* The user's saved settings as the self-test began. */
static NSDictionary *LBSavedSettings;

static NSDictionary *LBSavedSettingsNow(void) {
    NSString *domain = [NSBundle mainBundle].bundleIdentifier;
    return domain ? [[NSUserDefaults standardUserDefaults] persistentDomainForName:domain] ?: @{} : @{};
}

void LBSelfTestBegin(NSURL *root) {
    LBSelfTestRoot = root;
    LBSavedSettings = LBSavedSettingsNow();
    /* A server with no sign-in: the user the app is, whoever the Mac's user
       said they were. */
    LBSetDefault(@"LBUser", @"self-test@example.org");
}

void LBSetDefault(NSString *key, id value) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (!LBSelfTestRoot) {
        [defaults setObject:value forKey:key];
        return;
    }
    NSMutableDictionary *run = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) run[key] = value;
    else [run removeObjectForKey:key];
    [defaults removeVolatileDomainForName:NSArgumentDomain];
    [defaults setVolatileDomain:run forName:NSArgumentDomain];
}

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

/* That store, opened the first time it is asked for. */
static NSManagedObjectContext *LBServerContext(void) {
    if (!LBServerSide) {
        LBServerSide = [[LBStore alloc] initWithServiceRoot:LBSelfTestRoot signIn:nil];
        if (![LBServerSide open:NULL]) LBServerSide = nil;
    }
    return LBServerSide.context;
}

static Vehicle *LBVehicleNamed(NSString *name) {
    if (!LBServerContext()) return nil;
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
    LBCheck(@"filled in: now, here (this Mac's time zone), its driver the user, in the user's units",
            fillUp.timestamp && [fillUp.timeZone isEqualToString:[NSTimeZone localTimeZone].name] && fillUp.driver == user
                && fillUp.mileageDistanceUnit && fillUp.mileageDistanceUnit == user.distanceUnit
                && fillUp.volumeVolumeUnit && fillUp.volumeVolumeUnit == user.volumeUnit && fillUp.vehicle && fillUp.enteredBy == user,
            [NSString stringWithFormat:@"%@ %@ %@ %@", fillUp.timestamp, fillUp.driver.email, fillUp.mileageDistanceUnit.code,
                                       fillUp.volumeVolumeUnit.code]);
    NSPopUpButton *driver = (NSPopUpButton *)LBControl(window.contentView, @"FillUpDriver");
    LBCheck(@"the driver's pop-up shows the user", driver.selectedItem.representedObject == user, driver.titleOfSelectedItem);
    NSTextField *date = (NSTextField *)LBControl(window.contentView, @"FillUpTimestamp");
    LBCheck(@"its date shown", date.stringValue.length > 0 && [date.formatter isKindOfClass:[NSDateFormatter class]], date.stringValue);
    LBType(window, @"FillUpMileageValue", @"12345");
    LBType(window, @"FillUpVolumeValue", @"40");
    LBType(window, @"FillUpFuel", @"Petrol 95");
    LBType(window, @"FillUpTotalValue", @"60");
    LBType(window, @"FillUpStation", @"Shell");
    LBCheck(@"numbers typed are decimals of the fill-up",
            [fillUp.mileageQuantity isKindOfClass:[NSDecimalNumber class]] && fillUp.mileageQuantity.integerValue == 12345
                && fillUp.volumeQuantity.integerValue == 40 && fillUp.totalAmount.integerValue == 60,
            [NSString stringWithFormat:@"%@ (%@) %@ %@", fillUp.mileageQuantity, [fillUp.mileageQuantity class], fillUp.volumeQuantity,
                                       fillUp.totalAmount]);
    LBType(window, @"FillUpMileageUnit", @"mi");
    LBCheck(@"a unit chosen is the fill-up's", [fillUp.mileageDistanceUnit.code isEqualToString:@"mi"], fillUp.mileageDistanceUnit.code);
    LBType(window, @"FillUpMileageUnit", @"km");
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
    /* As first opened: the units the user has, shown. */
    NSPopUpButton *distance = (NSPopUpButton *)LBControl(preferences.contentView, @"distanceUnit");
    NSPopUpButton *volume = (NSPopUpButton *)LBControl(preferences.contentView, @"volumeUnit");
    LBCheck(@"a unit may be none: the first item is None", [distance.itemTitles.firstObject isEqualToString:@"None"]
                                                             && [volume.itemTitles.firstObject isEqualToString:@"None"],
            distance.itemTitles);
    User *user = controller.store.user;
    NSString *system = [[NSLocale currentLocale] objectForKey:NSLocaleMeasurementSystem];
    NSString *distanceCode = [system isEqualToString:@"U.S."] || [system isEqualToString:@"U.K."] ? @"mi" : @"km";
    NSString *volumeCode = [system isEqualToString:@"U.S."] ? @"gal (US)" : @"L";
    LBCheck(@"a user with no units took this Mac's at sign-in", [user.distanceUnit.code isEqualToString:distanceCode]
                && [user.volumeUnit.code isEqualToString:volumeCode],
            [NSString stringWithFormat:@"%@, %@ (%@)", user.distanceUnit.code, user.volumeUnit.code, system]);
    LBCheck(@"first opened: the user's units shown", user.distanceUnit && user.volumeUnit
                && [distance.titleOfSelectedItem isEqualToString:user.distanceUnit.lbTitle]
                && [volume.titleOfSelectedItem isEqualToString:user.volumeUnit.lbTitle],
            [NSString stringWithFormat:@"shown %@ and %@, the user's %@ and %@", distance.titleOfSelectedItem, volume.titleOfSelectedItem,
                                       user.distanceUnit.lbTitle, user.volumeUnit.lbTitle]);
    LBType(preferences, @"currencyUnit", @"eur");
    LBType(preferences, @"personName", @"Sam Driver");
    LBClick(preferences, @"done");
    LBCheck(@"saved and closed", !preferences.isVisible && !controller.lastError && !controller.store.context.hasChanges,
            controller.lastError.localizedRecoverySuggestion ?: controller.lastError);
    LBCheck(@"the user's currency", [controller.store.user.currency isEqualToString:@"EUR"], controller.store.user.currency);
    there = [LBServerObjects([User class], [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(email)),
                                                          controller.store.user.email]) firstObject];
    LBCheck(@"the user's name, on the server", [there.personName isEqualToString:@"Sam Driver"], there.personName);
    /* Opened again: what was saved, shown. */
    [NSApp sendAction:@selector(showPreferences:) to:nil from:nil];
    LBSpin();
    NSTextField *name = (NSTextField *)LBControl(preferences.contentView, @"personName");
    LBCheck(@"opened again: the name saved, shown", preferences.isVisible && [name.stringValue isEqualToString:@"Sam Driver"],
            name.stringValue);
    [preferences close];
}

/* The objects of an entity the server has, as the predicate says. */
static NSArray *LBServerObjects(Class cls, NSPredicate *predicate) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = predicate;
    NSArray *objects = [LBServerContext() executeFetchRequest:fetch error:NULL] ?: @[];
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
    LBType(window, @"scheduleEveryValue", @"15000");
    LBType(window, @"scheduleEveryUnit", @"km");
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
    LBType(window, @"ServiceItemCostValue", @"50");
    LBCheck(@"its task and cost typed", [item.task isEqualToString:@"Oil change"] && item.costAmount.integerValue == 50, item.task);
    LBCheck(@"with no odometer reading yet, a warning that no next reminder would be made",
            [controller reminderWarnings].count == 1 && [[controller reminderWarnings].firstObject.localizedDescription containsString:@"Oil change"],
            [controller reminderWarnings]);
    LBType(window, @"ServiceMileageValue", @"13000");
    LBType(window, @"ServiceMileageUnit", @"km");
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
/* The window as drawn, written as a TIFF named so into the folder
   LB_SNAPSHOTS names, when it names one: to look at, and for the docs. */
static void LBSnapshot(NSWindow *window, NSString *name) {
    NSString *folder = [NSProcessInfo processInfo].environment[@"LB_SNAPSHOTS"];
    if (!folder.length) return;
    /* The frame view: it draws the window's background, which the
       content's text is drawn over. */
    NSView *view = [window.contentView superview] ?: window.contentView;
    NSBitmapImageRep *image = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
    [[image TIFFRepresentation] writeToFile:[folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"tiff"]]
                                 atomically:YES];
}

static NSDecimalNumber *LBN10(void) {
    return [NSDecimalNumber decimalNumberWithString:@"10"];
}

static NSWindow *LBStockWindow(void) {
    for (NSWindow *window in NSApp.windows) {
        if (window.isVisible && [window.windowController isKindOfClass:[LBStockWindowController class]]) return window;
    }
    return nil;
}

/* What the server has of the class whose key is the object's. */
static id LBServerOf(NSManagedObject *object) {
    return [LBServerObjects([object class], [NSPredicate predicateWithFormat:@"id == %@", [object valueForKey:@"id"]]) firstObject];
}

/* The stock window's opened window of the class, shown. */
static id LBOpened(LBStockWindowController *stock, Class cls) {
    LBSpin();
    LBStockEditor *editor = [stock windowOfClass:cls];
    LBCheck([NSString stringWithFormat:@"a %@ open", NSStringFromClass(cls)], editor.window.isVisible, nil);
    return editor;
}

/* Saved, as a user does, and nothing refused. */
static BOOL LBSavedIn(LBStockEditor *editor, NSString *what) {
    LBClick(editor.window, @"save");
    BOOL saved = !editor.context.hasChanges && !editor.lastError;
    LBCheck(what, saved, editor.lastError.localizedRecoverySuggestion ?: editor.lastError);
    return saved;
}

/* Typed into a cell of a table's chosen row, as a user does: the cell
   edited, its text typed over. */
static void LBTypeInCell(NSWindow *window, NSString *table, NSInteger column, NSString *text) {
    NSTableView *view = (NSTableView *)LBControl(window.contentView, table);
    NSInteger row = view.selectedRow;
    LBCheck([NSString stringWithFormat:@"a row chosen in %@", table], view && row >= 0, nil);
    if (!view || row < 0) return;
    [view editColumn:column row:row withEvent:nil select:YES];
    LBTypeInRow(window, [NSString stringWithFormat:@"%@'s cell", table], text);
}

/* The catalog's settings, in their window (docs/STOCK.md): its name,
   currency, prefix and size unit; a warehouse with two shelves; a
   category; a supplier and a customer, its address typed before anything
   is saved (the new contact and its new address refer to each other, sent
   in one change set). Saved, the server's, and the stock window told. */
static void LBStockSettingsSteps(LBStockWindowController *stock, LBCatalogSettingsWindowController *settings) {
    NSWindow *window = settings.window;
    settings.quiet = YES;
    LBType(window, @"catalogName", @"Self-test Workshop");
    LBType(window, @"catalogCurrency", @"USD");
    LBType(window, @"catalogPrefix", @"GAR");
    LBChoose(window, @"catalogSizeUnit", @"cm");
    LBClick(window, @"addWarehouse");
    LBTypeInRow(window, @"the warehouse's name", @"Garage");
    LBClick(window, @"addLocation");
    LBTypeInRow(window, @"a location's name", @"Shelf A");
    LBClick(window, @"addLocation");
    LBTypeInRow(window, @"a location's name", @"Shelf B");
    LBClick(window, @"addCategory");
    LBTypeInRow(window, @"the category's name", @"Fasteners");
    LBClick(window, @"addContact");
    LBTypeInRow(window, @"the contact's name", @"Parts Ltd");
    /* Its Supplier box ticked, as a click in the table's cell does. */
    [settings.contactList.selectedObjects.firstObject setValue:@YES forKey:@"lb_isSupplier"];
    LBClick(window, @"addContact");
    LBTypeInRow(window, @"the contact's name", @"Bob's Garage");
    [settings.contactList.selectedObjects.firstObject setValue:@YES forKey:@"lb_isCustomer"];
    LBType(window, @"contactShipTo", @"1 Yard Lane");
    LBSavedIn(settings, @"the settings saved");
    Catalog *kept = LBServerOf(settings.catalog);
    NSMutableArray *places = [NSMutableArray array];
    for (Warehouse *warehouse in kept.warehouses) {
        for (Location *place in warehouse.locations) [places addObject:place.lbTitle];
    }
    [places sortUsingSelector:@selector(compare:)];
    LBCheck(@"the server has its name, currency, prefix, size unit, warehouses and locations",
            [kept.catalogName isEqualToString:@"Self-test Workshop"] && [kept.currency isEqualToString:@"USD"]
                && [kept.documentPrefix isEqualToString:@"GAR"] && [kept.sizeUnit.code isEqualToString:@"cm"]
                && [places isEqualToArray:@[ @"Garage / Shelf A", @"Garage / Shelf B", @"Main / Default" ]],
            places);
    LBCheck(@"its category", [[kept.categories.anyObject categoryName] isEqualToString:@"Fasteners"], kept.categories);
    Contact *bobs = nil, *parts = nil;
    for (Contact *contact in kept.contacts) {
        if ([contact.contactName isEqualToString:@"Bob's Garage"]) bobs = contact;
        if ([contact.contactName isEqualToString:@"Parts Ltd"]) parts = contact;
    }
    LBCheck(@"its contacts: a supplier, a customer", parts.supplier && !parts.customer && bobs.customer,
            [NSString stringWithFormat:@"%@ %@", parts, bobs]);
    LBCheck(@"the customer shipped to 1 Yard Lane", [bobs.shippingAddress.addressLines isEqualToString:@"1 Yard Lane"],
            bobs.shippingAddress);
    LBCheck(@"the stock window told: it lists the catalog by its new name", [stock.catalog.catalogName isEqualToString:@"Self-test Workshop"],
            stock.catalog.catalogName);
    [settings close];
}

/* A new item, in its window, named so, saved: its window. */
static LBStockItemWindowController *LBAddStockItem(LBStockWindowController *stock, NSString *name) {
    LBClick(stock.window, @"addItem");
    LBStockItemWindowController *card = LBOpened(stock, [LBStockItemWindowController class]);
    card.quiet = YES;
    LBType(card.window, @"itemNameField", name);
    LBSavedIn(card, [NSString stringWithFormat:@"%@ added and saved", name]);
    return card;
}

/* Stock moved in the item's window, as a user does: how many typed, the
   reason chosen, the button clicked. */
static void LBMoveStock(LBStockItemWindowController *card, NSString *button, NSString *quantity, NSString *reason) {
    [card.cardTabs selectTabViewItemWithIdentifier:@"stock"];
    LBSpin();
    LBType(card.window, @"stockQuantity", quantity);
    if (reason) LBChoose(card.window, @"stockReason", reason);
    LBClick(card.window, button);
}

/* The item's tables, as a user fills them: the supplier item made by
   choosing the supplier, its SKU, cost, pack and minimum typed; a code
   added; its weight and size; a reorder rule at Garage, due. Each saved,
   and the server's. */
static void LBStockCardSteps(LBStockItemWindowController *card) {
    NSWindow *window = card.window;
    StockItem *bolt = card.item;
    [card.cardTabs selectTabViewItemWithIdentifier:@"suppliers"];
    LBSpin();
    SupplierItem *bought = card.supplierItems.firstObject;
    LBCheck(@"its supplier item listed, preferred", card.supplierItems.count == 1 && bought.lb_isPreferred, card.supplierItems);
    [card.supplierItemList setSelectedObjects:bought ? @[ bought ] : @[]];
    LBTypeInCell(window, @"supplierItemsTable", 1, @"PL-778");
    LBTypeInCell(window, @"supplierItemsTable", 3, @"0.2");
    LBTypeInCell(window, @"supplierItemsTable", 4, @"50");
    LBTypeInCell(window, @"supplierItemsTable", 5, @"100");
    LBSavedIn(card, @"its supplier item saved");
    NSPredicate *ofBolt = [NSPredicate predicateWithFormat:@"stockItem.id == %@", bolt.id];
    SupplierItem *keptBought = [LBServerObjects([SupplierItem class], ofBolt) firstObject];
    LBCheck(@"the server has their SKU, PL-778, at 0.2 USD, in packs of 50, at least 100",
            [keptBought.supplierSKU isEqualToString:@"PL-778"] && LBIs(keptBought.supplierCostAmount, @"0.2")
                && [keptBought.supplierCostCurrency isEqualToString:@"USD"] && LBIs(keptBought.packSize, @"50")
                && LBIs(keptBought.minimumOrder, @"100"),
            keptBought);

    [card.cardTabs selectTabViewItemWithIdentifier:@"codes"];
    LBSpin();
    LBClick(window, @"addItemCode");
    LBTypeInRow(window, @"the code", @"4006381333931");
    LBSavedIn(card, @"its code saved");
    ItemCode *keptCode = [LBServerObjects([ItemCode class], ofBolt) firstObject];
    LBCheck(@"its code, a GTIN, the server's", [keptCode.codeText isEqualToString:@"4006381333931"] && [keptCode.codeKind isEqualToString:@"GTIN"],
            keptCode);

    [card.cardTabs selectTabViewItemWithIdentifier:@"size"];
    LBSpin();
    LBType(window, @"itemWeight", @"10");
    LBChoose(window, @"itemWeightUnit", @"g");
    NSDictionary *sizes = @{ @"itemLength": @"5", @"itemWidth": @"1", @"itemHeight": @"1" };
    for (NSString *size in sizes) {
        LBType(window, size, sizes[size]);
        LBChoose(window, [size stringByAppendingString:@"Unit"], @"cm");
    }
    LBSavedIn(card, @"its weight and size saved");
    StockItem *keptBolt = LBServerOf(bolt);
    LBCheck(@"its weight, 10 g, and size, 5 x 1 x 1 cm, the server's", LBIs(keptBolt.weightQuantity, @"10")
                && [keptBolt.weightWeightUnit.code isEqualToString:@"g"] && LBIs(keptBolt.lengthQuantity, @"5")
                && [keptBolt.heightSizeUnit.code isEqualToString:@"cm"],
            keptBolt.weightQuantity);

    [card.cardTabs selectTabViewItemWithIdentifier:@"reorder"];
    LBSpin();
    LBClick(window, @"addReorderRule");
    LBTypeInRow(window, @"the reorder point", @"30");
    LBTypeInCell(window, @"reorderRulesTable", 2, @"100");
    LBSavedIn(card, @"its reorder rule saved");
    ReorderRule *rule = card.reorderRules.firstObject;
    LBCheck(@"a reorder rule at Garage, below 30 up to 100: due, as the server worked it out",
            [rule.warehouse.warehouseName isEqualToString:@"Garage"] && LBIs(rule.reorderPoint, @"30") && rule.isDue,
            rule);
}

/* Sales and purchases, each in its window, as a user writes them: a sale
   to Bob of three bolts, numbered, confirmed, shipped in two from Shelf A;
   a purchase from Parts Ltd of ten brackets at a cost of 1, confirmed,
   received in two at Default. Each the server's. */
static void LBStockOrderSteps(LBStockWindowController *stock, StockItem *bolt, StockItem *bracket) {
    [stock.tabs selectTabViewItemWithIdentifier:@"saleOrders"];
    LBSpin();
    LBClick(stock.window, @"newSale");
    LBStockOrderWindowController *sale = LBOpened(stock, [LBStockOrderWindowController class]);
    sale.quiet = YES;
    NSWindow *window = sale.window;
    SaleOrder *order = (SaleOrder *)sale.order;
    LBCheck(@"a new sale, SO-GAR-0001, to Bob, in its window", [order.lb_number isEqualToString:@"SO-GAR-0001"]
                && [order.customer.lbTitle isEqualToString:@"Bob's Garage"],
            order.lb_number);
    LBCheck(@"shipped to his yard", [order.shipTo.addressLines isEqualToString:@"1 Yard Lane"], order.shipTo);
    LBClick(window, @"addLine");
    LBChoose(window, @"lineItem", @"Bolt");
    LBTypeInCell(window, @"linesTable", 1, @"3");
    SaleLine *line = sale.lineList.selectedObjects.firstObject;
    LBCheck(@"its line: 3 bolts at their price", [line.stockItem.objectID isEqual:bolt.objectID] && LBIs(line.quantity, @"3")
                                                   && LBIs(line.linePriceAmount, @"0.5"),
            line.quantity);
    LBSavedIn(sale, @"the sale saved");
    LBClick(window, @"confirmOrder");
    LBCheck(@"confirmed", [order.orderState isEqualToString:@"Confirmed"] && !sale.lastError, sale.lastError ?: order.orderState);
    LBChoose(window, @"moveAt", @"Garage / Shelf A");
    LBType(window, @"moveQuantity", @"2");
    [sale.lineList setSelectedObjects:@[ line ]];
    LBClick(window, @"moveLine");
    LBCheck(@"2 shipped from Shelf A: partly shipped", LBIs(line.shippedQuantity, @"2") && [order.lbFilled isEqualToString:@"Partly"],
            sale.lastError ?: [NSString stringWithFormat:@"shipped %@, %@", line.shippedQuantity, order.lbFilled]);
    LBClick(window, @"moveOutstanding");
    LBCheck(@"the rest shipped: fully, in two shipments", [order.lbFilled isEqualToString:@"Shipped"] && sale.documents.count == 2,
            sale.lastError ?: order.lbFilled);
    [sale close];

    NSDecimalNumber *bracketsBefore = [LBServerOf(bracket) totalQuantity];
    [stock.tabs selectTabViewItemWithIdentifier:@"purchaseOrders"];
    LBSpin();
    LBClick(stock.window, @"newPurchase");
    LBStockOrderWindowController *purchase = LBOpened(stock, [LBStockOrderWindowController class]);
    purchase.quiet = YES;
    window = purchase.window;
    PurchaseOrder *bought = (PurchaseOrder *)purchase.order;
    LBCheck(@"a new purchase, PO-GAR-0001, from Parts Ltd", [bought.lb_number isEqualToString:@"PO-GAR-0001"]
                && [bought.supplier.lbTitle isEqualToString:@"Parts Ltd"],
            bought.lb_number);
    LBClick(window, @"addLine");
    LBChoose(window, @"lineItem", @"Bracket");
    LBTypeInCell(window, @"linesTable", 1, @"10");
    LBTypeInCell(window, @"linesTable", 2, @"1");
    LBSavedIn(purchase, @"its line, 10 brackets at 1, saved");
    LBClick(window, @"confirmOrder");
    LBCheck(@"confirmed", [bought.orderState isEqualToString:@"Confirmed"] && !purchase.lastError, purchase.lastError ?: bought.orderState);
    LBChoose(window, @"moveAt", @"Main / Default");
    LBType(window, @"moveQuantity", @"4");
    [purchase.lineList setSelectedObjects:@[ purchase.lines.firstObject ]];
    LBClick(window, @"moveLine");
    LBCheck(@"4 received: partly", [bought.lbFilled isEqualToString:@"Partly"], purchase.lastError ?: bought.lbFilled);
    LBClick(window, @"moveOutstanding");
    NSDecimalNumber *brackets = [LBServerOf(bracket) totalQuantity];
    LBCheck(@"the rest received: fully, in two receipts; 10 brackets more on hand",
            [bought.lbFilled isEqualToString:@"Received"] && purchase.documents.count == 2
                && [brackets compare:[bracketsBefore decimalNumberByAdding:LBN10()]] == NSOrderedSame,
            purchase.lastError ?: brackets);
    LBSnapshot(window, @"stock-purchase");
    [purchase close];
    [stock.tabs selectTabViewItemWithIdentifier:@"saleOrders"];
    LBSpin();
    LBCheck(@"the stock window told: its sale shipped", [[stock.saleOrders.firstObject lbFilled] isEqualToString:@"Shipped"],
            [stock.saleOrders valueForKey:@"lbFilled"]);
}

/* Looking back, as a user does: the changelog, filtered by item and by
   what made the moves, before and after; a count of Shelf A, in its
   window, a bolt found of two and four brackets not expected, posted; the
   overview, what it holds weighs and takes up, its rule due ordered. */
static void LBStockLookingBackSteps(LBStockWindowController *stock, StockItem *bolt, StockItem *bracket) {
    NSWindow *window = stock.window;
    [stock.tabs selectTabViewItemWithIdentifier:@"changes"];
    LBSpin();
    NSUInteger all = [stock.changeList.arrangedObjects count];
    NSSet *catalogs = [NSSet setWithArray:[stock.catalogMoves valueForKeyPath:@"stockItem.catalog"]];
    LBCheck(@"the changelog: every move of the catalog's, and only those", all > 0 && all == stock.catalogMoves.count
                                                                            && [catalogs isEqualToSet:[NSSet setWithObject:stock.catalog]],
            @(all));
    LBChoose(window, @"changeItem", @"Bolt");
    NSArray *shown = stock.changeList.arrangedObjects;
    LBCheck(@"filtered by Bolt: its moves alone", shown.count > 0 && shown.count < all
                                                      && [[NSSet setWithArray:[shown valueForKeyPath:@"move.stockItem.itemName"]] isEqualToSet:
                                                             [NSSet setWithObject:@"Bolt"]],
            @(shown.count));
    LBChoose(window, @"changeKind", @"Shipment");
    shown = stock.changeList.arrangedObjects;
    LBCheck(@"and by Shipment: the sale's two", shown.count == 2 && [[NSSet setWithArray:[shown valueForKeyPath:@"move.lbKind"]] isEqualToSet:
                                                                         [NSSet setWithObject:@"Shipment"]],
            [shown valueForKeyPath:@"move.lbWhat"]);
    LBChoose(window, @"changeKind", @"Transfer");
    LBChange *transfer = [stock.changeList.arrangedObjects firstObject];
    LBCheck(@"the transfer, before and after at each end", [transfer.fromTitle isEqualToString:@"Main / Default: 20 → 15"]
                                                             && [transfer.toTitle isEqualToString:@"Garage / Shelf A: 0 → 5"],
            [NSString stringWithFormat:@"%@ | %@", transfer.fromTitle, transfer.toTitle]);
    LBChoose(window, @"changeItem", @"All items");
    LBChoose(window, @"changeKind", @"All");
    LBCheck(@"the filters cleared: all again", [stock.changeList.arrangedObjects count] == all, @([stock.changeList.arrangedObjects count]));
    LBSnapshot(window, @"stock-changelog");

    [stock.tabs selectTabViewItemWithIdentifier:@"counts"];
    LBSpin();
    LBClick(window, @"newCount");
    LBStockCountWindowController *counting = LBOpened(stock, [LBStockCountWindowController class]);
    counting.quiet = YES;
    NSWindow *sheet = counting.window;
    LBChoose(sheet, @"countPlace", @"Garage / Shelf A");
    LBClick(sheet, @"startCount");
    LBCountRow *boltRow = counting.rowsCounted.firstObject;
    LBCheck(@"a count of Shelf A started: the bolts held there", counting.rowsCounted.count == 1
                                                                   && [boltRow.item.itemName isEqualToString:@"Bolt"],
            [counting.rowsCounted valueForKeyPath:@"item.itemName"]);
    LBClick(sheet, @"countShowsExpected");
    LBCheck(@"what is held shown when asked: 2", LBIs(boltRow.expectedShown, @"2"), boltRow.expectedShown);
    [counting.countRows setSelectedObjects:boltRow ? @[ boltRow ] : @[]];
    LBTypeInCell(sheet, @"countRowsTable", 3, @"1");
    LBClick(sheet, @"addCountRow");
    LBChoose(sheet, @"countRowItem", @"Bracket");
    LBTypeInCell(sheet, @"countRowsTable", 3, @"4");
    LBSnapshot(sheet, @"stock-count");
    LBClick(sheet, @"postCount");
    StockCount *count = counting.posted;
    NSPredicate *atShelfA = [NSPredicate predicateWithFormat:@"location.id == %@", boltRow.location.id];
    NSMutableDictionary *held = [NSMutableDictionary dictionary];
    for (Holding *holding in LBServerObjects([Holding class], atShelfA)) held[holding.stockItem.itemName ?: @""] = holding.quantity;
    LBCheck(@"posted: CT-GAR-0001, its two adjustments; the server holds 1 bolt and 4 brackets at Shelf A",
            [count.lbNumber isEqualToString:@"CT-GAR-0001"] && count.moves.count == 2 && LBIs(held[@"Bolt"], @"1") && LBIs(held[@"Bracket"], @"4")
                && counting.rowsCounted.count == 0,
            counting.lastError ?: held);
    [counting close];
    LBSpin();
    LBCheck(@"the Counts tab lists it", [[stock.catalogCounts valueForKey:@"lbNumber"] containsObject:@"CT-GAR-0001"],
            [stock.catalogCounts valueForKey:@"lbNumber"]);

    [stock.tabs selectTabViewItemWithIdentifier:@"overview"];
    LBSpin();
    LBCheck(@"the overview: 3 items, its categories, locations, a supplier and a customer",
            stock.overviewItems.integerValue == 3 && stock.overviewCategories.integerValue == 1 && stock.overviewLocations.integerValue == 3
                && stock.overviewSuppliers.integerValue == 1 && stock.overviewCustomers.integerValue == 1,
            [NSString stringWithFormat:@"%@ %@ %@", stock.overviewItems, stock.overviewLocations, stock.overviewSuppliers]);
    LBCheck(@"the bolts' rule due, the sale and the purchase open",
            stock.rulesDue.count == 1 && [[stock.rulesDue.firstObject stockItem].itemName isEqualToString:@"Bolt"] && stock.ordersOpen.count == 2,
            [stock.ordersOpen valueForKey:@"lb_number"]);
    NSDecimalNumber *bolts = [LBServerOf(bolt) totalQuantity];
    LBCheck(@"what it holds weighs and takes up: the bolts', 10 g and 5 cm3 each, in kg and cm",
            [stock.overviewTotals.weight compare:[bolts decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"0.01"]]] == NSOrderedSame
                && [stock.overviewTotals.volume compare:[bolts decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"5"]]] == NSOrderedSame
                && [stock.overviewVolume hasSuffix:@" cm³"],
            [NSString stringWithFormat:@"%@ bolts: %@, %@", bolts, stock.overviewWeight, stock.overviewVolume]);
    LBSnapshot(window, @"stock-overview");
    LBClick(window, @"reorder");
    PurchaseOrder *draft = stock.purchaseList.selectedObjects.firstObject;
    PurchaseLine *wanted = draft.purchaseLines.anyObject;
    LBCheck(@"ordered: a draft from Parts Ltd for bolts, in packs of 50, at least 100, chosen in Purchases",
            [draft.orderState isEqualToString:@"Draft"] && [draft.supplier.lbTitle isEqualToString:@"Parts Ltd"]
                && [wanted.stockItem.itemName isEqualToString:@"Bolt"] && wanted.quantity.integerValue >= 100
                && wanted.quantity.integerValue % 50 == 0 && [stock.tabs.selectedTabViewItem.identifier isEqual:@"purchaseOrders"],
            stock.lastError ?: [NSString stringWithFormat:@"%@ %@ %@", draft.lb_number, wanted.stockItem.itemName, wanted.quantity]);
}

/* The stock windows (docs/STOCK.md): a catalog made, its settings in their
   window; items each in a window of its own, priced, moved, a kit
   assembled; orders, a count, the lists. Each saved, the server's, and the
   windows told of each other's changes. */
static void LBStockSteps(LBMainWindowController *controller) {
    [NSApp sendAction:@selector(showStock:) to:nil from:nil];
    LBSpin();
    NSWindow *window = LBStockWindow();
    LBStockWindowController *stock = window.windowController;
    LBCheck(@"the stock window", window != nil, nil);
    if (!window) return;
    stock.quiet = YES;
    LBClick(window, @"newCatalog");
    Catalog *kept = LBServerOf(stock.catalog);
    LBCheck(@"a new catalog, saved: the user's, with its warehouse Main and its Default location",
            [kept.catalogOwner.email isEqualToString:stock.store.user.email] && [[[kept.warehouses anyObject] warehouseName] isEqualToString:@"Main"]
                && [[[[[kept.warehouses anyObject] locations] anyObject] locationName] isEqualToString:@"Default"],
            stock.lastError ?: kept);
    LBCatalogSettingsWindowController *settings = LBOpened(stock, [LBCatalogSettingsWindowController class]);
    if (!settings) return;
    LBStockSettingsSteps(stock, settings);

    LBStockItemWindowController *card = LBAddStockItem(stock, @"Bolt");
    StockItem *bolt = card.item;
    NSWindow *boltWindow = card.window;
    LBType(boltWindow, @"itemPrice", @"0.5");
    LBChoose(boltWindow, @"itemCategory", @"Fasteners");
    LBChoose(boltWindow, @"itemSupplier", @"Parts Ltd");
    LBSavedIn(card, @"its price, category and supplier saved");
    StockItem *keptBolt = LBServerOf(bolt);
    LBCheck(@"its price kept, in the catalog's currency; its category; its SKU given, GAR-00001", LBIs(keptBolt.priceAmount, @"0.5")
                && [keptBolt.priceCurrency isEqualToString:@"USD"] && [keptBolt.category.categoryName isEqualToString:@"Fasteners"]
                && [keptBolt.sku isEqualToString:@"GAR-00001"],
            [NSString stringWithFormat:@"%@ %@ %@", keptBolt.priceAmount, keptBolt.priceCurrency, keptBolt.sku]);
    LBCheck(@"bought from Parts Ltd: its supplier item, preferred", [keptBolt.preferredSupplierItem.supplier.lbTitle isEqualToString:@"Parts Ltd"],
            keptBolt.preferredSupplierItem);
    LBStockCardSteps(card);
    [card.cardTabs selectTabViewItemWithIdentifier:@"stock"];
    LBSpin();
    LBChoose(boltWindow, @"stockAt", @"Main / Default");
    LBMoveStock(card, @"adjust", @"20", @"Opening");
    LBCheck(@"20 bolts brought in: on hand, held at Default, the move listed", LBIs(bolt.totalQuantity, @"20") && card.holdings.count == 1
                && card.moves.count == 1 && [[card.moves.firstObject lbWhat] isEqualToString:@"Adjustment: Opening"],
            card.lastError ?: bolt.totalQuantity);
    NSString *onHand = [(NSTextField *)LBControl(boltWindow.contentView, @"itemTotalQuantity") stringValue];
    LBCheck(@"its window shows them: On hand 20", [onHand isEqualToString:@"20"], onHand);
    LBChoose(boltWindow, @"stockTo", @"Garage / Shelf A");
    LBMoveStock(card, @"transfer", @"5", nil);
    LBCheck(@"5 moved to Garage / Shelf A: two holdings, 20 on hand still", card.holdings.count == 2 && LBIs(bolt.totalQuantity, @"20"),
            card.lastError ?: [card.holdings valueForKey:@"lbLocationTitle"]);
    LBMoveStock(card, @"adjust", @"-25", @"Lost");
    LBCheck(@"25 lost of the 15 at Default refused, in the procedure's words", [card.lastError.localizedDescription containsString:@"holds 15"]
                                                                                 && LBIs(bolt.totalQuantity, @"20"),
            card.lastError);
    LBSpin();
    StockItem *listed = [stock.items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"itemName == 'Bolt'"]].firstObject;
    LBCheck(@"the stock window told: it lists the bolts, 20 on hand", LBIs(listed.totalQuantity, @"20"), listed.totalQuantity);
    LBSnapshot(boltWindow, @"stock-item");
    [card close];

    card = LBAddStockItem(stock, @"Bracket");
    StockItem *bracket = card.item;
    LBChoose(card.window, @"stockAt", @"Main / Default");
    LBMoveStock(card, @"adjust", @"5", @"Opening");
    [card close];
    card = LBAddStockItem(stock, @"Mount");
    StockItem *mount = card.item;
    NSArray *offered = [card.components valueForKey:@"itemName"];
    LBCheck(@"a kit takes the catalog's other items", [offered containsObject:@"Bolt"] && ![offered containsObject:@"Mount"], offered);
    [card.cardTabs selectTabViewItemWithIdentifier:@"recipe"];
    LBSpin();
    LBClick(card.window, @"addKitLine");
    LBChoose(card.window, @"kitComponent", @"Bolt");
    LBClick(card.window, @"addKitLine");
    LBChoose(card.window, @"kitComponent", @"Bracket");
    LBSavedIn(card, @"its recipe saved");
    LBCheck(@"its recipe: a bolt and a bracket; it can make 5", card.kitLines.count == 2 && LBIs(mount.makeable, @"5"), mount.makeable);
    [card.cardTabs selectTabViewItemWithIdentifier:@"stock"];
    LBSpin();
    LBChoose(card.window, @"stockAt", @"Main / Default");
    LBMoveStock(card, @"assemble", @"2", nil);
    LBCheck(@"two assembled at Default: 2 mounts, 18 bolts, 3 brackets", LBIs(mount.totalQuantity, @"2")
                && LBIs([LBServerOf(bolt) totalQuantity], @"18") && LBIs([LBServerOf(bracket) totalQuantity], @"3"),
            card.lastError ?: mount.totalQuantity);
    [card close];

    LBStockOrderSteps(stock, bolt, bracket);
    LBStockLookingBackSteps(stock, bolt, bracket);
    [stock.tabs selectTabViewItemWithIdentifier:@"items"];
    LBSpin();
    LBType(window, @"itemSearch", @"mo");
    [stock search:nil];
    LBCheck(@"the list searched: Mount alone", [[stock.itemList.arrangedObjects valueForKey:@"itemName"] isEqualToArray:@[ @"Mount" ]],
            [stock.itemList.arrangedObjects valueForKey:@"itemName"]);
    LBType(window, @"itemSearch", @"");
    [stock search:nil];
    LBSnapshot(window, @"stock-items");
    [window close];
}

static void LBKindSteps(LBMainWindowController *controller) {
    NSWindow *window = controller.window;
    NSTabView *tabs = (NSTabView *)LBControl(window.contentView, @"tabs");
    [tabs selectTabViewItemWithIdentifier:@"records"];
    LBSpin();

    Expense *expense = (Expense *)LBAddRecord(controller, [Expense class]);
    LBChoose(window, @"ExpenseKind", @"Car wash");
    LBType(window, @"ExpenseMileageValue", @"14100");
    LBType(window, @"ExpenseTotalValue", @"12.50");
    LBType(window, @"ExpenseChargedValue", @"13.90");
    LBType(window, @"ExpenseChargedUnit", @"USD");
    Expense *keptExpense = LBSaved(controller, expense, @"the expense saved");
    LBCheck(@"the server has it: its kind, odometer, cost and what was charged",
            [keptExpense.expenseKind.name isEqualToString:@"Car wash"] && LBIs(keptExpense.mileageQuantity, @"14100")
                && LBIs(keptExpense.totalAmount, @"12.5") && LBIs(keptExpense.chargedAmount, @"13.9")
                && [keptExpense.chargedCurrency isEqualToString:@"USD"],
            keptExpense);
    LBChooseRecord(controller, expense);
    LBType(window, @"ExpenseTotalValue", @"15");
    keptExpense = LBSaved(controller, expense, @"the expense corrected");
    LBCheck(@"the server has the cost corrected", LBIs(keptExpense.totalAmount, @"15"), keptExpense.totalAmount);

    Trip *trip = (Trip *)LBAddRecord(controller, [Trip class]);
    LBType(window, @"TripMileageValue", @"14200");
    LBType(window, @"TripPlace", @"Berlin");
    LBType(window, @"TripDistanceValue", @"14450");
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
    LBType(window, @"IncomeEarnedValue", @"80");
    LBType(window, @"IncomeEarnedUnit", @"EUR");
    LBChoose(window, @"IncomeTrip", trip.lbTitle);
    Income *keptIncome = LBSaved(controller, income, @"the income saved");
    LBCheck(@"the server has it, for the trip", [keptIncome.incomeKind isEqualToString:@"Delivery fee"] && LBIs(keptIncome.earnedAmount, @"80")
                && [keptIncome.trip.id isEqual:trip.id],
            keptIncome);
    LBChooseRecord(controller, trip);
    NSTextField *earned = (NSTextField *)LBControl(window.contentView, @"TripIncome");
    LBCheck(@"the trip shows what it earned", [earned.stringValue isEqualToString:@"80.00 EUR"], earned.stringValue);
    LBChooseRecord(controller, income);
    LBType(window, @"IncomeEarnedValue", @"90");
    keptIncome = LBSaved(controller, income, @"the income corrected");
    LBCheck(@"the server has it corrected", LBIs(keptIncome.earnedAmount, @"90"), keptIncome.earnedAmount);

    TyreSet *tyres = (TyreSet *)LBAddRecord(controller, [TyreSet class]);
    LBType(window, @"TyreSetName", @"Winter set");
    LBType(window, @"TyreSetSeason", @"Winter");
    LBType(window, @"TyreSetModel", @"Alpin 6");
    LBType(window, @"TyreSetSize", @"205/55 R16");
    LBTypeDay(window, @"TyreSetDate", LBDay([NSDate date]));
    LBType(window, @"TyreSetTotalValue", @"400");
    LBType(window, @"TyreSetTotalUnit", @"EUR");
    TyreSet *keptTyres = LBSaved(controller, tyres, @"the tyre set saved");
    LBCheck(@"the server has it, bought for 400", [keptTyres.tyreSetName isEqualToString:@"Winter set"] && keptTyres.date
                && LBIs(keptTyres.totalAmount, @"400"),
            keptTyres);
    LBChooseRecord(controller, tyres);
    LBType(window, @"TyreSetModel", @"Alpin 7");
    keptTyres = LBSaved(controller, tyres, @"the tyre set corrected");
    LBCheck(@"the server has its model corrected", [keptTyres.tyreModel isEqualToString:@"Alpin 7"], keptTyres.tyreModel);

    TyreChange *change = (TyreChange *)LBAddRecord(controller, [TyreChange class]);
    LBType(window, @"TyreChangeMileageValue", @"14500");
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
    LBType(window, @"DocumentTotalValue", @"300");
    LBType(window, @"DocumentTotalUnit", @"EUR");
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
    LBType(window, @"MeterReadingMileageValue", @"14600");
    MeterReading *keptReading = LBSaved(controller, reading, @"the meter reading saved");
    LBCheck(@"the server has it", LBIs(keptReading.mileageQuantity, @"14600"), keptReading);
    LBChooseRecord(controller, reading);
    LBType(window, @"MeterReadingMileageValue", @"14650");
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
    LBType(window, @"InspectionMileageValue", @"14700");
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
    LBType(window, @"FillUpChargedValue", @"65");
    LBType(window, @"FillUpChargedUnit", @"USD");
    FillUp *keptFillUp = LBSaved(controller, fillUp, @"the fill-up corrected");
    LBCheck(@"the server has what was charged", LBIs(keptFillUp.chargedAmount, @"65") && [keptFillUp.chargedCurrency isEqualToString:@"USD"],
            keptFillUp.chargedAmount);

    /* The meter reading removed, a file attached to it again: the file
       stays, of nothing, an orphan (a process clears orphans away, or asks
       about them). */
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
    LBCheck(@"a record removed, on the server too; its file left, an orphan", !controller.lastError
                && [LBServerObjects([MeterReading class], [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(id)),
                                                                         readingID]) count] == 0
                && [LBServerObjects([Attachment class], [NSPredicate predicateWithFormat:@"%K == %@ AND %K == nil",
                                                                      NSStringFromSelector(@selector(fileName)), @"odometer.txt",
                                                                      NSStringFromSelector(@selector(record))]) count] == 1,
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

/* A quantity of nothing of Logbook's, for the field alone. */
@interface LBPlainQuantity : NSObject
@property (nonatomic, copy) NSDecimalNumber *amount;
@property (nonatomic, strong) id currency;
@end

@implementation LBPlainQuantity
@end

/* UDQuantityField alone, made in code, bound to a plain object: a unit
   typed as a code, as part of a name, or not one; the number with the
   unit's decimals; what is typed given to the object, and what the object
   has shown. */
static void LBQuantityFieldAlone(void) {
    LBPlainQuantity *quantity = [[LBPlainQuantity alloc] init];
    quantity.amount = [NSDecimalNumber decimalNumberWithString:@"12.5"];
    quantity.currency = @"EUR";
    UDCurrencies *currencies = [[UDCurrencies alloc] init];
    currencies.codes = @[ @"EUR", @"USD", @"JPY", @"GBP" ];

    UDQuantityField *field = [[UDQuantityField alloc] initWithFrame:NSMakeRect(20, 20, 240, 26)];
    field.identifier = @"alone";
    field.units = currencies;
    [field bind:@"value" toObject:quantity withKeyPath:@"amount" options:nil];
    [field bind:@"unit" toObject:quantity withKeyPath:@"currency" options:nil];
    NSWindow *host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 280, 66) styleMask:NSWindowStyleMaskTitled
                                                   backing:NSBackingStoreBuffered defer:NO];
    host.releasedWhenClosed = NO;
    [host.contentView addSubview:field];
    [host orderBack:nil];
    LBCheck(@"quantity alone: 12.50 EUR shown", [field.valueField.stringValue isEqualToString:@"12.50"]
                && [field.unitBox.stringValue isEqualToString:@"EUR"],
            [NSString stringWithFormat:@"%@ %@", field.valueField.stringValue, field.unitBox.stringValue]);

    LBType(host, @"aloneUnit", @"yen");
    LBCheck(@"quantity alone: part of a name typed, the one currency it names taken", [quantity.currency isEqual:@"JPY"]
                && [field.unitBox.stringValue isEqualToString:@"JPY"],
            quantity.currency);
    LBCheck(@"quantity alone: yen have no decimals", [field.valueField.stringValue rangeOfCharacterFromSet:[NSCharacterSet punctuationCharacterSet]].location
                == NSNotFound,
            field.valueField.stringValue);

    LBType(host, @"aloneUnit", @"gbp");
    LBCheck(@"quantity alone: a code typed small, taken", [quantity.currency isEqual:@"GBP"], quantity.currency);

    NSComboBox *box = field.unitBox;
    [host makeFirstResponder:box];
    NSTextView *editor = (NSTextView *)[host fieldEditor:NO forObject:box];
    [editor selectAll:nil];
    [editor insertText:@"u" replacementRange:NSMakeRange(NSNotFound, 0)];
    NSInteger listed = [box.dataSource numberOfItemsInComboBox:box];
    NSString *first = listed ? [box.dataSource comboBox:box objectValueForItemAtIndex:0] : nil;
    LBCheck(@"quantity alone: what is typed lists those that have it, a code beginning with it first", listed >= 2 && listed < 4
                && [first hasPrefix:@"USD"],
            [NSString stringWithFormat:@"%ld, %@", (long)listed, first]);
    [host makeFirstResponder:nil];
    LBSpin();
    LBCheck(@"quantity alone: more than one, the currency before kept", [quantity.currency isEqual:@"GBP"]
                && [box.stringValue isEqualToString:@"GBP"] && [box.dataSource numberOfItemsInComboBox:box] == 4,
            box.stringValue);

    LBType(host, @"aloneUnit", @"XYZ");
    LBCheck(@"quantity alone: none, the currency before kept", [quantity.currency isEqual:@"GBP"], quantity.currency);

    LBType(host, @"aloneValue", @"7.5");
    LBCheck(@"quantity alone: an amount typed, given", [quantity.amount isEqual:[NSDecimalNumber decimalNumberWithString:@"7.5"]],
            quantity.amount);
    quantity.amount = [NSDecimalNumber decimalNumberWithString:@"3"];
    LBCheck(@"quantity alone: the object's amount shown, with the currency's decimals",
            [field.valueField.stringValue isEqualToString:@"3.00"], field.valueField.stringValue);

    /* Objects, said by key paths. */
    UDKeyPathUnits *distances = [[UDKeyPathUnits alloc] init];
    NSDictionary *km = @{ @"code" : @"km", @"name" : @"kilometres" };
    NSDictionary *mi = @{ @"code" : @"mi", @"name" : @"miles" };
    distances.objects = @[ km, mi ];
    distances.codeKeyPath = @"code";
    distances.nameKeyPath = @"name";
    quantity.currency = km;
    field.units = distances;
    LBType(host, @"aloneUnit", @"mile");
    LBCheck(@"quantity alone: units by key path, one found by its name", quantity.currency == mi
                && [field.unitBox.stringValue isEqualToString:@"mi"],
            quantity.currency);
    LBCheck(@"quantity alone: drawn", LBDrawn(field), nil);
    [field unbind:@"value"];
    [field unbind:@"unit"];
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

/* What the connect panel connected to, as its delegate. */
@interface LBConnected : NSObject <LBConnectPanelDelegate>
@property (nonatomic, strong) ODataSignIn *signIn;
@end

@implementation LBConnected
- (void)connectPanel:(LBConnectPanel *)panel didConnect:(ODataSignIn *)signIn {
    self.signIn = signIn;
}
@end

/* A server that asks no one, and an app that does not know its user: the
   panel asks who they are, refuses what is not an email, and connects as
   the one given, kept (for this run only, being a self-test). */
static void LBConnectSteps(void) {
    LBSetDefault(@"LBUser", @"");
    LBConnectPanel *panel = [[LBConnectPanel alloc] init];
    LBConnected *connected = [[LBConnected alloc] init];
    panel.delegate = connected;
    [panel showWithServer:LBSelfTestRoot.absoluteString];
    for (int i = 0; i < 50 && [panel.emailField isHidden]; i++) LBSpin();
    LBCheck(@"connecting to a server that asks no one, with no user known: asked for an email",
            ![panel.emailField isHidden] && !connected.signIn, panel.statusLabel.stringValue);
    LBType(panel.window, @"emailField", @"just a name");
    LBClick(panel.window, @"connect");
    LBCheck(@"what is not an email refused", !connected.signIn && [panel.statusLabel.stringValue containsString:@"not an email"],
            panel.statusLabel.stringValue);
    LBType(panel.window, @"emailField", @"driver@example.org");
    LBClick(panel.window, @"connect");
    LBCheck(@"an email given: connected, as it", connected.signIn != nil
                && [[[NSUserDefaults standardUserDefaults] stringForKey:@"LBUser"] isEqualToString:@"driver@example.org"],
            [[NSUserDefaults standardUserDefaults] stringForKey:@"LBUser"]);
    [panel close];
    LBSetDefault(@"LBUser", @"self-test@example.org");
}

/* Whether the steps of the part run: every part, unless LB_STEPS names
   some ("stock", "logbook", or both, comma-separated). */
static BOOL LBRuns(NSString *part) {
    NSString *only = [NSProcessInfo processInfo].environment[@"LB_STEPS"];
    return !only.length || [[only componentsSeparatedByString:@","] containsObject:part];
}

/* The logbook's steps: a vehicle added, and everything done with it. */
static void LBLogbookSteps(LBMainWindowController *controller) {
    NSWindow *window = controller.window;
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
    LBQuantityFieldAlone();
    LBConnectSteps();
}

static void LBSteps(LBMainWindowController *controller) {
    NSWindow *window = controller.window;
    controller.quiet = YES;
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    LBCheck(@"the window", window.isVisible, nil);
    if (LBRuns(@"logbook")) LBLogbookSteps(controller);
    if (LBRuns(@"stock")) LBStockSteps(controller);
    LBCheck(@"the user's saved settings as they were (the server, the user)", [LBSavedSettingsNow()[@"LBServer"] ?: @"" isEqual:LBSavedSettings[@"LBServer"] ?: @""]
                && [LBSavedSettingsNow()[@"LBUser"] ?: @"" isEqual:LBSavedSettings[@"LBUser"] ?: @""],
            LBSavedSettingsNow()[@"LBServer"]);
}

/* The steps run from the run loop, not from a block on the main queue:
   spinning the run loop then lets what is sent to the main queue (a
   sign-in's answer) run, as it does for a user. */
@interface LBSelfTestRun : NSObject
@property (nonatomic, strong) LBMainWindowController *window;
@end

@implementation LBSelfTestRun
- (void)run {
    @try {
        LBSteps(self.window);
    } @catch (NSException *e) {
        LBCheck(@"no exception", NO, e.reason);
    }
    printf("self-test done: %lu failed\n", (unsigned long)LBFailures);
    fflush(stdout);
    exit(LBFailures ? 1 : 0);
}
@end

void LBRunSelfTest(LBMainWindowController *window) {
    static LBSelfTestRun *run;
    run = [[LBSelfTestRun alloc] init];
    run.window = window;
    [run performSelector:@selector(run) withObject:nil afterDelay:0.5];
}
