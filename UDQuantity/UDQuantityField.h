// UDQuantityField (underivable.org): an amount and its unit in one field, a
// number and, beside it, the unit picked from a list: money and its
// currency, a distance and its unit. Foundation and AppKit only, nothing
// of the app it is in, to be moved to a repository of its own.
//
// The unit is typed or picked: what is typed narrows the list to the
// units whose code or name has it ("eur", "dollar", "gallon"), and on
// leaving the box an exact code, or the one unit left, is taken; anything
// else goes back to the unit before. The number is said with the unit's
// decimals (a currency's: 2 for EUR, 0 for JPY).
//
// In a XIB, a custom view of the class with two bindings, value (an
// NSDecimalNumber) and unit (the unit as its units source has it: a code,
// an object), as any control's; its units source an object of the XIB
// (a UDCurrencies, a UDKeyPathUnits) connected to its units outlet, or
// set in code. Its number field and unit box are named by its identifier,
// with "Value" and with "Unit" ("FillUpTotalValue", "FillUpTotalUnit"), as
// tests and accessibility find them.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UDQuantityField;

// What a quantity field's units are, and how each is said.
@protocol UDQuantityUnits <NSObject>
// The units, in the order listed.
- (NSArray *)unitsForQuantityField:(UDQuantityField *)field;
// A unit said short, as the box shows it chosen and it is typed: "EUR", "km".
- (NSString *)quantityField:(UDQuantityField *)field codeOfUnit:(id)unit;
@optional
// Said in full, as listed and searched: "EUR — Euro".
- (NSString *)quantityField:(UDQuantityField *)field nameOfUnit:(id)unit;
// How many decimals an amount of it has; the field's own when not said.
- (NSInteger)quantityField:(UDQuantityField *)field decimalsOfUnit:(id)unit;
@end

@interface UDQuantityField : NSView
// Kept: a XIB's units source is one of its objects and nothing else's.
@property (nonatomic, strong, nullable) IBOutlet id<UDQuantityUnits> units;
@property (nonatomic, copy, nullable) NSDecimalNumber *value;
@property (nonatomic, strong, nullable) id unit;
// Decimals where the units say none (3 by default).
@property (nonatomic) NSInteger decimals;
// The unit's box's width (90 by default).
@property (nonatomic) CGFloat unitWidth;
// NO: the unit only (a currency picked, no amount).
@property (nonatomic) BOOL showsValue;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) NSTextField *valueField;
@property (nonatomic, readonly) NSComboBox *unitBox;
// The units again, as their source says them now.
- (void)reloadUnits;
// What is typed in the box taken as a unit, as leaving it does: YES when
// one was.
- (BOOL)takeTypedUnit;
@end

// A units source of currencies by their ISO 4217 codes: named and with the
// decimals the user's locale gives each.
@interface UDCurrencies : NSObject <UDQuantityUnits>
// The codes listed; the platform's common ones by default.
@property (nonatomic, copy) NSArray<NSString *> *codes;
// "EUR — Euro", in the user's language; the code alone where it has no name.
+ (NSString *)nameOfCode:(NSString *)code;
// The decimals of an amount of it, in the user's locale: 2 for EUR, 0 for JPY.
+ (NSInteger)decimalsOfCode:(NSString *)code;
@end

// A units source of objects, each said by a key path of it ("code"), and
// in full by another ("name") where one is given. In a XIB, its key paths
// are user-defined runtime attributes, and its objects an array
// controller's, connected to its controller outlet.
@interface UDKeyPathUnits : NSObject <UDQuantityUnits>
// The objects, when no controller is.
@property (nonatomic, copy) NSArray *objects;
@property (nonatomic, weak, nullable) IBOutlet NSArrayController *controller;
@property (nonatomic, copy) NSString *codeKeyPath;
@property (nonatomic, copy, nullable) NSString *nameKeyPath;
@end

NS_ASSUME_NONNULL_END
