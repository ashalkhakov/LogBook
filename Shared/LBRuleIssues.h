#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

// The rules an object breaks as it is now, by the keys they name: Core
// Data's (a required value, a length), and the model's (ORMRuntime's
// validator "Logbook"; a rule query names the properties it reads). What
// a form shows at its fields as they are filled in (LBFieldIssues on the
// desktop, LBRecordForm on the phone), as XFormsKit shows a constraint.
@interface LBRuleIssues : NSObject
// Each key's sentences, in the order said.
+ (NSDictionary<NSString *, NSArray<NSString *> *> *)issuesOf:(NSManagedObject *)object;
// Whether the property must have a value: Core Data's, or the model's (a
// to-one ORMKit marks mandatory, which the sync lets be nil a while).
+ (BOOL)isMandatory:(nullable NSPropertyDescription *)property;
// Whether the field shown for the key says " *": mandatory, or named by a
// broken rule while it has no value.
+ (BOOL)isRequired:(NSString *)key of:(NSManagedObject *)object issues:(NSDictionary<NSString *, NSArray<NSString *> *> *)issues;
@end

NS_ASSUME_NONNULL_END
