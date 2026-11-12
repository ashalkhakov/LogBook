// The server's processes' tasks (Server/LBWorkflow.h): its workflow API,
// beside the logbook's service (http://<host>/workflow/ for
// http://<host>/odata/), asked as the store asks the logbook, signed in
// where it is. A task is a person's step of a process -- Confirm the order,
// Receive the goods -- done with one of the model's forms (its form key,
// "ormkit:form:ReceiveGoods"), about the object its process is of (its
// business key: a purchase order's id).

#import <Foundation/Foundation.h>

@class ODataSignIn;

NS_ASSUME_NONNULL_BEGIN

@interface LBTask : NSObject
@property (nonatomic, readonly, copy) NSString *taskId;
@property (nonatomic, readonly, copy) NSString *name;
// "ormkit:form:ConfirmPurchaseOrder"; nil where it has none.
@property (nonatomic, readonly, copy, nullable) NSString *formKey;
// The form's name, of its key ("ConfirmPurchaseOrder"); nil for another key.
@property (nonatomic, readonly, copy, nullable) NSString *formName;
// What its process is of: a purchase order's id.
@property (nonatomic, readonly, copy, nullable) NSString *businessKey;
@property (nonatomic, readonly, strong, nullable) NSDate *createdAt;
@end

// Posted (object: the tasks) once a step of a task's may have been done.
FOUNDATION_EXPORT NSNotificationName const LBTasksDidChangeNotification;

@interface LBTasks : NSObject

// For the logbook's service at the root, signed in as it is.
- (instancetype)initWithServiceRoot:(NSURL *)serviceRoot signIn:(nullable ODataSignIn *)signIn;
@property (nonatomic, readonly, copy) NSURL *workflowRoot;

// The open tasks, the oldest first; nil, and why. Each call waits for the
// answer, the run loop turning meanwhile.
- (nullable NSArray<LBTask *> *)openTasks:(NSError **)error;
// A step of a task's was done: its task completed by the server, as the
// facts it is about change (Server/LBWorkflow.h), so the tasks are asked
// again (LBTasksDidChangeNotification).
- (void)noteChange;

@end

NS_ASSUME_NONNULL_END
