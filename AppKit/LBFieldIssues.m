#import "LBFieldIssues.h"
#import "LBFormValues.h"
#import "LBRuleIssues.h"
#import <objc/runtime.h>

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

static char LBLabelWas, LBBadge;

/* A label's text and colour as the window has it. */
static NSArray *LBWasOf(NSTextField *label) {
    NSArray *was = objc_getAssociatedObject(label, &LBLabelWas);
    if (!was) {
        was = @[ label.stringValue ?: @"", label.textColor ?: [NSColor controlTextColor] ];
        objc_setAssociatedObject(label, &LBLabelWas, was, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return was;
}

@implementation LBFieldIssues {
    __weak NSView *_root;
    /* The controllers whose selection is watched. (Each label's text as
       the window has it, and each field's ⚠, are theirs: associated, so
       gone with them; GNUstep's weak-keyed tables keep a freed key's
       entry.) */
    NSMutableArray *_watched;
    NSDictionary *_issues;
    NSArray *_tabs;
    BOOL _scheduled;
}

- (instancetype)initWithView:(NSView *)root {
    if ((self = [super init])) {
        _root = root;
        _watched = [NSMutableArray array];
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
        if (text.isEditable || text.isBezeled || objc_getAssociatedObject(field, &LBBadge) == text) continue;
        if (fabs(NSMidY(text.frame) - NSMidY(frame)) > 8 || NSMaxX(text.frame) > NSMinX(frame) + 4) continue;
        if (!best || NSMaxX(text.frame) > NSMaxX(best.frame)) best = text;
    }
    return best;
}

- (NSView *)badgeOf:(NSView *)field {
    NSTextField *badge = objc_getAssociatedObject(field, &LBBadge);
    return badge.isHidden || !badge.superview ? nil : badge;
}

#pragma mark Checking

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
        NSDictionary *said = [LBRuleIssues issuesOf:field.object];
        [byObject setObject:said forKey:field.object];
        for (NSString *key in said)
            issues[[NSString stringWithFormat:@"%@.%@", field.object.entity.name, key]] = said[key];
    }
    _issues = issues;

    /* The shown fields' labels as they were, their ⚠ hidden; then marked
       again. */
    for (LBIssueField *field in fields) {
        NSView *view = field.view;
        NSTextField *label = view ? [self labelOf:view] : nil;
        if (label) {
            NSArray *was = LBWasOf(label);
            label.stringValue = was[0];
            label.textColor = was[1];
        }
        [(NSView *)objc_getAssociatedObject(view, &LBBadge) setHidden:YES];
    }
    for (LBIssueField *field in fields) {
        NSView *view = field.view;
        if (!view) continue;
        NSDictionary *said = [byObject objectForKey:field.object];
        NSArray *sentences = said[field.key];
        BOOL required = [LBRuleIssues isRequired:field.key of:field.object issues:said];
        NSTextField *label = [self labelOf:view];
        if (label) {
            NSString *text = LBWasOf(label)[0];
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
    NSTextField *badge = objc_getAssociatedObject(field, &LBBadge);
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
        objc_setAssociatedObject(field, &LBBadge, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
