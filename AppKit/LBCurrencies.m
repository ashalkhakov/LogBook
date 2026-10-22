#import "LBCurrencies.h"
#import "LBStore.h"

@implementation LBCurrencies

- (instancetype)init {
    if ((self = [super init])) {
        NSEntityDescription *rate = [LBStore model].entitiesByName[@"ExchangeRate"];
        NSAttributeDescription *currency = rate.attributesByName[@"baseCurrency"];
        NSArray *codes = currency ? [LBCurrencies allowedValuesOfAttribute:currency] : nil;
        if (codes.count) self.codes = codes;
    }
    return self;
}

+ (NSArray<NSString *> *)allowedValuesOfAttribute:(NSAttributeDescription *)attribute {
    NSString *annotations = attribute.userInfo[@"OData.annotations"];
    NSData *data = [annotations dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSArray *allowed = [parsed isKindOfClass:[NSDictionary class]] ? parsed[@"Validation.AllowedValues"] : nil;
    if (![allowed isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *values = [NSMutableArray array];
    for (NSDictionary *each in allowed) {
        id value = [each isKindOfClass:[NSDictionary class]] ? each[@"Value"] : nil;
        if ([value isKindOfClass:[NSString class]]) [values addObject:value];
    }
    return values;
}

@end
