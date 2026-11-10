#import "LBFormValues.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>

static NSISO8601DateFormatter *LBFormDates(void) {
    static NSISO8601DateFormatter *dates;
    if (!dates) dates = [[NSISO8601DateFormatter alloc] init];
    return dates;
}

static NSLocale *LBFormPOSIX(void) {
    return [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
}

@implementation LBFormValues

- (instancetype)initWithSession:(ORMFormSession *)session context:(NSManagedObjectContext *)context {
    if ((self = [super init])) {
        _session = session;
        _context = context;
    }
    return self;
}

- (void)reload {
    for (ORMFormElement *element in _session.form.elements) [self willChangeValueForKey:element.name];
    for (ORMFormElement *element in [_session.form.elements reverseObjectEnumerator]) [self didChangeValueForKey:element.name];
}

/* The object of the entity whose key is the text: a UUID's by its UUID. */
- (NSManagedObject *)objectOf:(ORMFormElement *)element key:(NSString *)text {
    if (![text length] || !element.entityName) return nil;
    NSEntityDescription *entity = [NSEntityDescription entityForName:element.entityName inManagedObjectContext:_context];
    NSAttributeDescription *key = entity.attributesByName[element.keyName ?: @""];
    if (!key) return nil;
    id value = key.attributeType == NSUUIDAttributeType ? (id)[[NSUUID alloc] initWithUUIDString:text] : text;
    if (!value) return nil;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:element.entityName];
    request.predicate = [NSPredicate predicateWithFormat:@"%K == %@", element.keyName, value];
    request.fetchLimit = 1;
    return [[_context executeFetchRequest:request error:NULL] firstObject];
}

- (NSString *)keyOf:(id)object element:(ORMFormElement *)element {
    id key = [object valueForKey:element.keyName];
    if ([key isKindOfClass:[NSUUID class]]) return [key UUIDString];
    return [key description] ?: @"";
}

- (id)valueForKey:(NSString *)name {
    ORMFormElement *element = [_session.form elementNamed:name];
    if (!element) return [super valueForKey:name];
    NSString *text = [_session valueForElement:name];
    if ([element.kind isEqualToString:@"reference"]) return [self objectOf:element key:text];
    if (![text length]) return nil;
    if ([element.schemaType hasSuffix:@"dateTime"]) return [LBFormDates() dateFromString:text];
    if ([element.schemaType hasSuffix:@"decimal"]) {
        NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:text locale:LBFormPOSIX()];
        return [number isEqual:[NSDecimalNumber notANumber]] ? nil : number;
    }
    if ([element.schemaType hasSuffix:@"boolean"]) return @([text isEqualToString:@"true"]);
    return text;
}

- (void)setValue:(id)value forKey:(NSString *)name {
    ORMFormElement *element = [_session.form elementNamed:name];
    if (!element) {
        [super setValue:value forKey:name];
        return;
    }
    NSString *text = @"";
    if ([element.kind isEqualToString:@"reference"]) {
        text = value ? [self keyOf:value element:element] : @"";
    } else if ([value isKindOfClass:[NSDate class]]) {
        text = [LBFormDates() stringFromDate:value];
    } else if ([value isKindOfClass:[NSDecimalNumber class]]) {
        text = [value descriptionWithLocale:LBFormPOSIX()];
    } else if ([element.schemaType hasSuffix:@"boolean"]) {
        text = [value boolValue] ? @"true" : @"false";
    } else if (value) {
        text = [value description];
    }
    [self willChangeValueForKey:name];
    [_session setValue:text forElement:name];
    [self didChangeValueForKey:name];
    if (_changedHandler) _changedHandler(name);
}

- (NSArray<NSManagedObject *> *)choicesNamed:(NSString *)name error:(NSError **)error {
    ORMFormElement *element = [_session.form elementNamed:name];
    NSArray<NSString *> *keys = [_session choicesNamed:name error:error];
    if (!keys) return nil;
    NSMutableArray *objects = [NSMutableArray array];
    for (NSString *key in keys) {
        NSManagedObject *object = [self objectOf:element key:key];
        if (object) [objects addObject:object];
    }
    return objects;
}

@end
