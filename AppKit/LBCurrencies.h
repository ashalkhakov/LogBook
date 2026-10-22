// The currencies a quantity field lists (UDQuantityField.h): those the
// model allows (Currency's values, ISO 4217's in use), as the model's
// annotation on an exchange rate's currency gives them; in a XIB, an object
// of the class connected to each money field's units outlet.

#import "UDQuantityField.h"
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@interface LBCurrencies : UDCurrencies
// The values an attribute of the model is allowed (its
// Validation.AllowedValues annotation); nil when any.
+ (nullable NSArray<NSString *> *)allowedValuesOfAttribute:(NSAttributeDescription *)attribute;
@end

NS_ASSUME_NONNULL_END
