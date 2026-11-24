#import "LBRuleIssues.h"
#import <ORMRuntime/ORMValidator.h>

/* Each error an error holds, its details' each. */
static void LBIssuesOf(NSError *error, NSMutableArray<NSError *> *into) {
    NSArray *detailed = error.userInfo[NSDetailedErrorsKey];
    if ([detailed isKindOfClass:[NSArray class]] && detailed.count) {
        for (id each in detailed)
            if ([each isKindOfClass:[NSError class]]) LBIssuesOf(each, into);
        return;
    }
    [into addObject:error];
}

static NSArray<NSString *> *LBKeysOf(NSError *error) {
    NSArray *keys = error.userInfo[@"ORMKeys"];
    if ([keys isKindOfClass:[NSArray class]] && keys.count) return keys;
    NSString *key = error.userInfo[NSValidationKeyErrorKey];
    return [key isKindOfClass:[NSString class]] ? @[ key ] : @[];
}

static BOOL LBEmpty(id value) {
    return value == nil || value == [NSNull null] || ([value isKindOfClass:[NSString class]] && ![value length])
           || ([value isKindOfClass:[NSSet class]] && ![value count]);
}

@implementation LBRuleIssues

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)issuesOf:(NSManagedObject *)object {
    if (!object || object.isDeleted || !object.managedObjectContext) return @{};
    NSMutableArray<NSError *> *found = [NSMutableArray array];
    NSError *error = nil;
    BOOL valid = object.isInserted ? [object validateForInsert:&error] : [object validateForUpdate:&error];
    if (!valid && error) LBIssuesOf(error, found);
    ORMValidator *validator = [ORMValidator validatorNamed:@"Logbook" error:NULL];
    for (NSError *each in [validator violationsOf:object deontic:NO] ?: @[]) LBIssuesOf(each, found);
    NSMutableDictionary<NSString *, NSMutableOrderedSet *> *said = [NSMutableDictionary dictionary];
    for (NSError *each in found) {
        NSString *sentence = each.localizedDescription;
        if (!sentence.length) continue;
        for (NSString *key in LBKeysOf(each)) {
            if (!said[key]) said[key] = [NSMutableOrderedSet orderedSet];
            [said[key] addObject:sentence];
        }
    }
    NSMutableDictionary *issues = [NSMutableDictionary dictionary];
    for (NSString *key in said) issues[key] = said[key].array;
    return issues;
}

+ (BOOL)isMandatory:(NSPropertyDescription *)property {
    return property && (!property.isOptional || [property.userInfo[@"ormkit.mandatory"] isEqual:@"YES"]);
}

+ (BOOL)isRequired:(NSString *)key of:(NSManagedObject *)object issues:(NSDictionary<NSString *, NSArray<NSString *> *> *)issues {
    if ([self isMandatory:object.entity.propertiesByName[key]]) return YES;
    return [issues[key] count] && LBEmpty([object valueForKey:key]);
}

@end
