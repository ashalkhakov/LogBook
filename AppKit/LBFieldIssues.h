#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The rules a window's fields break, shown at the fields, as XFormsKit
// shows a control's constraint: each field bound to a controller's
// selection (a vehicle's, or a record's form values) is of a property of
// an object; that object's rules are checked (Core Data's, and the
// model's, ORMRuntime's validator "Logbook") as it is edited. A field's
// label says " *" where it must have a value (its property mandatory, or
// a rule broken that names it while it has none); a field a broken rule
// names has its label red, and a ⚠ beside it, the rules said as its tip.
@interface LBFieldIssues : NSObject
- (instancetype)initWithView:(NSView *)root;
- (instancetype)init NS_UNAVAILABLE;
// Checked again (soon: what changes at once, checked once): the context
// changed, a selection or a tab.
- (void)setNeedsRefresh;
// Checked again now.
- (void)refresh;
// What the last check found, by "Entity.key": the rules' sentences.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSArray<NSString *> *> *issues;
// The label a field is said by (nil: none found), and its ⚠ (nil: none).
- (nullable NSTextField *)labelOf:(NSView *)field;
- (nullable NSView *)badgeOf:(NSView *)field;
@end

NS_ASSUME_NONNULL_END
