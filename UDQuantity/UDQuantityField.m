#import "UDQuantityField.h"

static const CGFloat UDGap = 6;
static const CGFloat UDFieldHeight = 22;

/* The units listed for what is typed: those whose code begins with it
   first, then those whose code or name has it elsewhere. */
static BOOL UDHas(NSString *text, NSString *typed) {
    return text && [text rangeOfString:typed options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
}

static BOOL UDBegins(NSString *text, NSString *typed) {
    return text && [text rangeOfString:typed options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSAnchoredSearch].location
                       != NSNotFound;
}

@interface UDQuantityField () <NSComboBoxDataSource, NSComboBoxDelegate, NSTextFieldDelegate>
@end

@implementation UDQuantityField {
    NSArray *_listed;
    NSMutableDictionary<NSString *, NSDictionary *> *_bound;
    NSNumberFormatter *_formatter;
    BOOL _showing;
}

+ (void)initialize {
    if (self == [UDQuantityField class]) {
        [self exposeBinding:@"value"];
        [self exposeBinding:@"unit"];
    }
}

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) [self setUp];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) [self setUp];
    return self;
}

- (void)setUp {
    _decimals = 3;
    _unitWidth = 90;
    _showsValue = YES;
    _enabled = YES;
    _bound = [NSMutableDictionary dictionary];

    _formatter = [[NSNumberFormatter alloc] init];
    _formatter.formatterBehavior = NSNumberFormatterBehavior10_4;
    _formatter.numberStyle = NSNumberFormatterDecimalStyle;
    _formatter.generatesDecimalNumbers = YES;
    _formatter.usesGroupingSeparator = NO;
    _formatter.minimumIntegerDigits = 1;

    _valueField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _valueField.alignment = NSTextAlignmentRight;
    _valueField.formatter = _formatter;
    _valueField.delegate = self;
    [_valueField.cell setScrollable:YES];
    [_valueField.cell setSendsActionOnEndEditing:YES];
    [self addSubview:_valueField];

    _unitBox = [[NSComboBox alloc] initWithFrame:NSZeroRect];
    _unitBox.usesDataSource = YES;
    _unitBox.dataSource = self;
    _unitBox.delegate = self;
    _unitBox.completes = NO;
    _unitBox.numberOfVisibleItems = 12;
    [_unitBox.cell setScrollable:YES];
    [self addSubview:_unitBox];

    [self layOut];
    [self showFormat];
}

/* Its parts named by its identifier, as it is shown: AppKit's
   identifier is not to be overridden. */
- (void)nameParts {
    NSString *identifier = self.identifier;
    _valueField.identifier = identifier ? [identifier stringByAppendingString:@"Value"] : nil;
    _unitBox.identifier = identifier ? [identifier stringByAppendingString:@"Unit"] : nil;
}

- (void)viewWillMoveToWindow:(NSWindow *)window {
    [super viewWillMoveToWindow:window];
    [self nameParts];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self nameParts];
    [self reloadUnits];
}

#pragma mark Laid out

- (void)layOut {
    NSRect bounds = self.bounds;
    CGFloat boxHeight = MIN(NSHeight(bounds), 26);
    CGFloat unitWidth = _showsValue ? MIN(_unitWidth, NSWidth(bounds)) : NSWidth(bounds);
    _unitBox.frame = NSMakeRect(NSMaxX(bounds) - unitWidth, floor(NSMidY(bounds) - boxHeight / 2), unitWidth, boxHeight);
    _unitBox.autoresizingMask = _showsValue ? NSViewMinXMargin : NSViewWidthSizable;
    CGFloat fieldWidth = MAX(0, NSWidth(bounds) - unitWidth - UDGap);
    CGFloat fieldHeight = MIN(NSHeight(bounds), UDFieldHeight);
    _valueField.frame = NSMakeRect(NSMinX(bounds), floor(NSMidY(bounds) - fieldHeight / 2), fieldWidth, fieldHeight);
    _valueField.autoresizingMask = NSViewWidthSizable;
    _valueField.hidden = !_showsValue;
}

- (void)setUnitWidth:(CGFloat)unitWidth {
    _unitWidth = unitWidth;
    [self layOut];
}

- (void)setShowsValue:(BOOL)showsValue {
    _showsValue = showsValue;
    [self layOut];
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    _valueField.enabled = enabled;
    _unitBox.enabled = enabled;
}

#pragma mark Units

- (void)setUnits:(id<UDQuantityUnits>)units {
    _units = units;
    [self reloadUnits];
}

/* Asked of the source each time: an array controller's objects may be
   fetched after the field is made. */
- (NSArray *)allUnits {
    return [_units unitsForQuantityField:self] ?: @[];
}

/* Those listed: those for what is typed, else all. */
- (NSArray *)listed {
    return _listed ?: [self allUnits];
}

- (void)reloadUnits {
    _listed = nil;
    [_unitBox reloadData];
    [self showUnit];
    [self showFormat];
}

- (NSString *)codeOf:(id)unit {
    return unit ? [_units quantityField:self codeOfUnit:unit] ?: [unit description] : @"";
}

- (NSString *)nameOf:(id)unit {
    if ([_units respondsToSelector:@selector(quantityField:nameOfUnit:)]) {
        NSString *name = [_units quantityField:self nameOfUnit:unit];
        if (name.length) return name;
    }
    return [self codeOf:unit];
}

- (NSArray *)unitsFor:(NSString *)typed {
    if (!typed.length) return nil;
    NSMutableArray *first = [NSMutableArray array];
    NSMutableArray *then = [NSMutableArray array];
    for (id unit in [self allUnits]) {
        NSString *code = [self codeOf:unit];
        if (UDBegins(code, typed)) [first addObject:unit];
        else if (UDHas(code, typed) || UDHas([self nameOf:unit], typed)) [then addObject:unit];
    }
    [first addObjectsFromArray:then];
    return first;
}

- (BOOL)takeTypedUnit {
    NSString *typed = [_unitBox.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    id taken = nil;
    BOOL found = typed.length == 0;
    for (id unit in [self allUnits]) {
        if (found) break;
        if ([[self codeOf:unit] caseInsensitiveCompare:typed] == NSOrderedSame || [[self nameOf:unit] isEqualToString:typed]) {
            taken = unit;
            found = YES;
        }
    }
    if (!found) {
        NSArray *those = [self unitsFor:typed];
        if (those.count == 1) {
            taken = those.firstObject;
            found = YES;
        }
    }
    _listed = nil;
    [_unitBox reloadData];
    if (found && ![self same:taken as:_unit]) {
        self.unit = taken;
        [self push:@"unit" value:_unit];
    }
    [self showUnit];
    return found;
}

- (BOOL)same:(id)a as:(id)b {
    return a == b || [a isEqual:b];
}

#pragma mark Value and unit

- (void)setValue:(NSDecimalNumber *)value {
    _value = [value copy];
    [self showValue];
}

- (void)setUnit:(id)unit {
    _unit = unit;
    [self showUnit];
    [self showFormat];
}

- (void)showValue {
    _showing = YES;
    _valueField.objectValue = _value;
    _showing = NO;
}

- (void)showUnit {
    _showing = YES;
    _unitBox.stringValue = [self codeOf:_unit];
    _showing = NO;
}

/* The number said with the unit's decimals: a currency's as many always,
   a measure's up to the field's. */
- (void)showFormat {
    BOOL fixed = _unit && [_units respondsToSelector:@selector(quantityField:decimalsOfUnit:)];
    NSInteger decimals = fixed ? [_units quantityField:self decimalsOfUnit:_unit] : _decimals;
    _formatter.minimumFractionDigits = fixed ? decimals : 0;
    _formatter.maximumFractionDigits = decimals;
    [self showValue];
}

#pragma mark The box and the field

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)box {
    return (NSInteger)[self listed].count;
}

- (id)comboBox:(NSComboBox *)box objectValueForItemAtIndex:(NSInteger)index {
    NSArray *listed = [self listed];
    return index >= 0 && index < (NSInteger)listed.count ? [self nameOf:listed[index]] : @"";
}

- (NSUInteger)comboBox:(NSComboBox *)box indexOfItemWithStringValue:(NSString *)string {
    NSArray *listed = [self listed];
    for (NSUInteger i = 0; i < listed.count; i++) {
        if ([[self nameOf:listed[i]] isEqualToString:string] || [[self codeOf:listed[i]] caseInsensitiveCompare:string] == NSOrderedSame)
            return i;
    }
    return NSNotFound;
}

- (void)comboBoxSelectionDidChange:(NSNotification *)note {
    NSInteger index = _unitBox.indexOfSelectedItem;
    NSArray *listed = [self listed];
    if (_showing || index < 0 || index >= (NSInteger)listed.count) return;
    id unit = listed[index];
    if ([self same:unit as:_unit]) return;
    _unit = unit;
    [self showFormat];
    [self push:@"unit" value:_unit];
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (note.object != _unitBox) return;
    _listed = [self unitsFor:[_unitBox.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    [_unitBox reloadData];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    if (note.object == _unitBox) {
        [self takeTypedUnit];
    } else if (note.object == _valueField) {
        id typed = _valueField.objectValue;
        NSDecimalNumber *value = [typed isKindOfClass:[NSDecimalNumber class]] ? typed
                                 : [typed isKindOfClass:[NSNumber class]] ? [NSDecimalNumber decimalNumberWithDecimal:[typed decimalValue]]
                                                                           : nil;
        if ([self same:value as:_value]) return;
        _value = value;
        [self push:@"value" value:_value];
    }
}

#pragma mark Bindings

- (void)bind:(NSString *)binding toObject:(id)object withKeyPath:(NSString *)keyPath options:(NSDictionary *)options {
    if (![binding isEqualToString:@"value"] && ![binding isEqualToString:@"unit"]) {
        [super bind:binding toObject:object withKeyPath:keyPath options:options];
        return;
    }
    [self unbind:binding];
    _bound[binding] = @{
        NSObservedObjectKey : object,
        NSObservedKeyPathKey : keyPath,
        NSOptionsKey : options ?: @{},
    };
    [object addObserver:self forKeyPath:keyPath options:0 context:(__bridge void *)binding];
    [self pull:binding];
}

- (void)unbind:(NSString *)binding {
    NSDictionary *info = _bound[binding];
    if (!info) {
        [super unbind:binding];
        return;
    }
    [info[NSObservedObjectKey] removeObserver:self forKeyPath:info[NSObservedKeyPathKey]];
    [_bound removeObjectForKey:binding];
}

- (NSDictionary *)infoForBinding:(NSString *)binding {
    return _bound[binding] ?: [super infoForBinding:binding];
}

- (void)dealloc {
    for (NSString *binding in _bound.allKeys) [self unbind:binding];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    for (NSString *binding in _bound) {
        NSDictionary *info = _bound[binding];
        if (info[NSObservedObjectKey] == object && [info[NSObservedKeyPathKey] isEqualToString:keyPath]) [self pull:binding];
    }
}

/* What the bound object has, shown: a controller's no selection, many or
   not applicable shown as nothing, and not to be changed. */
- (void)pull:(NSString *)binding {
    NSDictionary *info = _bound[binding];
    id value = [info[NSObservedObjectKey] valueForKeyPath:info[NSObservedKeyPathKey]];
    BOOL marker = NSIsControllerMarker(value);
    if (marker || value == [NSNull null]) value = nil;
    if ([binding isEqualToString:@"value"]) {
        if (value && ![value isKindOfClass:[NSDecimalNumber class]])
            value = [value isKindOfClass:[NSNumber class]] ? [NSDecimalNumber decimalNumberWithDecimal:[value decimalValue]] : nil;
        self.value = value;
    } else {
        self.unit = value;
    }
    BOOL editable = YES;
    for (NSString *each in _bound) {
        NSDictionary *one = _bound[each];
        if (NSIsControllerMarker([one[NSObservedObjectKey] valueForKeyPath:one[NSObservedKeyPathKey]])) editable = NO;
    }
    _valueField.enabled = _enabled && editable;
    _unitBox.enabled = _enabled && editable;
}

/* What was typed, given to the bound object; checked first when the
   binding validates immediately, and shown as it was when it is not
   valid. */
- (void)push:(NSString *)binding value:(id)value {
    NSDictionary *info = _bound[binding];
    if (!info) return;
    id object = info[NSObservedObjectKey];
    NSString *keyPath = info[NSObservedKeyPathKey];
    if ([info[NSOptionsKey][NSValidatesImmediatelyBindingOption] boolValue]) {
        NSError *error = nil;
        id checked = value;
        if (![object validateValue:&checked forKeyPath:keyPath error:&error]) {
            if (error) [self presentError:error];
            [self pull:binding];
            return;
        }
        value = checked;
    }
    [object setValue:value forKeyPath:keyPath];
}

@end

@implementation UDCurrencies

- (instancetype)init {
    if ((self = [super init])) _codes = [NSLocale commonISOCurrencyCodes] ?: @[];
    return self;
}

+ (NSString *)nameOfCode:(NSString *)code {
    NSString *name = [[NSLocale currentLocale] displayNameForKey:NSLocaleCurrencyCode value:code];
    return name.length && ![name isEqualToString:code] ? [NSString stringWithFormat:@"%@ — %@", code, name] : code;
}

+ (NSInteger)decimalsOfCode:(NSString *)code {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.formatterBehavior = NSNumberFormatterBehavior10_4;
    formatter.numberStyle = NSNumberFormatterCurrencyStyle;
    formatter.currencyCode = code;
    return (NSInteger)formatter.maximumFractionDigits;
}

- (NSArray *)unitsForQuantityField:(UDQuantityField *)field {
    return _codes;
}

- (NSString *)quantityField:(UDQuantityField *)field codeOfUnit:(id)unit {
    return [unit description];
}

- (NSString *)quantityField:(UDQuantityField *)field nameOfUnit:(id)unit {
    return [UDCurrencies nameOfCode:[unit description]];
}

- (NSInteger)quantityField:(UDQuantityField *)field decimalsOfUnit:(id)unit {
    return [UDCurrencies decimalsOfCode:[unit description]];
}

@end

@implementation UDKeyPathUnits

- (instancetype)init {
    if ((self = [super init])) {
        _objects = @[];
        _codeKeyPath = @"description";
    }
    return self;
}

- (NSArray *)unitsForQuantityField:(UDQuantityField *)field {
    return _controller ? _controller.arrangedObjects : _objects;
}

- (NSString *)quantityField:(UDQuantityField *)field codeOfUnit:(id)unit {
    return [[unit valueForKeyPath:_codeKeyPath] description] ?: @"";
}

- (NSString *)quantityField:(UDQuantityField *)field nameOfUnit:(id)unit {
    return _nameKeyPath ? [[unit valueForKeyPath:_nameKeyPath] description] : nil;
}

@end
