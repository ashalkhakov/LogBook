// A form's values (ORMKit's ORMFormSession, the form's contract run) as a
// XIB's controls bind to them: each element by its name, as the control
// wants it. A date (xsd:dateTime) as an NSDate, a number (xsd:decimal) as
// an NSDecimalNumber, a flag (xsd:boolean) as an NSNumber, a reference as
// the object of the context it is the key of (a User, a DistanceUnit), the
// rest as text. Set through a binding, it is written back as the form's
// table has it, and into the object the form edits where there is one (a
// record's tab: the record kept as it is typed, as the list shows it);
// read again (-reload), every binding hears of it. A reference's choices
// are choices.<name> ("choices.driver"), objects of the context.
//
//   <binding destination="-2" name="value" keyPath="values.timestamp"/>
//   <binding destination="-2" name="selectedObject" keyPath="values.driver"/>

#import <AppKit/AppKit.h>
#import <CoreData/CoreData.h>

@class ORMFormSession;

NS_ASSUME_NONNULL_BEGIN

@interface LBFormValues : NSObject

- (instancetype)initWithSession:(ORMFormSession *)session context:(NSManagedObjectContext *)context;
// The same, each value set written into the object too: its properties the
// form's elements by name.
- (instancetype)initWithSession:(ORMFormSession *)session object:(NSManagedObject *)object;
@property (nonatomic, readonly, strong, nullable) NSManagedObject *object;
@property (nonatomic, readonly, strong) ORMFormSession *session;
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;

// The session's values changed (opened, saved): each element's bindings
// told.
- (void)reload;
// Called with an element's name as a control changes its value.
@property (nonatomic, copy, nullable) void (^changedHandler)(NSString *element);
// A reference's choices, as the session has them, as objects of the
// context, in order.
- (nullable NSArray<NSManagedObject *> *)choicesNamed:(NSString *)name error:(NSError **)error;
// Each reference's choices, by its name, as a pop-up's content binds them.
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSArray<NSManagedObject *> *> *choices;

// What a refused save said, under the controls of the view: in each label
// a XIB names "problem-" and the elements it is for ("problem-driver",
// "problem-mileageQuantity-mileageDistanceUnit"), what is said of them; the
// rest, said of no element there or of the form, returned ("Driver: …"
// by the element's label). An empty errors clears them.
- (NSArray<NSString *> *)showErrors:(NSDictionary<NSString *, NSString *> *)errors under:(NSView *)view;
// What is said under the element's control in the view now; "" for none.
+ (NSString *)problemAt:(NSString *)element under:(NSView *)view;
// What is said of the element there cleared, as its value changed.
+ (void)clearProblemAt:(NSString *)element under:(NSView *)view;

@end

NS_ASSUME_NONNULL_END
