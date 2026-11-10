// A form's values (ORMKit's ORMFormSession, the form's contract run) as a
// XIB's controls bind to them: each element by its name, as the control
// wants it. A date (xsd:dateTime) as an NSDate, a number (xsd:decimal) as
// an NSDecimalNumber, a flag (xsd:boolean) as an NSNumber, a reference as
// the object of the context it is the key of (a User, a DistanceUnit), the
// rest as text. Set through a binding, it is written back as the form's
// table has it; read again (-reload), every binding hears of it.
//
//   <binding destination="-2" name="value" keyPath="values.timestamp"/>
//   <binding destination="-2" name="selectedObject" keyPath="values.driver"/>

#import <CoreData/CoreData.h>

@class ORMFormSession;

NS_ASSUME_NONNULL_BEGIN

@interface LBFormValues : NSObject

- (instancetype)initWithSession:(ORMFormSession *)session context:(NSManagedObjectContext *)context;
@property (nonatomic, readonly, strong) ORMFormSession *session;
@property (nonatomic, readonly, strong) NSManagedObjectContext *context;

// The session's values changed (opened, saved): each element's bindings
// told.
- (void)reload;
// Called with an element's name as a control changes its value.
@property (nonatomic, copy, nullable) void (^changedHandler)(NSString *element);
// A reference's choices, as the session has them, as objects of the
// context, in order.
- (NSArray<NSManagedObject *> *)choicesNamed:(NSString *)name error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
