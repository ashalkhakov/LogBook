// A record's form (LBiOSControllers.h): fields, by kind, as the model has
// them; a service's items; an inspection's answers; receipts' photos.

#import "LBiOSControllers.h"
#import "LBDisplay.h"
#import "LBProcedures.h"
#import "Event+CoreDataClass.h"
#import "FillUp+CoreDataClass.h"
#import "Service+CoreDataClass.h"
#import "ServiceItem+CoreDataClass.h"
#import "Expense+CoreDataClass.h"
#import "ExpenseKind+CoreDataClass.h"
#import "Trip+CoreDataClass.h"
#import "MeterReading+CoreDataClass.h"
#import "Inspection+CoreDataClass.h"
#import "Checklist+CoreDataClass.h"
#import "Question+CoreDataClass.h"
#import "Answer+CoreDataClass.h"
#import "Attachment+CoreDataClass.h"
#import "CostKind+CoreDataClass.h"
#import "DistanceUnit+CoreDataClass.h"
#import "VolumeUnit+CoreDataClass.h"
#import "User+CoreDataClass.h"

typedef NS_ENUM(NSInteger, LBFieldKind) {
    LBFieldText,
    LBFieldNumber,     // a decimal, typed
    LBFieldInteger,    // a whole number, typed
    LBFieldDate,       // a moment, picked
    LBFieldSwitch,
    LBFieldChoice,     // one of objects, picked
};

/* A field: a title, the property it is (by selector), and for a quantity
   the to-one its unit is set in (or the attribute its currency is). */
@interface LBField : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *key;
@property (nonatomic) LBFieldKind kind;
@property (nonatomic, copy) NSString *unitKey;
@property (nonatomic, strong) id unit;
@property (nonatomic, copy) NSArray *choices;
@end

@implementation LBField
@end

static LBField *LBMakeField(NSString *title, SEL key, LBFieldKind kind) {
    LBField *field = [[LBField alloc] init];
    field.title = title;
    field.key = NSStringFromSelector(key);
    field.kind = kind;
    return field;
}

/* What the user says things in: their units and currency, else km, L and
   euros. */
static id LBFetchFirst(NSManagedObjectContext *context, Class cls, NSPredicate *predicate) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = predicate;
    return [[context executeFetchRequest:fetch error:NULL] firstObject];
}

static DistanceUnit *LBDistanceUnitOf(LBPhone *phone) {
    return phone.store.user.distanceUnit
        ?: LBFetchFirst(phone.store.context, [DistanceUnit class],
                        [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(code)), @"km"]);
}

static VolumeUnit *LBVolumeUnitOf(LBPhone *phone) {
    return phone.store.user.volumeUnit
        ?: LBFetchFirst(phone.store.context, [VolumeUnit class],
                        [NSPredicate predicateWithFormat:@"%K == %@", NSStringFromSelector(@selector(code)), @"L"]);
}

static NSString *LBCurrencyOf(LBPhone *phone) {
    return phone.store.user.currency.length ? phone.store.user.currency : @"EUR";
}

static NSArray *LBAll(NSManagedObjectContext *context, Class cls, NSPredicate *predicate, SEL sortedBy) {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(cls)];
    fetch.predicate = predicate;
    fetch.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(sortedBy) ascending:YES] ];
    return [context executeFetchRequest:fetch error:NULL] ?: @[];
}

static NSString *LBTitleOf(id object) {
    if (!object) return @"None";
    return [object respondsToSelector:@selector(lbTitle)] ? [(id<LBTitled>)object lbTitle] : [object description];
}

/* A number as typed, in the user's locale or with a point. */
static NSDecimalNumber *LBNumberOf(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!trimmed.length) return nil;
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:trimmed locale:[NSLocale currentLocale]];
    if ([number isEqualToNumber:[NSDecimalNumber notANumber]])
        number = [NSDecimalNumber decimalNumberWithString:[trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."]];
    return [number isEqualToNumber:[NSDecimalNumber notANumber]] ? nil : number;
}

static NSString *LBTextOfNumber(NSNumber *number) {
    if (!number) return @"";
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    f.usesGroupingSeparator = NO;
    f.maximumFractionDigits = 3;
    return [f stringFromNumber:number] ?: number.description;
}

/* An image no larger than 1600 pixels across, as a JPEG. */
/* A photo as it is kept and synced: a JPEG, its longest side no more than
   LBPhotoLongestSide pixels. */
CGFloat const LBPhotoLongestSide = 2000;

static NSData *LBJPEGOf(UIImage *image) {
    CGFloat longest = MAX(image.size.width, image.size.height);
    if (longest > LBPhotoLongestSide) {
        CGFloat scale = LBPhotoLongestSide / longest;
        CGSize size = CGSizeMake(floor(image.size.width * scale), floor(image.size.height * scale));
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
        format.scale = 1;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        }];
    }
    return UIImageJPEGRepresentation(image, 0.7);
}

enum { LBSectionFields, LBSectionItems, LBSectionPhotos, LBSectionCount };

@implementation LBRecordFormViewController {
    LBPhone *_phone;
    NSArray<LBField *> *_fields;
    BOOL _isNew;
}

+ (NSManagedObject *)newRecordOfKind:(NSString *)entityName phone:(LBPhone *)phone {
    LBLocalStore *store = phone.store;
    Vehicle *vehicle = phone.vehicle;
    User *user = store.user;
    if (!vehicle || !user) return nil;
    Record *record = (Record *)[NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:store.context];
    record.vehicle = vehicle;
    record.enteredBy = user;
    if ([record isKindOfClass:[Event class]]) {
        Event *event = (Event *)record;
        event.timestamp = LBNow();
        event.driver = user;
    }
    if ([record isKindOfClass:[FillUp class]]) {
        FillUp *fillUp = (FillUp *)record;
        fillUp.fuel = vehicle.fuel;
        fillUp.filledTheTank = YES;
        fillUp.volumeVolumeUnit = LBVolumeUnitOf(phone);
        fillUp.totalCurrency = LBCurrencyOf(phone);
    }
    if ([record isKindOfClass:[Service class]]) {
        Service *service = (Service *)record;
        service.currency = LBCurrencyOf(phone);
        service.serviceKind = [CostKind lbServiceKindsInContext:store.context].firstObject;
    }
    if ([record isKindOfClass:[Expense class]]) record.totalCurrency = LBCurrencyOf(phone);
    if ([record isKindOfClass:[Trip class]]) {
        Trip *trip = (Trip *)record;
        trip.moment = LBNow();
        trip.distanceDistanceUnit = LBDistanceUnitOf(phone);
    }
    return record;
}

+ (NSManagedObject *)newVehicleForPhone:(LBPhone *)phone {
    Vehicle *vehicle = (Vehicle *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Vehicle class])
                                                                inManagedObjectContext:phone.store.context];
    vehicle.owner = phone.store.user;
    vehicle.fuel = @"Petrol";
    vehicle.manufactureYear = (int32_t)[[NSCalendar currentCalendar] component:NSCalendarUnitYear fromDate:[NSDate date]];
    return vehicle;
}

- (instancetype)initWithObject:(NSManagedObject *)object phone:(LBPhone *)phone {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _object = object;
        _phone = phone;
        _isNew = object.isInserted;
        _warnings = @[];
        _problems = @[];
        _fields = [self fieldsOf:object];
        self.title = [object isKindOfClass:[Record class]] ? ((Record *)object).lbKind
                   : [object isKindOfClass:[Vehicle class]] ? (_isNew ? @"New Vehicle" : @"Vehicle") : object.entity.name;
    }
    return self;
}

- (NSArray<LBField *> *)fieldsOf:(NSManagedObject *)object {
    NSMutableArray<LBField *> *fields = [NSMutableArray array];
    NSManagedObjectContext *context = object.managedObjectContext;
    if ([object isKindOfClass:[Vehicle class]]) {
        [fields addObject:LBMakeField(@"Name", @selector(vehicleName), LBFieldText)];
        [fields addObject:LBMakeField(@"Make", @selector(make), LBFieldText)];
        [fields addObject:LBMakeField(@"Model", @selector(carModel), LBFieldText)];
        [fields addObject:LBMakeField(@"Year", @selector(manufactureYear), LBFieldInteger)];
        [fields addObject:LBMakeField(@"Fuel", @selector(fuel), LBFieldText)];
        [fields addObject:LBMakeField(@"Registration", @selector(registrationNumber), LBFieldText)];
        return fields;
    }
    if ([object isKindOfClass:[Trip class]]) {
        [fields addObject:LBMakeField(@"Started", @selector(timestamp), LBFieldDate)];
        [fields addObject:LBMakeField(@"Ended", @selector(moment), LBFieldDate)];
        LBField *distance = LBMakeField(@"Distance", @selector(distanceQuantity), LBFieldNumber);
        distance.unitKey = NSStringFromSelector(@selector(distanceDistanceUnit));
        distance.unit = LBDistanceUnitOf(_phone);
        [fields addObject:distance];
    } else if ([object isKindOfClass:[Event class]]) {
        [fields addObject:LBMakeField(@"When", @selector(timestamp), LBFieldDate)];
    }
    if ([object isKindOfClass:[Event class]]) {
        LBField *odometer = LBMakeField(@"Odometer", @selector(mileageQuantity), LBFieldNumber);
        odometer.unitKey = NSStringFromSelector(@selector(mileageDistanceUnit));
        odometer.unit = LBDistanceUnitOf(_phone);
        [fields addObject:odometer];
    }
    if ([object isKindOfClass:[FillUp class]]) {
        LBField *volume = LBMakeField(@"Volume", @selector(volumeQuantity), LBFieldNumber);
        volume.unitKey = NSStringFromSelector(@selector(volumeVolumeUnit));
        volume.unit = LBVolumeUnitOf(_phone);
        [fields addObject:volume];
        LBField *cost = LBMakeField(@"Cost", @selector(totalAmount), LBFieldNumber);
        cost.unitKey = NSStringFromSelector(@selector(totalCurrency));
        cost.unit = LBCurrencyOf(_phone);
        [fields addObject:cost];
        [fields addObject:LBMakeField(@"Full tank", @selector(filledTheTank), LBFieldSwitch)];
        [fields addObject:LBMakeField(@"Station", @selector(station), LBFieldText)];
    }
    if ([object isKindOfClass:[Service class]]) {
        [fields addObject:LBMakeField(@"Garage", @selector(garage), LBFieldText)];
        LBField *kind = LBMakeField(@"Kind", @selector(serviceKind), LBFieldChoice);
        kind.choices = [CostKind lbServiceKindsInContext:context];
        [fields addObject:kind];
        [fields addObject:LBMakeField(@"Title", @selector(title), LBFieldText)];
    }
    if ([object isKindOfClass:[Expense class]]) {
        LBField *kind = LBMakeField(@"Kind", @selector(expenseKind), LBFieldChoice);
        kind.choices = LBAll(context, [ExpenseKind class], nil, @selector(name));
        [fields addObject:kind];
        LBField *cost = LBMakeField(@"Cost", @selector(totalAmount), LBFieldNumber);
        cost.unitKey = NSStringFromSelector(@selector(totalCurrency));
        cost.unit = LBCurrencyOf(_phone);
        [fields addObject:cost];
    }
    if ([object isKindOfClass:[Trip class]]) {
        [fields addObject:LBMakeField(@"Purpose", @selector(purpose), LBFieldText)];
        [fields addObject:LBMakeField(@"To", @selector(wentToPlace), LBFieldText)];
    }
    if ([object isKindOfClass:[Inspection class]]) {
        LBField *checklist = LBMakeField(@"Checklist", @selector(checklist), LBFieldChoice);
        checklist.choices = LBAll(context, [Checklist class], nil, @selector(checklistName));
        [fields addObject:checklist];
    }
    if ([object isKindOfClass:[Record class]]) [fields addObject:LBMakeField(@"Note", @selector(note), LBFieldText)];
    return fields;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self
                                                                                          action:@selector(cancel:)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self
                                                                                           action:@selector(save:)];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (NSArray<NSString *> *)fieldTitles {
    NSMutableArray *titles = [NSMutableArray array];
    for (LBField *field in _fields) [titles addObject:field.title];
    return titles;
}

- (LBField *)fieldTitled:(NSString *)title {
    for (LBField *field in _fields) {
        if ([field.title isEqualToString:title]) return field;
    }
    return nil;
}

/* A field's value set, and what goes with it: a quantity's unit, an
   amount's currency (or none, with none). */
- (void)setValue:(id)value ofField:(LBField *)field {
    [_object setValue:value forKey:field.key];
    if (field.unitKey) [_object setValue:value ? field.unit : nil forKey:field.unitKey];
}

- (BOOL)enter:(id)value intoField:(NSString *)title {
    LBField *field = [self fieldTitled:title];
    if (!field) return NO;
    switch (field.kind) {
        case LBFieldText:
            [self setValue:[value length] ? value : nil ofField:field];
            break;
        case LBFieldNumber:
            [self setValue:LBNumberOf(value) ofField:field];
            break;
        case LBFieldInteger:
            [self setValue:@([value integerValue]) ofField:field];
            break;
        case LBFieldDate:
        case LBFieldChoice:
            [self setValue:value ofField:field];
            break;
        case LBFieldSwitch:
            [self setValue:@([value boolValue]) ofField:field];
            break;
    }
    if ([self isViewLoaded]) [self.tableView reloadData];
    return YES;
}

#pragma mark Items, answers, photos

- (Service *)service {
    return [_object isKindOfClass:[Service class]] ? (Service *)_object : nil;
}

- (Inspection *)inspection {
    return [_object isKindOfClass:[Inspection class]] ? (Inspection *)_object : nil;
}

- (NSArray<ServiceItem *> *)items {
    NSMutableArray *items = [NSMutableArray array];
    for (ServiceItem *item in self.service.serviceItems) {
        if (!item.isDeleted) [items addObject:item];
    }
    [items sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(task)) ascending:YES] ]];
    return items;
}

- (NSArray<Question *> *)questions {
    NSArray *questions = self.inspection.checklist.questions.allObjects ?: @[];
    return [questions sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(position))
                                                                                   ascending:YES] ]];
}

- (Answer *)answerTo:(Question *)question {
    for (Answer *answer in self.inspection.answers) {
        if (answer.question == question && !answer.isDeleted) return answer;
    }
    return nil;
}

- (void)addItemTask:(NSString *)task cost:(NSDecimalNumber *)cost {
    Service *service = self.service;
    if (!service || !task.length) return;
    ServiceItem *item = (ServiceItem *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([ServiceItem class])
                                                                     inManagedObjectContext:_object.managedObjectContext];
    item.service = service;
    item.task = task;
    item.costAmount = cost;
    item.costCurrency = service.currency ?: LBCurrencyOf(_phone);
    if ([self isViewLoaded]) [self.tableView reloadData];
}

- (void)answer:(BOOL)yes toQuestionAt:(NSUInteger)index {
    NSArray *questions = [self questions];
    if (index >= questions.count) return;
    Question *question = questions[index];
    Answer *answer = [self answerTo:question];
    if (!answer) {
        answer = (Answer *)[NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Answer class])
                                                         inManagedObjectContext:_object.managedObjectContext];
        answer.inspection = self.inspection;
        answer.question = question;
    }
    answer.yesNo = yes ? @"Yes" : @"No";
}

- (NSArray<Attachment *> *)attachments {
    if (![_object isKindOfClass:[Record class]]) return @[];
    NSMutableArray *attachments = [NSMutableArray array];
    for (Attachment *attachment in ((Record *)_object).attachments) {
        if (!attachment.isDeleted) [attachments addObject:attachment];
    }
    [attachments sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(fileName)) ascending:YES] ]];
    return attachments;
}

- (void)addImageData:(NSData *)jpeg {
    if (![_object isKindOfClass:[Record class]] || !jpeg) return;
    [_phone.store attachImage:jpeg toRecord:(Record *)_object];
    if ([self isViewLoaded]) [self.tableView reloadData];
}

- (void)pickPhoto {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]
                            ? UIImagePickerControllerSourceTypeCamera : UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image) [self addImageData:LBJPEGOf(image)];
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark Saving

- (void)finish {
    if (self.navigationController.viewControllers.firstObject == self && self.navigationController.presentingViewController) {
        [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (BOOL)saveIgnoringWarnings:(BOOL)ignoring {
    [self.view endEditing:YES];
    LBLocalStore *store = _phone.store;
    NSArray<NSError *> *said = [store warnings];
    NSMutableArray *warnings = [NSMutableArray array];
    for (NSError *warning in said) [warnings addObject:warning.localizedDescription ?: @""];
    _warnings = warnings;
    _problems = @[];
    if (warnings.count && !ignoring) return NO;
    [store acceptWarnings:said];
    NSError *error = nil;
    if (![store save:&error]) {
        NSArray *sentences = [LBLocalStore sentencesOfError:error];
        _problems = sentences.count ? sentences : @[ error.localizedDescription ?: @"Not saved." ];
        return NO;
    }
    if ([_delegate respondsToSelector:@selector(recordFormDidSave:)]) [_delegate recordFormDidSave:self];
    return YES;
}

- (void)saveAnyway:(id)sender {
    if ([self saveIgnoringWarnings:YES]) [self finish];
    else [self tell:@"Not Saved" lines:_problems];
}

- (void)tell:(NSString *)title lines:(NSArray<NSString *> *)lines {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:[lines componentsJoinedByString:@"\n\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)save:(id)sender {
    if ([self saveIgnoringWarnings:NO]) {
        [self finish];
        return;
    }
    if (_problems.count) {
        [self tell:@"Not Saved" lines:_problems];
        return;
    }
    /* What ought not to be, said before it is saved: the user may. */
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Before You Save"
                                                                   message:[_warnings componentsJoinedByString:@"\n\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak LBRecordFormViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Go Back" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save Anyway" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf saveAnyway:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (IBAction)cancel:(id)sender {
    [self.view endEditing:YES];
    [_phone.store.context rollback];
    [self finish];
}

#pragma mark The table

- (BOOL)hasItems {
    return self.service != nil || self.inspection != nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return LBSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == LBSectionItems) return self.service ? @"Items" : self.inspection ? @"Answers" : nil;
    if (section == LBSectionPhotos) return [_object isKindOfClass:[Record class]] ? @"Receipts" : nil;
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == LBSectionFields) return (NSInteger)_fields.count;
    if (section == LBSectionItems) {
        if (self.service) return (NSInteger)[self items].count + 1;
        if (self.inspection) return (NSInteger)[self questions].count;
        return 0;
    }
    return [_object isKindOfClass:[Record class]] ? (NSInteger)[self attachments].count + 1 : 0;
}

- (UITextField *)textFieldFor:(NSInteger)row field:(LBField *)field {
    UITextField *text = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 190, 34)];
    text.textAlignment = NSTextAlignmentRight;
    text.tag = row;
    text.delegate = self;
    text.clearButtonMode = UITextFieldViewModeWhileEditing;
    id value = [_object valueForKey:field.key];
    if (field.kind == LBFieldNumber || field.kind == LBFieldInteger) {
        text.keyboardType = field.kind == LBFieldNumber ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumberPad;
        text.text = LBTextOfNumber(value);
        id unit = field.unit;
        text.placeholder = [unit isKindOfClass:[NSString class]] ? unit : unit ? LBTitleOf(unit) : nil;
    } else {
        text.text = value ?: @"";
        text.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    }
    [text addTarget:self action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
    return text;
}

- (void)textChanged:(UITextField *)text {
    LBField *field = _fields[(NSUInteger)text.tag];
    [self enterWithoutReloading:text.text field:field];
}

- (void)enterWithoutReloading:(id)value field:(LBField *)field {
    if (field.kind == LBFieldNumber) [self setValue:LBNumberOf(value) ofField:field];
    else if (field.kind == LBFieldInteger) [self setValue:@([value integerValue]) ofField:field];
    else [self setValue:[value length] ? value : nil ofField:field];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)dateChanged:(UIDatePicker *)picker {
    [self setValue:picker.date ofField:_fields[(NSUInteger)picker.tag]];
}

- (void)switchChanged:(UISwitch *)toggle {
    [self setValue:@(toggle.isOn) ofField:_fields[(NSUInteger)toggle.tag]];
}

- (void)answerChanged:(UISwitch *)toggle {
    [self answer:toggle.isOn toQuestionAt:(NSUInteger)toggle.tag];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSInteger row = indexPath.row;
    if (indexPath.section == LBSectionFields) {
        LBField *field = _fields[(NSUInteger)row];
        cell.textLabel.text = field.title;
        id value = [_object valueForKey:field.key];
        switch (field.kind) {
            case LBFieldText:
            case LBFieldNumber:
            case LBFieldInteger:
                cell.accessoryView = [self textFieldFor:row field:field];
                break;
            case LBFieldDate: {
                UIDatePicker *picker = [[UIDatePicker alloc] init];
                picker.datePickerMode = UIDatePickerModeDateAndTime;
                if (@available(iOS 14.0, *)) picker.preferredDatePickerStyle = UIDatePickerStyleCompact;
                picker.date = value ?: [NSDate date];
                picker.tag = row;
                [picker addTarget:self action:@selector(dateChanged:) forControlEvents:UIControlEventValueChanged];
                [picker sizeToFit];
                cell.accessoryView = picker;
                break;
            }
            case LBFieldSwitch: {
                UISwitch *toggle = [[UISwitch alloc] init];
                toggle.on = [value boolValue];
                toggle.tag = row;
                [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = toggle;
                break;
            }
            case LBFieldChoice:
                cell.detailTextLabel.text = LBTitleOf(value);
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                break;
        }
        return cell;
    }
    if (indexPath.section == LBSectionItems && self.service) {
        NSArray<ServiceItem *> *items = [self items];
        if ((NSUInteger)row < items.count) {
            ServiceItem *item = items[(NSUInteger)row];
            cell.textLabel.text = item.task;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", LBTextOfNumber(item.costAmount), item.costCurrency ?: @""];
        } else {
            cell.textLabel.text = @"Add Item…";
            cell.textLabel.textColor = self.view.tintColor;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        return cell;
    }
    if (indexPath.section == LBSectionItems && self.inspection) {
        Question *question = [self questions][(NSUInteger)row];
        cell.textLabel.text = question.questionText;
        cell.textLabel.numberOfLines = 0;
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [[self answerTo:question].yesNo isEqualToString:@"Yes"];
        toggle.tag = row;
        [toggle addTarget:self action:@selector(answerChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }
    NSArray<Attachment *> *attachments = [self attachments];
    if ((NSUInteger)row < attachments.count) {
        Attachment *attachment = attachments[(NSUInteger)row];
        cell.textLabel.text = [NSString stringWithFormat:@"Receipt %ld", (long)row + 1];
        cell.imageView.image = attachment.content ? [UIImage imageWithData:attachment.content] : nil;
    } else {
        cell.textLabel.text = @"Add Photo…";
        cell.textLabel.textColor = self.view.tintColor;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == LBSectionFields) {
        LBField *field = _fields[(NSUInteger)indexPath.row];
        if (field.kind == LBFieldChoice) [self choose:field from:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == LBSectionItems && self.service && (NSUInteger)indexPath.row == [self items].count) {
        [self askForItem];
    } else if (indexPath.section == LBSectionPhotos && (NSUInteger)indexPath.row == [self attachments].count) {
        [self pickPhoto];
    }
}

- (void)choose:(LBField *)field from:(UITableViewCell *)cell {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:field.title message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak LBRecordFormViewController *weakSelf = self;
    for (id choice in field.choices) {
        [sheet addAction:[UIAlertAction actionWithTitle:LBTitleOf(choice) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [weakSelf enter:choice intoField:field.title];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)askForItem {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Item" message:@"What was done, and what it cost."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Oil change";
        field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Cost";
        field.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    __weak LBRecordFormViewController *weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *task = weakAlert.textFields[0].text;
        [weakSelf addItemTask:task cost:LBNumberOf(weakAlert.textFields[1].text) ?: [NSDecimalNumber zero]];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
