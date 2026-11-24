#import "LBFieldIssues.h"
#import "LBFormValues.h"
#import <ORMRuntime/ORMValidator.h>

/* A field: the control, the object its controller's selection is (a
   record's, behind its form values), the property it shows. */
@interface LBIssueField : NSObject
@property (nonatomic, weak) NSView *view;
@property (nonatomic, strong) NSManagedObject *object;
@property (nonatomic, copy) NSString *key;
@end

@implementation LBIssueField
@end

static NSColor *LBInvalidColor(void) {
    if ([[NSColor class] respondsToSelector:@selector(systemRedColor)]) return [[NSColor class] performSelector:@selector(systemRedColor)];
    return [NSColor redColor];
}

/* Each sentence an error says, with the keys it names (none: the object's). */
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

@implementation LBFieldIssues {
    __weak NSView *_root;
    /* Each label as the window has it, before it was marked. */
    NSMapTable<NSTextField *, NSArray *> *_labels;
    /* Each field's ⚠. */
    NSMapTable<NSView *, NSTextField *> *_badges;
    /* The controllers whose selection is watched. */
    NSHashTable *_watched;
    NSDictionary *_issues;
    NSArray *_tabs;
    BOOL _scheduled;
}

- (instancetype)initWithView:(NSView *)root {
    if ((self = [super init])) {
        _root = root;
        _labels = [NSMapTable weakToStrongObjectsMapTable];
        _badges = [NSMapTable weakToStrongObjectsMapTable];
        _watched = [NSHashTable weakObjectsHashTable];
        _issues = @{};
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextChanged:)
                                                     name:NSManagedObjectContextObjectsDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowUpdated:)
                                                     name:NSWindowDidUpdateNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (id controller in _watched) [controller removeObserver:self forKeyPath:@"selectedObjects"];
}

/* A tab chosen: other fields shown. */
static void LBChosenTabs(NSView *view, NSMutableArray *into) {
    if ([view isKindOfClass:[NSTabView class]]) {
        NSTabViewItem *chosen = [(NSTabView *)view selectedTabViewItem];
        [into addObject:chosen ? [NSValue valueWithNonretainedObject:chosen] : [NSNull null]];
    }
    for (NSView *each in view.subviews) LBChosenTabs(each, into);
}

- (void)windowUpdated:(NSNotification *)note {
    NSView *root = _root;
    if (!root || note.object != root.window) return;
    NSMutableArray *tabs = [NSMutableArray array];
    LBChosenTabs(root, tabs);
    if ([tabs isEqualToArray:_tabs]) return;
    _tabs = tabs;
    [self setNeedsRefresh];
}

- (void)contextChanged:(NSNotification *)note {
    [self setNeedsRefresh];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self setNeedsRefresh];
}

- (void)setNeedsRefresh {
    /* A context of another thread's (a sync's) says so on its thread. */
    if (![NSThread isMainThread]) {
        __weak LBFieldIssues *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf setNeedsRefresh]; });
        return;
    }
    if (_scheduled) return;
    _scheduled = YES;
    [self performSelector:@selector(refreshSoon) withObject:nil afterDelay:0];
}

- (void)refreshSoon {
    _scheduled = NO;
    [self refresh];
}

- (NSDictionary *)issues {
    return _issues;
}

#pragma mark Fields

/* Every bound field under the view (a tab view's chosen tab's only). */
- (void)collectFieldsIn:(NSView *)view into:(NSMutableArray<LBIssueField *> *)fields {
    if (view.isHidden) return;
    LBIssueField *field = [self fieldOf:view];
    if (field) [fields addObject:field];
    for (NSView *each in view.subviews) [self collectFieldsIn:each into:fields];
}

- (LBIssueField *)fieldOf:(NSView *)view {
    if (![view isKindOfClass:[NSControl class]] && ![view isKindOfClass:[NSTextView class]]) return nil;
    for (NSString *binding in view.exposedBindings) {
        NSDictionary *info = [view infoForBinding:binding];
        NSString *path = info[NSObservedKeyPathKey];
        id controller = info[NSObservedObjectKey];
        if (![path hasPrefix:@"selection."] || ![controller isKindOfClass:[NSObjectController class]]) continue;
        NSString *key = [path componentsSeparatedByString:@"."][1];
        if (![_watched containsObject:controller]) {
            [_watched addObject:controller];
            [controller addObserver:self forKeyPath:@"selectedObjects" options:0 context:NULL];
        }
        NSArray *chosen = [controller selectedObjects];
        id object = chosen.count == 1 ? chosen.firstObject : nil;
        if ([object isKindOfClass:[LBFormValues class]]) object = [(LBFormValues *)object object];
        if (![object isKindOfClass:[NSManagedObject class]] || [(NSManagedObject *)object isDeleted]) continue;
        if (![[(NSManagedObject *)object entity] propertiesByName][key]) continue;
        LBIssueField *field = [[LBIssueField alloc] init];
        field.view = view;
        field.object = object;
        field.key = key;
        return field;
    }
    return nil;
}

/* The label left of the field, on its row: the nearest. */
- (NSTextField *)labelOf:(NSView *)field {
    NSTextField *best = nil;
    NSRect frame = field.frame;
    for (NSView *each in field.superview.subviews) {
        if (each == field || ![each isKindOfClass:[NSTextField class]]) continue;
        NSTextField *text = (NSTextField *)each;
        if (text.isEditable || text.isBezeled || [_badges objectForKey:field] == text) continue;
        if (fabs(NSMidY(text.frame) - NSMidY(frame)) > 8 || NSMaxX(text.frame) > NSMinX(frame) + 4) continue;
        if (!best || NSMaxX(text.frame) > NSMaxX(best.frame)) best = text;
    }
    return best;
}

- (NSView *)badgeOf:(NSView *)field {
    NSTextField *badge = [_badges objectForKey:field];
    return badge.isHidden ? nil : badge;
}

#pragma mark Checking

/* The object's rules it breaks, each with the keys it names. */
- (NSArray<NSError *> *)brokenBy:(NSManagedObject *)object {
    NSMutableArray<NSError *> *found = [NSMutableArray array];
    NSError *error = nil;
    BOOL valid = object.isInserted ? [object validateForInsert:&error] : [object validateForUpdate:&error];
    if (!valid && error) LBIssuesOf(error, found);
    ORMValidator *validator = [ORMValidator validatorNamed:@"Logbook" error:NULL];
    for (NSError *each in [validator violationsOf:object deontic:NO] ?: @[]) LBIssuesOf(each, found);
    return found;
}

/* Whether the property must have a value: Core Data's, or the model's
   (a to-one ORMKit marks mandatory, which Core Data's sync lets be nil). */
static BOOL LBMandatory(NSPropertyDescription *property) {
    return !property.isOptional || [property.userInfo[@"ormkit.mandatory"] isEqual:@"YES"];
}

static BOOL LBEmpty(id value) {
    return value == nil || value == [NSNull null] || ([value isKindOfClass:[NSString class]] && ![value length])
           || ([value isKindOfClass:[NSSet class]] && ![value count]);
}

- (void)refresh {
    NSView *root = _root;
    if (!root) return;
    NSMutableArray<LBIssueField *> *fields = [NSMutableArray array];
    [self collectFieldsIn:root into:fields];
    /* Each object checked once: its sentences by key. */
    NSMapTable *byObject = [NSMapTable strongToStrongObjectsMapTable];
    NSMutableDictionary *issues = [NSMutableDictionary dictionary];
    for (LBIssueField *field in fields) {
        if ([byObject objectForKey:field.object]) continue;
        NSMutableDictionary<NSString *, NSMutableOrderedSet *> *said = [NSMutableDictionary dictionary];
        for (NSError *error in [self brokenBy:field.object]) {
            NSString *sentence = error.localizedDescription;
            for (NSString *key in LBKeysOf(error)) {
                if (!said[key]) said[key] = [NSMutableOrderedSet orderedSet];
                [said[key] addObject:sentence];
            }
        }
        [byObject setObject:said forKey:field.object];
        for (NSString *key in said)
            issues[[NSString stringWithFormat:@"%@.%@", field.object.entity.name, key]] = said[key].array;
    }
    _issues = issues;

    /* Labels as they were, then marked again. */
    for (NSTextField *label in _labels) {
        NSArray *was = [_labels objectForKey:label];
        label.stringValue = was[0];
        label.textColor = was[1];
    }
    for (NSView *field in _badges) [[_badges objectForKey:field] setHidden:YES];
    for (LBIssueField *field in fields) {
        NSView *view = field.view;
        if (!view) continue;
        NSArray *sentences = [[byObject objectForKey:field.object][field.key] array];
        id value = [field.object valueForKey:field.key];
        BOOL required = LBMandatory(field.object.entity.propertiesByName[field.key]) || (sentences.count && LBEmpty(value));
        NSTextField *label = [self labelOf:view];
        if (label) {
            if (![_labels objectForKey:label]) [_labels setObject:@[ label.stringValue ?: @"", label.textColor ?: [NSColor labelColor] ] forKey:label];
            NSString *text = [_labels objectForKey:label][0];
            if (required && ![text containsString:@"*"])
                text = [text hasSuffix:@":"] ? [[text substringToIndex:text.length - 1] stringByAppendingString:@" *:"]
                                             : [text stringByAppendingString:@" *"];
            label.stringValue = text;
            if (sentences.count) label.textColor = LBInvalidColor();
        }
        if (sentences.count) [self showBadgeAt:view saying:[sentences componentsJoinedByString:@"\n"] label:label];
    }
}

/* Its ⚠: beside the field where the row has room, else left of its label. */
- (void)showBadgeAt:(NSView *)field saying:(NSString *)said label:(NSTextField *)label {
    NSTextField *badge = [_badges objectForKey:field];
    if (!badge) {
        badge = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 16, 16)];
        badge.editable = NO;
        badge.selectable = NO;
        badge.bezeled = NO;
        badge.bordered = NO;
        badge.drawsBackground = NO;
        badge.stringValue = @"⚠";
        badge.textColor = LBInvalidColor();
        badge.alignment = NSTextAlignmentCenter;
        [_badges setObject:badge forKey:field];
    }
    NSView *row = field.superview;
    NSRect frame = field.frame;
    CGFloat x = NSMaxX(frame) + 2;
    if (x + 16 > NSWidth(row.bounds)) x = label ? NSMinX(label.frame) - 16 : NSMinX(frame) - 18;
    badge.frame = NSMakeRect(x, NSMidY(frame) - 8, 16, 16);
    /* Kept on its field's row as the window resizes: its field's vertical
       margins, its side's horizontal one. */
    badge.autoresizingMask = (x > NSMaxX(frame) ? NSViewMinXMargin : NSViewMaxXMargin)
                             | (field.autoresizingMask & (NSViewMinYMargin | NSViewMaxYMargin));
    badge.toolTip = said;
    if (badge.superview != row) [row addSubview:badge];
    badge.hidden = NO;
}

@end
