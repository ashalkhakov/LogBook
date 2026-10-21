#import "LBiOSControllers.h"
#import "LBDisplay.h"
#import "LBProcedures.h"
#import "LBSignIn.h"
#import "LBVehicleSummary.h"
#import "Event+CoreDataClass.h"
#import "User+CoreDataClass.h"
#import "VehicleDriver+CoreDataClass.h"
#import "Rescheduling+CoreDataClass.h"

NSString * const LBServerDefaultsKey = @"LBServer";
NSString * const LBEmailDefaultsKey = @"LBEmail";
NSString * const LBVehicleDefaultsKey = @"LBVehicle";
NSNotificationName const LBPhoneVehicleDidChangeNotification = @"LBPhoneVehicleDidChangeNotification";

static void LBTell(UIViewController *controller, NSString *title, NSArray<NSString *> *lines) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:[lines componentsJoinedByString:@"\n\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

/* A form in a navigation controller of its own, over the controller. */
static void LBPresentForm(UIViewController *over, LBRecordFormViewController *form) {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:form];
    [over presentViewController:navigation animated:YES completion:nil];
}

#pragma mark - The phone

@implementation LBPhone
@synthesize vehicle = _vehicle;

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithStore:(LBLocalStore *)store {
    if ((self = [super init])) _store = store;
    return self;
}

static NSComparisonResult LBByName(Vehicle *a, Vehicle *b, void *unused) {
    return [a.lbTitle localizedCaseInsensitiveCompare:b.lbTitle];
}

- (NSArray<Vehicle *> *)vehicles {
    User *user = _store.user;
    NSMutableSet *vehicles = [NSMutableSet set];
    for (Vehicle *vehicle in user.ownedVehicles) {
        if (!vehicle.isDeleted) [vehicles addObject:vehicle];
    }
    for (VehicleDriver *sharing in user.vehicleDrivers) {
        if (sharing.vehicle && !sharing.isDeleted && !sharing.vehicle.isDeleted) [vehicles addObject:sharing.vehicle];
    }
    return [vehicles.allObjects sortedArrayUsingFunction:LBByName context:NULL];
}

- (Vehicle *)vehicle {
    if (_vehicle && !_vehicle.isDeleted && _vehicle.managedObjectContext) return _vehicle;
    NSArray<Vehicle *> *vehicles = [self vehicles];
    NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:LBVehicleDefaultsKey];
    for (Vehicle *vehicle in vehicles) {
        if ([vehicle.id.UUIDString isEqualToString:chosen]) _vehicle = vehicle;
    }
    if (!_vehicle) _vehicle = vehicles.firstObject;
    return _vehicle;
}

- (void)setVehicle:(Vehicle *)vehicle {
    _vehicle = vehicle;
    if (vehicle.id) [[NSUserDefaults standardUserDefaults] setObject:vehicle.id.UUIDString forKey:LBVehicleDefaultsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:LBPhoneVehicleDidChangeNotification object:self];
}

- (BOOL)ownsVehicle {
    return self.vehicle && self.vehicle.owner == _store.user;
}

@end

#pragma mark - Signing in

@implementation LBSignInViewController {
    ODataSignIn *_signIn;
    NSURL *_page;
    NSString *_code;
    BOOL _waiting;
}

- (instancetype)init {
    return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _serverText = [defaults stringForKey:LBServerDefaultsKey] ?: [[NSBundle mainBundle] objectForInfoDictionaryKey:@"LBDefaultServer"] ?: @"";
        _emailText = [defaults stringForKey:LBEmailDefaultsKey] ?: @"";
        _status = @"Your logbook server's address, as whoever runs it gave it to you.";
        self.title = @"Logbook";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Connect" style:UIBarButtonItemStyleDone
                                                                              target:self action:@selector(connect:)];
}

- (void)say:(NSString *)status waiting:(BOOL)waiting {
    _status = [status copy];
    _waiting = waiting;
    self.navigationItem.rightBarButtonItem.enabled = !waiting;
    if ([self isViewLoaded]) [self.tableView reloadData];
}

- (IBAction)connect:(id)sender {
    [self.view endEditing:YES];
    NSURL *root = LBServiceRootOf(_serverText);
    if (!root) {
        [self say:@"That is not a server's address." waiting:NO];
        return;
    }
    _code = nil;
    _page = nil;
    [self say:[NSString stringWithFormat:@"Asking %@ how to sign in…", root.host] waiting:YES];
    [_signIn cancel];
    _signIn = LBSignInTo(root);
    _signIn.delegate = self;
    [_signIn learn];
}

- (void)signInDidLearn:(ODataSignIn *)signIn {
    if (signIn.kind == ODataSignInOpenID && !signIn.isSignedIn) {
        [self say:@"Asking for a code to sign in with…" waiting:YES];
        [signIn begin];
        return;
    }
    if (signIn.kind != ODataSignInOpenID && !signIn.isSignedIn) {
        /* A server that asks for no one, for trying it out: who you are
           is the email you give. */
        NSString *email = [_emailText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (signIn.kind == ODataSignInNone && ![email containsString:@"@"]) {
            [self say:@"This server asks for no sign-in: give your email, which is who you are in the logbook." waiting:NO];
            return;
        }
    }
    [self connected];
}

- (void)signIn:(ODataSignIn *)signIn showCode:(NSString *)code page:(NSURL *)page completePage:(NSURL *)completePage {
    _code = code;
    _page = completePage ?: page;
    [self say:[NSString stringWithFormat:@"Open %@ in a browser, on any device, and enter the code. "
                                         @"The logbook opens once you have signed in.", page.absoluteString]
      waiting:YES];
}

- (void)signInDidFinish:(ODataSignIn *)signIn {
    [self connected];
}

- (void)signIn:(ODataSignIn *)signIn didFail:(NSError *)error {
    [self say:error.localizedDescription ?: @"Not signed in." waiting:NO];
}

- (void)connected {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:_signIn.serviceRoot.absoluteString forKey:LBServerDefaultsKey];
    NSString *email = [_emailText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
    if (email.length) [defaults setObject:email forKey:LBEmailDefaultsKey];
    [self say:@"Signed in." waiting:NO];
    [_delegate signInViewController:self didConnect:_signIn email:email.length ? email : nil];
}

- (void)openPage:(id)sender {
    if (_page) [[UIApplication sharedApplication] openURL:_page options:@{} completionHandler:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _code ? 3 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? _status : nil;
}

- (void)fieldChanged:(UITextField *)field {
    if (field.tag == 0) _serverText = field.text ?: @"";
    else _emailText = field.text ?: @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 0) {
        UITextField *field = [[UITextField alloc] init];
        field.translatesAutoresizingMaskIntoConstraints = NO;
        field.tag = indexPath.row;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.keyboardType = indexPath.row == 0 ? UIKeyboardTypeURL : UIKeyboardTypeEmailAddress;
        field.placeholder = indexPath.row == 0 ? @"logbook.example.com" : @"Your email (a server with no sign-in)";
        field.text = indexPath.row == 0 ? _serverText : _emailText;
        field.enabled = !_waiting;
        field.delegate = self;
        [field addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
        [cell.contentView addSubview:field];
        [NSLayoutConstraint activateConstraints:@[
            [field.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:11],
            [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-11] ]];
    } else if (indexPath.section == 1 && _code) {
        cell.textLabel.text = _code;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:28 weight:UIFontWeightSemibold];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
    } else {
        cell.textLabel.text = _code ? @"Open the Page" : @"Connect";
        cell.textLabel.textColor = self.view.tintColor;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == tableView.numberOfSections - 1) {
        if (_code) [self openPage:nil];
        else [self connect:nil];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

#pragma mark - Sync status and conflicts, on every tab

/* What each list says over it: the sync's status, and the conflicts that
   wait (a button to them). */
@interface UIViewController (LBStatus)
- (void)lb_showStatusOf:(LBPhone *)phone;
@end

@implementation UIViewController (LBStatus)

- (void)lb_showStatusOf:(LBPhone *)phone {
    self.navigationItem.prompt = phone.store.status;
    NSUInteger conflicts = [phone.store pendingConflicts].count;
    self.navigationItem.leftBarButtonItem = conflicts
        ? [[UIBarButtonItem alloc] initWithTitle:[NSString stringWithFormat:@"⚠︎ %lu", (unsigned long)conflicts] style:UIBarButtonItemStylePlain
                                          target:self action:@selector(lb_showConflicts:)]
        : nil;
}

- (void)lb_showConflicts:(id)sender {
    LBMainViewController *main = (LBMainViewController *)self.tabBarController;
    if (![main isKindOfClass:[LBMainViewController class]]) return;
    [self.navigationController pushViewController:[[LBConflictsViewController alloc] initWithPhone:main.phone] animated:YES];
}

@end

#pragma mark - The tabs and the +

@implementation LBMainViewController {
    UIButton *_plus;
}

+ (NSArray<NSString *> *)loggedKinds {
    return @[ @"FillUp", @"Service", @"Expense", @"Trip", @"MeterReading", @"Inspection" ];
}

- (instancetype)initWithPhone:(LBPhone *)phone {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _phone = phone;
        UINavigationController *timeline = [[UINavigationController alloc] initWithRootViewController:[[LBTimelineViewController alloc] initWithPhone:phone]];
        timeline.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Timeline" image:[UIImage systemImageNamed:@"list.bullet.rectangle"] tag:0];
        UINavigationController *reminders = [[UINavigationController alloc] initWithRootViewController:[[LBRemindersViewController alloc] initWithPhone:phone]];
        reminders.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Reminders" image:[UIImage systemImageNamed:@"bell"] tag:1];
        UINavigationController *vehicle = [[UINavigationController alloc] initWithRootViewController:[[LBVehicleViewController alloc] initWithPhone:phone]];
        vehicle.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Vehicle" image:[UIImage systemImageNamed:@"car"] tag:2];
        self.viewControllers = @[ timeline, reminders, vehicle ];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changed:) name:LBLocalStoreDidChangeNotification
                                                   object:phone.store];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    /* The +, prominent, over the tab bar: what is logged most, fastest. */
    _plus = [UIButton buttonWithType:UIButtonTypeSystem];
    _plus.translatesAutoresizingMaskIntoConstraints = NO;
    _plus.backgroundColor = self.view.tintColor;
    _plus.tintColor = [UIColor whiteColor];
    [_plus setImage:[UIImage systemImageNamed:@"plus" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24
                                                                                                                       weight:UIImageSymbolWeightBold]]
           forState:UIControlStateNormal];
    _plus.layer.cornerRadius = 28;
    _plus.layer.shadowOpacity = 0.25;
    _plus.layer.shadowRadius = 4;
    _plus.layer.shadowOffset = CGSizeMake(0, 2);
    _plus.accessibilityLabel = @"Log";
    [_plus addTarget:self action:@selector(log:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_plus];
    [NSLayoutConstraint activateConstraints:@[
        [_plus.widthAnchor constraintEqualToConstant:56], [_plus.heightAnchor constraintEqualToConstant:56],
        [_plus.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [_plus.bottomAnchor constraintEqualToAnchor:self.tabBar.topAnchor constant:-16] ]];
    [self changed:nil];
}

- (void)changed:(NSNotification *)notification {
    NSUInteger conflicts = [_phone.store pendingConflicts].count;
    self.viewControllers.lastObject.tabBarItem.badgeValue = conflicts ? [NSString stringWithFormat:@"%lu", (unsigned long)conflicts] : nil;
}

- (UIViewController *)logKind:(NSString *)entityName {
    NSManagedObject *record = [LBRecordFormViewController newRecordOfKind:entityName phone:_phone];
    if (!record) {
        LBTell(self, @"No Vehicle", @[ @"Add a vehicle first, or have one shared with you: the Vehicle tab." ]);
        return nil;
    }
    LBRecordFormViewController *form = [[LBRecordFormViewController alloc] initWithObject:record phone:_phone];
    LBPresentForm(self, form);
    return form;
}

- (IBAction)log:(id)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak LBMainViewController *weakSelf = self;
    for (NSString *kind in [LBMainViewController loggedKinds]) {
        [sheet addAction:[UIAlertAction actionWithTitle:[Record lbKindOfEntityNamed:kind] style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    [weakSelf logKind:kind];
                                                }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _plus;
    sheet.popoverPresentationController.sourceRect = _plus.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - Timeline

@implementation LBTimelineViewController {
    LBPhone *_phone;
    NSArray<LBMonth *> *_months;
}

- (instancetype)initWithPhone:(LBPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _phone = phone;
        self.title = @"Timeline";
        for (NSNotificationName name in @[ LBLocalStoreDidChangeNotification, LBPhoneVehicleDidChangeNotification ]) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:name object:nil];
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(pull:) forControlEvents:UIControlEventValueChanged];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)pull:(id)sender {
    [_phone.store sync];
    [self.refreshControl endRefreshing];
}

- (void)reload {
    Vehicle *vehicle = _phone.vehicle;
    self.navigationItem.title = vehicle ? vehicle.lbTitle : @"Timeline";
    _months = vehicle ? [[[LBVehicleSummary alloc] initWithVehicle:vehicle] months] : @[];
    [self lb_showStatusOf:_phone];
    if ([self isViewLoaded]) [self.tableView reloadData];
}

- (NSArray<NSString *> *)shownRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (LBMonth *month in _months) {
        NSMutableArray *kinds = [NSMutableArray array];
        for (Record *record in month.records) [kinds addObject:record.lbKind];
        [rows addObject:[NSString stringWithFormat:@"%@: %@", month.title, [kinds componentsJoinedByString:@", "]]];
    }
    return rows;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAX((NSInteger)_months.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _months.count ? _months[(NSUInteger)section].title : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (_months.count) return nil;
    return _phone.vehicle ? @"Nothing logged yet: the + logs a fill-up, a service, an expense…"
                          : @"No vehicle yet: add one, or have one shared with you, in the Vehicle tab.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _months.count ? (NSInteger)_months[(NSUInteger)section].records.count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"record"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"record"];
    Record *record = _months[(NSUInteger)indexPath.section].records[(NSUInteger)indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@\n%@", record.lbKind, record.lbWhen ?: @""];
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = record.lbCost;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Record *record = _months[(NSUInteger)indexPath.section].records[(NSUInteger)indexPath.row];
    [self.navigationController pushViewController:[[LBRecordFormViewController alloc] initWithObject:record phone:_phone] animated:YES];
}

@end

#pragma mark - Reminders

/* A reminder moved: the day it is now due, and why. */
@interface LBRescheduleViewController : UIViewController
@property (nonatomic, copy) void (^done)(NSDate *day, NSString *note);
@end

@implementation LBRescheduleViewController {
    UIDatePicker *_picker;
    UITextField *_note;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Move To";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    _picker = [[UIDatePicker alloc] init];
    _picker.datePickerMode = UIDatePickerModeDate;
    if (@available(iOS 14.0, *)) _picker.preferredDatePickerStyle = UIDatePickerStyleInline;
    _picker.date = [NSDate dateWithTimeIntervalSinceNow:30 * 86400];
    _note = [[UITextField alloc] init];
    _note.placeholder = @"Why (away in May…)";
    _note.borderStyle = UITextBorderStyleRoundedRect;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ _picker, _note ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor] ]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self
                                                                                           action:@selector(save:)];
}

- (void)save:(id)sender {
    /* The day picked, as the model's days are: in UTC. */
    NSDateComponents *parts = [[NSCalendar currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                              fromDate:_picker.date];
    NSCalendar *utc = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    utc.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    if (self.done) self.done([utc dateFromComponents:parts], _note.text.length ? _note.text : nil);
}

@end

@implementation LBRemindersViewController {
    LBPhone *_phone;
    LBVehicleSummary *_summary;
    NSArray<Reminder *> *_reminders;
}

- (instancetype)initWithPhone:(LBPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _phone = phone;
        self.title = @"Reminders";
        for (NSNotificationName name in @[ LBLocalStoreDidChangeNotification, LBPhoneVehicleDidChangeNotification ]) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:name object:nil];
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    Vehicle *vehicle = _phone.vehicle;
    _summary = vehicle ? [[LBVehicleSummary alloc] initWithVehicle:vehicle] : nil;
    _reminders = _summary ? [_summary reminders] : @[];
    [self lb_showStatusOf:_phone];
    if ([self isViewLoaded]) [self.tableView reloadData];
}

- (NSArray<Reminder *> *)shownReminders {
    return _reminders;
}

- (NSString *)statusOf:(Reminder *)reminder {
    if (reminder.lb_isOpen) return [_summary isOverdue:reminder] ? @"Overdue" : @"Open";
    return reminder.lbStatus;
}

- (NSArray<NSString *> *)shownRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (Reminder *reminder in _reminders) [rows addObject:[NSString stringWithFormat:@"%@ — %@", reminder.lbWork, [self statusOf:reminder]]];
    return rows;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_reminders.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return _reminders.count ? nil : @"No reminders: the owner sets up schedules on the desktop.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"reminder"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"reminder"];
    Reminder *reminder = _reminders[(NSUInteger)indexPath.row];
    NSString *status = [self statusOf:reminder];
    cell.textLabel.text = reminder.lbWork;
    cell.detailTextLabel.text = reminder.lb_isOpen ? [NSString stringWithFormat:@"%@ · due %@", status, reminder.lbDue] : status;
    cell.detailTextLabel.textColor = [status isEqualToString:@"Overdue"] ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];
    cell.textLabel.textColor = reminder.lb_isOpen ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    return cell;
}

- (BOOL)reschedule:(Reminder *)reminder toDate:(NSDate *)day mileage:(NSDecimalNumber *)mileage note:(NSString *)note
          problems:(NSArray<NSString *> **)problems {
    NSError *error = nil;
    LBLocalStore *store = _phone.store;
    BOOL done = [reminder lb_rescheduleToDate:day mileage:mileage unit:mileage ? reminder.dueMileageDistanceUnit : nil note:note
                                           by:store.user at:LBNow() error:&error]
                && [store save:&error];
    if (!done) {
        [store.context rollback];
        if (problems) *problems = [LBLocalStore sentencesOfError:error];
    }
    [self reload];
    return done;
}

- (BOOL)cancel:(Reminder *)reminder problems:(NSArray<NSString *> **)problems {
    NSError *error = nil;
    LBLocalStore *store = _phone.store;
    BOOL done = [reminder lb_cancelOn:nil replacementDueDate:nil mileage:nil unit:nil by:store.user at:LBNow() replacement:NULL
                                error:&error]
                && [store save:&error];
    if (!done) {
        [store.context rollback];
        if (problems) *problems = [LBLocalStore sentencesOfError:error];
    }
    [self reload];
    return done;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    Reminder *reminder = _reminders[(NSUInteger)indexPath.row];
    if (!reminder.lb_isOpen) {
        if (reminder.event)
            [self.navigationController pushViewController:[[LBRecordFormViewController alloc] initWithObject:reminder.event phone:_phone]
                                                 animated:YES];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:reminder.lbWork
                                                                   message:[NSString stringWithFormat:@"Due %@", reminder.lbDue]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak LBRemindersViewController *weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Move to Another Day…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf showRescheduleOf:reminder];
    }]];
    /* Cancelling is the owner's. */
    if ([_phone ownsVehicle]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel Reminder" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            NSArray *problems = nil;
            if (![weakSelf cancel:reminder problems:&problems]) LBTell(weakSelf, @"Not Cancelled", problems ?: @[]);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showRescheduleOf:(Reminder *)reminder {
    LBRescheduleViewController *move = [[LBRescheduleViewController alloc] init];
    __weak LBRemindersViewController *weakSelf = self;
    __weak LBRescheduleViewController *weakMove = move;
    move.done = ^(NSDate *day, NSString *note) {
        NSArray *problems = nil;
        if ([weakSelf reschedule:reminder toDate:day mileage:nil note:note problems:&problems]) {
            [weakSelf.navigationController popViewControllerAnimated:YES];
        } else {
            LBTell(weakMove, @"Not Moved", problems ?: @[]);
        }
    };
    [self.navigationController pushViewController:move animated:YES];
}

@end

#pragma mark - Vehicle

@interface LBVehicleViewController () <LBRecordFormDelegate>
@end

typedef NS_ENUM(NSInteger, LBVehicleSection) {
    LBVehicleSectionVehicle,
    LBVehicleSectionNumbers,
    LBVehicleSectionSharing,
    LBVehicleSectionSync,
    LBVehicleSectionAccount,
};

@implementation LBVehicleViewController {
    LBPhone *_phone;
    NSArray<NSNumber *> *_sections;
    LBVehicleSummary *_summary;
}

- (instancetype)initWithPhone:(LBPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _phone = phone;
        self.title = @"Vehicle";
        for (NSNotificationName name in @[ LBLocalStoreDidChangeNotification, LBPhoneVehicleDidChangeNotification ]) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:name object:nil];
        }
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (BOOL)showsSharing {
    return [_phone ownsVehicle];
}

- (void)reload {
    NSMutableArray *sections = [NSMutableArray arrayWithObject:@(LBVehicleSectionVehicle)];
    if (_phone.vehicle) [sections addObject:@(LBVehicleSectionNumbers)];
    if ([self showsSharing]) [sections addObject:@(LBVehicleSectionSharing)];
    [sections addObjectsFromArray:@[ @(LBVehicleSectionSync), @(LBVehicleSectionAccount) ]];
    _sections = sections;
    _summary = _phone.vehicle ? [[LBVehicleSummary alloc] initWithVehicle:_phone.vehicle] : nil;
    self.navigationItem.prompt = _phone.store.status;
    if ([self isViewLoaded]) [self.tableView reloadData];
}

- (NSString *)titleOf:(LBVehicleSection)section {
    switch (section) {
        case LBVehicleSectionVehicle: return @"Vehicle";
        case LBVehicleSectionNumbers: return @"At a Glance";
        case LBVehicleSectionSharing: return @"Sharing";
        case LBVehicleSectionSync: return @"Sync";
        case LBVehicleSectionAccount: return @"Account";
    }
    return @"";
}

- (NSArray<NSString *> *)shownSections {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSNumber *section in _sections) [titles addObject:[self titleOf:section.integerValue]];
    return titles;
}

- (NSArray<VehicleDriver *> *)drivers {
    NSMutableArray *drivers = [NSMutableArray array];
    for (VehicleDriver *sharing in _phone.vehicle.vehicleDrivers) {
        if (!sharing.isDeleted) [drivers addObject:sharing];
    }
    [drivers sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:[NSString stringWithFormat:@"%@.%@", NSStringFromSelector(@selector(user)),
                                                                                                   NSStringFromSelector(@selector(email))]
                                                                   ascending:YES] ]];
    return drivers;
}

/* Rows of a section: (title, detail) pairs. */
- (NSArray<NSArray<NSString *> *> *)rowsOf:(LBVehicleSection)section {
    Vehicle *vehicle = _phone.vehicle;
    LBLocalStore *store = _phone.store;
    switch (section) {
        case LBVehicleSectionVehicle: {
            NSMutableArray *rows = [NSMutableArray array];
            [rows addObject:@[ vehicle ? vehicle.lbTitle : @"No vehicle", [_phone vehicles].count > 1 ? @"Change" : @"" ]];
            if (vehicle) {
                [rows addObject:@[ @"Make and model", [NSString stringWithFormat:@"%@ %@", vehicle.make ?: @"", vehicle.carModel ?: @""] ]];
                [rows addObject:@[ @"Year", [NSString stringWithFormat:@"%d", vehicle.manufactureYear] ]];
                [rows addObject:@[ @"Fuel", vehicle.fuel ?: @"" ]];
                if (vehicle.registrationNumber.length) [rows addObject:@[ @"Registration", vehicle.registrationNumber ]];
                [rows addObject:@[ @"Owner", vehicle.owner.lbTitle ?: @"" ]];
            }
            [rows addObject:@[ @"Add a Vehicle…", @"" ]];
            return rows;
        }
        case LBVehicleSectionNumbers:
            return @[ @[ @"Consumption", [_summary consumption] ?: @"after two full tanks" ],
                      @[ @"This month", [_summary costThisMonth] ?: @"nothing yet" ],
                      @[ @"Next due", [_summary nextDue] ?: @"nothing" ] ];
        case LBVehicleSectionSharing: {
            NSMutableArray *rows = [NSMutableArray array];
            for (VehicleDriver *sharing in [self drivers]) [rows addObject:@[ sharing.user.email ?: @"", @"drives it" ]];
            [rows addObject:@[ @"Share by Email…", @"" ]];
            return rows;
        }
        case LBVehicleSectionSync: {
            NSUInteger conflicts = [store pendingConflicts].count;
            return @[ @[ @"Sync", @"" ], @[ store.status, @"" ],
                      @[ @"Waiting to send", [NSString stringWithFormat:@"%lu", (unsigned long)[store pendingCount]] ],
                      @[ @"Refused by the server", [NSString stringWithFormat:@"%lu", (unsigned long)store.issues.count] ],
                      @[ @"Conflicts", [NSString stringWithFormat:@"%lu", (unsigned long)conflicts] ] ];
        }
        case LBVehicleSectionAccount:
            return @[ @[ store.user.email ?: @"", @"" ], @[ @"Sign Out", @"" ] ];
    }
    return @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (NSInteger)_sections.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self titleOf:_sections[(NSUInteger)section].integerValue];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self rowsOf:_sections[(NSUInteger)section].integerValue].count;
}

- (void)syncSwitched:(UISwitch *)toggle {
    [self setSyncOn:toggle.isOn];
}

- (void)setSyncOn:(BOOL)on {
    _phone.store.syncEnabled = on;
    [self reload];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LBVehicleSection section = _sections[(NSUInteger)indexPath.section].integerValue;
    NSArray<NSArray<NSString *> *> *rows = [self rowsOf:section];
    NSArray<NSString *> *row = rows[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = row[0];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = row[1];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    BOOL last = (NSUInteger)indexPath.row == rows.count - 1;
    if ((section == LBVehicleSectionVehicle && (indexPath.row == 0 || last)) || (section == LBVehicleSectionSharing && last)
        || (section == LBVehicleSectionAccount && last) || (section == LBVehicleSectionSync && indexPath.row >= 3)) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        if (last && section != LBVehicleSectionSync) cell.textLabel.textColor = section == LBVehicleSectionAccount ? [UIColor systemRedColor] : self.view.tintColor;
        else cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    if (section == LBVehicleSectionVehicle && indexPath.row == 0) cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    if (section == LBVehicleSectionSync && indexPath.row == 0) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = _phone.store.syncEnabled;
        [toggle addTarget:self action:@selector(syncSwitched:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    if (section == LBVehicleSectionSync && indexPath.row == 1) cell.textLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LBVehicleSection section = _sections[(NSUInteger)indexPath.section].integerValue;
    NSUInteger count = [self rowsOf:section].count;
    BOOL last = (NSUInteger)indexPath.row == count - 1;
    if (section == LBVehicleSectionVehicle && indexPath.row == 0) [self chooseVehicle:[tableView cellForRowAtIndexPath:indexPath]];
    else if (section == LBVehicleSectionVehicle && last) [self addVehicle:nil];
    else if (section == LBVehicleSectionSharing && last) [self askEmail];
    else if (section == LBVehicleSectionSync && indexPath.row == 3) [self showIssues];
    else if (section == LBVehicleSectionSync && indexPath.row == 4)
        [self.navigationController pushViewController:[[LBConflictsViewController alloc] initWithPhone:_phone] animated:YES];
    else if (section == LBVehicleSectionAccount && last) [self signOut];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return _sections[(NSUInteger)indexPath.section].integerValue == LBVehicleSectionSharing && (NSUInteger)indexPath.row < [self drivers].count;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    VehicleDriver *sharing = [self drivers][(NSUInteger)indexPath.row];
    [_phone.store.context deleteObject:sharing];
    NSError *error = nil;
    if (![_phone.store save:&error]) {
        [_phone.store.context rollback];
        LBTell(self, @"Not Saved", [LBLocalStore sentencesOfError:error]);
    }
    [self reload];
}

- (void)chooseVehicle:(UITableViewCell *)cell {
    NSArray<Vehicle *> *vehicles = [_phone vehicles];
    if (vehicles.count < 2) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Vehicle" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    LBPhone *phone = _phone;
    for (Vehicle *vehicle in vehicles) {
        [sheet addAction:[UIAlertAction actionWithTitle:vehicle.lbTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            phone.vehicle = vehicle;
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)recordFormDidSave:(LBRecordFormViewController *)form {
    if ([form.object isKindOfClass:[Vehicle class]]) _phone.vehicle = (Vehicle *)form.object;
}

- (IBAction)addVehicle:(id)sender {
    LBRecordFormViewController *form = [[LBRecordFormViewController alloc] initWithObject:[LBRecordFormViewController newVehicleForPhone:_phone]
                                                                                    phone:_phone];
    form.delegate = self;
    LBPresentForm(self, form);
}

- (BOOL)shareWithEmail:(NSString *)typed problems:(NSArray<NSString *> **)problems {
    NSString *email = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
    Vehicle *vehicle = _phone.vehicle;
    LBLocalStore *store = _phone.store;
    if (!vehicle || ![email containsString:@"@"]) {
        if (problems) *problems = @[ @"An email, of whoever is to drive it." ];
        return NO;
    }
    /* A user is named by their email: one the logbook has, else made (they
       need not have signed in yet). */
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass([User class])];
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K ==[c] %@", NSStringFromSelector(@selector(email)), email];
    User *user = [[store.context executeFetchRequest:fetch error:NULL] firstObject];
    if (!user) {
        user = (User *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([User class]) inManagedObjectContext:store.context];
        user.email = email;
    }
    VehicleDriver *sharing = (VehicleDriver *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([VehicleDriver class])
                                                                            inManagedObjectContext:store.context];
    sharing.vehicle = vehicle;
    sharing.user = user;
    NSError *error = nil;
    BOOL saved = [store save:&error];
    if (!saved) {
        [store.context rollback];
        if (problems) *problems = [LBLocalStore sentencesOfError:error];
    }
    [self reload];
    return saved;
}

- (void)askEmail {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Share" message:@"Whoever is to drive it, by their email."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"ben@example.org";
        field.keyboardType = UIKeyboardTypeEmailAddress;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak LBVehicleViewController *weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Share" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *problems = nil;
        if (![weakSelf shareWithEmail:weakAlert.textFields.firstObject.text ?: @"" problems:&problems])
            LBTell(weakSelf, @"Not Shared", problems ?: @[]);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showIssues {
    NSArray<ODataSyncIssue *> *issues = _phone.store.issues;
    if (!issues.count) return;
    NSMutableArray *lines = [NSMutableArray array];
    for (ODataSyncIssue *issue in issues) [lines addObject:[NSString stringWithFormat:@"%@: %@", issue.entityName, issue.message]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Refused by the Server" message:[lines componentsJoinedByString:@"\n\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    LBLocalStore *store = _phone.store;
    __weak LBVehicleViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Send Again" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        for (ODataSyncIssue *issue in store.issues) [store.engine retryIssue:issue];
        [store sync];
        [weakSelf reload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Forget Them" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        for (ODataSyncIssue *issue in store.issues) [store.engine discardIssue:issue];
        [weakSelf reload];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)signOut {
    LBMainViewController *main = (LBMainViewController *)self.tabBarController;
    if ([main isKindOfClass:[LBMainViewController class]] && main.signOutTarget && main.signOutAction)
        [[UIApplication sharedApplication] sendAction:main.signOutAction to:main.signOutTarget from:self forEvent:nil];
}

@end

#pragma mark - Conflicts

@interface LBConflictsViewController () <LBRecordFormDelegate>
@end

@implementation LBConflictsViewController {
    LBPhone *_phone;
    NSArray<LBPendingConflict *> *_conflicts;
    NSMutableDictionary<NSManagedObjectID *, LBPendingConflict *> *_editing;
}

- (instancetype)initWithPhone:(LBPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _phone = phone;
        _editing = [NSMutableDictionary dictionary];
        self.title = @"Conflicts";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:LBLocalStoreDidChangeNotification object:nil];
        [self reload];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reload {
    _conflicts = [_phone.store pendingConflicts];
    if ([self isViewLoaded]) [self.tableView reloadData];
}

- (NSString *)kindOf:(LBPendingConflict *)conflict {
    return [Record lbKindOfEntityNamed:conflict.objectEntityName ?: @""];
}

- (NSArray<NSString *> *)linesOf:(LBPendingConflict *)conflict {
    LBLocalStore *store = _phone.store;
    NSMutableArray *lines = [NSMutableArray array];
    if (conflict.deletedThere) [lines addObject:@"Deleted on the server; changed here."];
    if (conflict.deletedHere) [lines addObject:@"Deleted here; changed on the server, and back."];
    for (NSString *name in conflict.properties) {
        NSString *mine = conflict.deletedHere ? @"deleted" : [store textOfValue:conflict.mine[name] property:name ofConflict:conflict];
        NSString *theirs = conflict.deletedThere ? @"deleted" : [store textOfValue:conflict.theirs[name] property:name ofConflict:conflict];
        [lines addObject:[NSString stringWithFormat:@"%@ — mine %@, theirs %@", name, mine, theirs]];
    }
    return lines;
}

- (NSArray<NSString *> *)shownRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (LBPendingConflict *conflict in _conflicts) {
        for (NSString *line in [self linesOf:conflict]) [rows addObject:[NSString stringWithFormat:@"%@: %@", [self kindOf:conflict], line]];
    }
    return rows;
}

- (void)keepTheirs:(LBPendingConflict *)conflict {
    [_phone.store keepTheirs:conflict];
    [self reload];
}

- (BOOL)keepMine:(LBPendingConflict *)conflict problems:(NSArray<NSString *> **)problems {
    NSError *error = nil;
    BOOL kept = [_phone.store keepMine:conflict error:&error];
    if (!kept && problems) *problems = [LBLocalStore sentencesOfError:error];
    [self reload];
    return kept;
}

- (LBRecordFormViewController *)editByHand:(LBPendingConflict *)conflict {
    NSManagedObject *object = [_phone.store objectOfConflict:conflict];
    if (!object) return nil;
    _editing[object.objectID] = conflict;
    LBRecordFormViewController *form = [[LBRecordFormViewController alloc] initWithObject:object phone:_phone];
    form.delegate = self;
    [self.navigationController pushViewController:form animated:YES];
    return form;
}

- (void)recordFormDidSave:(LBRecordFormViewController *)form {
    LBPendingConflict *conflict = _editing[form.object.objectID];
    if (conflict) {
        [_editing removeObjectForKey:form.object.objectID];
        [_phone.store settleConflict:conflict];
    }
    [self reload];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MAX((NSInteger)_conflicts.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!_conflicts.count) return nil;
    LBPendingConflict *conflict = _conflicts[(NSUInteger)section];
    NSDateFormatter *said = [[NSDateFormatter alloc] init];
    said.dateStyle = NSDateFormatterShortStyle;
    said.timeStyle = NSDateFormatterShortStyle;
    return [NSString stringWithFormat:@"%@, %@", [self kindOf:conflict], [said stringFromDate:conflict.when]];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!_conflicts.count) return @"No conflicts. When a record is changed here and elsewhere before they meet, the server's stands, "
                                   @"and what you changed waits here for you to keep or let go.";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!_conflicts.count) return 0;
    return (NSInteger)[self linesOf:_conflicts[(NSUInteger)section]].count + 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    LBPendingConflict *conflict = _conflicts[(NSUInteger)indexPath.section];
    NSArray *lines = [self linesOf:conflict];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    NSUInteger row = (NSUInteger)indexPath.row;
    if (row < lines.count) {
        cell.textLabel.text = lines[row];
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSArray *actions = @[ @"Keep Theirs", @"Keep Mine", @"Edit by Hand…" ];
    cell.textLabel.text = actions[row - lines.count];
    cell.textLabel.textColor = self.view.tintColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!_conflicts.count) return;
    LBPendingConflict *conflict = _conflicts[(NSUInteger)indexPath.section];
    NSUInteger lines = [self linesOf:conflict].count, row = (NSUInteger)indexPath.row;
    if (row < lines) return;
    if (row == lines) {
        [self keepTheirs:conflict];
    } else if (row == lines + 1) {
        NSArray *problems = nil;
        if (![self keepMine:conflict problems:&problems]) LBTell(self, @"Not Kept", problems ?: @[]);
    } else if (![self editByHand:conflict]) {
        LBTell(self, @"Gone", @[ @"The server deleted it: keep yours to make it again, or theirs to let it go." ]);
    }
}

@end
