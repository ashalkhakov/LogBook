#import "LBFormValues.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>
#import <objc/runtime.h>

static NSISO8601DateFormatter *LBFormDates(void) {
    static NSISO8601DateFormatter *dates;
    if (!dates) dates = [[NSISO8601DateFormatter alloc] init];
    return dates;
}

/* A day (xsd:date): the same day everywhere. */
static NSDateFormatter *LBFormDays(void) {
    static NSDateFormatter *days;
    if (!days) {
        days = [[NSDateFormatter alloc] init];
        days.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        days.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        days.dateFormat = @"yyyy-MM-dd";
    }
    return days;
}

static NSLocale *LBFormPOSIX(void) {
    return [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
}

static void *LBRowsChanged = &LBRowsChanged;

@interface LBFormValues (LBRows)
- (NSManagedObject *)objectOf:(ORMFormElement *)element key:(NSString *)text;
- (NSString *)keyOf:(id)object element:(ORMFormElement *)element;
@end

/* A row of a repeat whose rows each choose of their own (an answer's
   options, of its question's): its object's values, and its own choices
   and lists, as a table's row binds them. */
@interface LBFormRow : NSObject
@end

@implementation LBFormRow {
    __weak LBFormValues *_values;
    ORMForm *_form;
    NSManagedObject *_object;
    NSDictionary *_choices;
}

static void *LBRowChanged = &LBRowChanged;

- (instancetype)initWithValues:(LBFormValues *)values form:(ORMForm *)form object:(NSManagedObject *)object {
    if ((self = [super init])) {
        _values = values;
        _form = form;
        _object = object;
        /* Its object's values changed (read again, or by another view):
           said as its own, and its choices read again. */
        for (ORMFormElement *element in form.elements) {
            if (object.entity.propertiesByName[element.name]) {
                [object addObserver:self forKeyPath:element.name options:NSKeyValueObservingOptionPrior context:LBRowChanged];
            }
        }
    }
    return self;
}

- (void)dealloc {
    for (ORMFormElement *element in _form.elements) {
        if (_object.entity.propertiesByName[element.name]) [_object removeObserver:self forKeyPath:element.name context:LBRowChanged];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != LBRowChanged) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    /* Before, as KVO wants of a path through it (question.questionText);
       then after. Its choices read again only where they are of it (an
       answer's options, of its question). */
    BOOL chosenOf = NO;
    for (NSString *choice in [_form choiceNames]) {
        chosenOf = chosenOf || [[_form elementsChoicesDependOn:choice] containsObject:keyPath];
    }
    if ([change[NSKeyValueChangeNotificationIsPriorKey] boolValue]) {
        [self willChangeValueForKey:keyPath];
        if (chosenOf) [self willChangeValueForKey:@"choices"];
        return;
    }
    if (chosenOf) {
        _choices = nil;
        [self didChangeValueForKey:@"choices"];
    }
    [self didChangeValueForKey:keyPath];
}

/* The same row as another of its object: the form opened again (its
   record read again, as a sync brings it) has rows of their own, and a
   table's row chosen stays chosen. */
- (BOOL)isEqual:(id)other {
    return self == other || ([other isKindOfClass:[LBFormRow class]] && ((LBFormRow *)other)->_object == _object);
}

- (NSUInteger)hash {
    return [_object hash];
}

/* Its values as its form's elements hold them: a reference's key, a set
   of choices' keys. */
- (NSDictionary<NSString *, NSString *> *)texts {
    NSMutableDictionary *texts = [NSMutableDictionary dictionary];
    for (ORMFormElement *element in _form.elements) {
        if (!_object.entity.propertiesByName[element.name]) continue;
        id value = [_object valueForKey:element.name];
        if (element.many) {
            NSMutableArray *keys = [NSMutableArray array];
            for (id each in value) [keys addObject:[_values keyOf:each element:element]];
            texts[element.name] = [[keys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "];
        } else if ([element.kind isEqualToString:@"reference"]) {
            texts[element.name] = value ? [_values keyOf:value element:element] : @"";
        } else {
            texts[element.name] = [value description] ?: @"";
        }
    }
    return texts;
}

- (NSDictionary *)choices {
    if (!_choices) {
        NSMutableDictionary *given = [_values.session.values mutableCopy] ?: [NSMutableDictionary dictionary];
        [given addEntriesFromDictionary:[self texts]];
        NSMutableDictionary *choices = [NSMutableDictionary dictionary];
        for (NSString *name in [_form choiceNames]) {
            NSMutableArray *objects = [NSMutableArray array];
            NSArray *keys = [_form choicesNamed:name values:given inContext:_values.context error:NULL] ?: @[];
            for (NSString *key in keys) {
                NSManagedObject *object = [_values objectOf:[_form elementNamed:name] key:key];
                if (object) [objects addObject:object];
            }
            choices[name] = objects;
        }
        _choices = choices;
    }
    return _choices;
}

- (NSDictionary *)items {
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    for (ORMFormElement *element in _form.elements) {
        if (element.items && ![element.kind isEqualToString:@"reference"]) items[element.name] = element.items;
    }
    return items;
}

- (id)valueForKey:(NSString *)key {
    if ([key isEqualToString:@"choices"]) return [self choices];
    if ([key isEqualToString:@"items"]) return [self items];
    ORMFormElement *element = [_form elementNamed:key];
    id value = [_object valueForKey:key];
    if (element.many) return [value allObjects] ?: @[];
    return value;
}

- (void)setValue:(id)value forKey:(NSString *)key {
    ORMFormElement *element = [_form elementNamed:key];
    /* Said through its object's change (above). */
    [_object setValue:element.many ? [NSSet setWithArray:value ?: @[]] : value forKey:key];
}

@end

@implementation LBFormValues {
    NSDictionary<NSString *, id> *_choices;
    NSDictionary<NSString *, NSArray<NSString *> *> *_items;
    NSMutableDictionary<NSString *, NSArray<LBFormRow *> *> *_rows;
}

static char LBSaveFailureKey;

+ (void)session:(ORMFormSession *)session
     useContext:(NSManagedObjectContext *)context
         saving:(BOOL (^)(NSManagedObjectContext *context, NSError **failure))saving {
    __weak ORMFormSession *weak = session;
    [session useContext:context saving:^BOOL(NSManagedObjectContext *saved, NSError **failure) {
        NSError *refused = nil;
        BOOL ok = saving(saved, &refused);
        if (weak) objc_setAssociatedObject(weak, &LBSaveFailureKey, ok ? nil : refused, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!ok && failure) *failure = refused;
        return ok;
    }];
}

+ (NSError *)saveFailureOf:(ORMFormSession *)session {
    return session ? objc_getAssociatedObject(session, &LBSaveFailureKey) : nil;
}

- (instancetype)initWithSession:(ORMFormSession *)session context:(NSManagedObjectContext *)context {
    if ((self = [super init])) {
        _session = session;
        _context = context;
    }
    return self;
}

- (instancetype)initWithSession:(ORMFormSession *)session object:(NSManagedObject *)object {
    if ((self = [self initWithSession:session context:object.managedObjectContext])) {
        _object = object;
        /* A repeat's rows are the object's (a service's items), as its
           array controller changes them: each change told as the repeat's. */
        for (NSString *name in [session.form repeatNames]) {
            if (object.entity.relationshipsByName[name]) {
                [object addObserver:self forKeyPath:name options:NSKeyValueObservingOptionPrior context:LBRowsChanged];
            }
        }
    }
    return self;
}

- (void)dealloc {
    for (NSString *name in [_session.form repeatNames]) {
        if (_object.entity.relationshipsByName[name]) [_object removeObserver:self forKeyPath:name context:LBRowsChanged];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != LBRowsChanged) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    /* Before, while the rows are as they were (what observes paths through
       them lets go of them), then after. */
    if ([change[NSKeyValueChangeNotificationIsPriorKey] boolValue]) {
        [self willChangeValueForKey:keyPath];
        return;
    }
    [_rows removeObjectForKey:keyPath];
    [self didChangeValueForKey:keyPath];
}

/* A repeat of the form the object has: its rows, the object's. */
- (BOOL)rowsAre:(NSString *)name {
    return _object && [_session.form repeatNamed:name] && _object.entity.relationshipsByName[name];
}

- (NSMutableSet *)mutableSetValueForKey:(NSString *)name {
    return [self rowsAre:name] ? [_object mutableSetValueForKey:name] : [super mutableSetValueForKey:name];
}

- (void)reload {
    for (ORMFormElement *element in _session.form.elements) [self willChangeValueForKey:element.name];
    for (ORMFormElement *element in [_session.form.elements reverseObjectEnumerator]) [self didChangeValueForKey:element.name];
    [self choicesChanged];
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

/* Whether a repeat's rows each choose of their own (a set of choices, or
   a choice of the row's values): rows of their own, not the objects. */
- (BOOL)rowsChooseOfTheirOwn:(NSString *)name {
    ORMForm *rows = [_session.form repeatNamed:name];
    for (ORMFormElement *element in rows.elements) {
        if (element.many) return YES;
    }
    for (NSString *choice in [rows choiceNames]) {
        for (NSString *on in [rows elementsChoicesDependOn:choice]) {
            if ([rows elementNamed:on]) return YES;
        }
    }
    return NO;
}

- (id)valueForKey:(NSString *)name {
    if ([self rowsAre:name] && [self rowsChooseOfTheirOwn:name]) {
        if (!_rows) _rows = [NSMutableDictionary dictionary];
        if (!_rows[name]) {
            NSMutableArray *rows = [NSMutableArray array];
            NSArray *objects = [[[_object valueForKey:name] allObjects]
                sortedArrayUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"id.UUIDString" ascending:YES] ]];
            for (NSManagedObject *each in objects) {
                [rows addObject:[[LBFormRow alloc] initWithValues:self form:[_session.form repeatNamed:name] object:each]];
            }
            _rows[name] = rows;
        }
        return _rows[name];
    }
    if ([self rowsAre:name]) return [_object valueForKey:name];
    ORMFormElement *element = [_session.form elementNamed:name];
    if (!element) return [super valueForKey:name];
    NSString *text = [_session valueForElement:name];
    if ([element.kind isEqualToString:@"reference"]) return [self objectOf:element key:text];
    if (![text length]) return nil;
    if ([element.schemaType hasSuffix:@"dateTime"]) return [LBFormDates() dateFromString:text];
    if ([element.schemaType hasSuffix:@":date"]) return [LBFormDays() dateFromString:text];
    if ([element.schemaType hasSuffix:@"decimal"]) {
        NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:text locale:LBFormPOSIX()];
        return [number isEqual:[NSDecimalNumber notANumber]] ? nil : number;
    }
    if ([element.schemaType hasSuffix:@"boolean"]) return @([text isEqualToString:@"true"]);
    return text;
}

- (void)setValue:(id)value forKey:(NSString *)name {
    if ([self rowsAre:name]) {
        [_object setValue:value forKey:name];
        return;
    }
    ORMFormElement *element = [_session.form elementNamed:name];
    if (!element) {
        [super setValue:value forKey:name];
        return;
    }
    NSString *text = @"";
    if ([element.kind isEqualToString:@"reference"]) {
        text = value ? [self keyOf:value element:element] : @"";
    } else if ([value isKindOfClass:[NSDate class]] && [element.schemaType hasSuffix:@":date"]) {
        text = [LBFormDays() stringFromDate:value];
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
    if (_object && _object.entity.propertiesByName[name]) [_object setValue:value forKey:name];
    [self didChangeValueForKey:name];
    for (NSString *choice in [_session.form choiceNames]) {
        if ([[_session.form elementsChoicesDependOn:choice] containsObject:name]) {
            [self choicesChanged];
            break;
        }
    }
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

#pragma mark Refusals at their controls

/* The problem labels under the view: the elements each is for. */
static void LBProblemLabels(NSView *view, NSMutableDictionary<NSArray<NSString *> *, NSTextField *> *found) {
    for (NSView *subview in view.subviews) {
        if ([subview.identifier hasPrefix:@"problem-"] && [subview isKindOfClass:[NSTextField class]]) {
            found[[[subview.identifier substringFromIndex:[@"problem-" length]] componentsSeparatedByString:@"-"]] = (NSTextField *)subview;
        }
        LBProblemLabels(subview, found);
    }
}

- (NSArray<NSString *> *)showErrors:(NSDictionary<NSString *, NSString *> *)errors under:(NSView *)view {
    NSMutableDictionary *labels = [NSMutableDictionary dictionary];
    LBProblemLabels(view, labels);
    NSMutableDictionary *left = [errors mutableCopy];
    [labels enumerateKeysAndObjectsUsingBlock:^(NSArray<NSString *> *elements, NSTextField *label, BOOL *stop) {
        NSMutableArray *said = [NSMutableArray array];
        for (NSString *element in elements) {
            if (errors[element]) [said addObject:errors[element]];
            [left removeObjectForKey:element];
        }
        label.stringValue = [said componentsJoinedByString:@" "];
    }];
    NSMutableArray *rest = [NSMutableArray array];
    for (NSString *element in left) {
        ORMFormElement *known = element.length ? [_session.form elementNamed:element] : nil;
        [rest addObject:known ? [NSString stringWithFormat:@"%@: %@", known.label, left[element]] : left[element]];
    }
    return rest;
}

+ (NSString *)problemAt:(NSString *)element under:(NSView *)view {
    NSMutableDictionary *labels = [NSMutableDictionary dictionary];
    LBProblemLabels(view, labels);
    for (NSArray<NSString *> *elements in labels) {
        if ([elements containsObject:element]) return ((NSTextField *)labels[elements]).stringValue ?: @"";
    }
    return @"";
}

+ (void)clearProblemAt:(NSString *)element under:(NSView *)view {
    NSMutableDictionary *labels = [NSMutableDictionary dictionary];
    LBProblemLabels(view, labels);
    for (NSArray<NSString *> *elements in labels) {
        if ([elements containsObject:element]) ((NSTextField *)labels[elements]).stringValue = @"";
    }
}

/* Kept, so that what observes a choice's objects (a pop-up's content,
   choices.driver) sees the same dictionary until they are read again: as
   the values change (one choice's objects depend on another's value), and
   as they are read again. */
- (NSDictionary<NSString *, id> *)choices {
    if (!_choices) {
        NSMutableDictionary *choices = [NSMutableDictionary dictionary];
        for (NSString *name in [_session.form choiceNames]) {
            NSArray *theirs = [self choicesNamed:name error:NULL] ?: @[];
            choices[name] = _arrangesChoices ? _arrangesChoices(name, theirs) : theirs;
        }
        /* A repeat's, by its name: its rows' choices, of the form's values
           (an order's lines' items, of its catalog). */
        for (NSString *repeat in [_session.form repeatNames]) {
            ORMForm *rows = [_session.form repeatNamed:repeat];
            NSMutableDictionary *theirs = [NSMutableDictionary dictionary];
            for (NSString *name in [rows choiceNames]) {
                NSMutableArray *objects = [NSMutableArray array];
                for (NSString *key in [_session choicesNamed:name inRepeat:repeat row:NSNotFound error:NULL] ?: @[]) {
                    NSManagedObject *object = [self objectOf:[rows elementNamed:name] key:key];
                    if (object) [objects addObject:object];
                }
                theirs[name] = objects;
            }
            if (theirs.count) choices[repeat] = theirs;
        }
        _choices = choices;
    }
    return _choices;
}

/* The form's, kept: the same dictionary to whatever observes a list. */
- (NSDictionary<NSString *, NSArray<NSString *> *> *)items {
    if (!_items) {
        NSMutableDictionary *items = [NSMutableDictionary dictionary];
        for (ORMFormElement *element in _session.form.elements) {
            if (element.items && ![element.kind isEqualToString:@"reference"]) items[element.name] = element.items;
        }
        _items = items;
    }
    return _items;
}

- (void)choicesChanged {
    [self willChangeValueForKey:@"choices"];
    _choices = nil;
    [self didChangeValueForKey:@"choices"];
}

@end
