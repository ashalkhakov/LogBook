// The server's processes' tasks (Server/LBWorkflow.h): its workflow API,
// beside the logbook's service (http://<host>/workflow/ for
// http://<host>/odata/), asked as the store asks the logbook, signed in
// where it is. A task is a person's step of a process -- Confirm the order,
// Receive the goods -- done with one of the model's forms or a flow's entry
// (its form key, "ormkit:form:ReceiveGoods", "ormkit:flow:Purchasing.flow#Receive"),
// about the object its process is of (its business key: a purchase order's
// id).

#import <Foundation/Foundation.h>

@class ODataSignIn, ORMFormSession, LBAppState, LBPendingSubmission;

NS_ASSUME_NONNULL_BEGIN

@interface LBTask : NSObject
@property (nonatomic, readonly, copy) NSString *taskId;
@property (nonatomic, readonly, copy) NSString *name;
// "ormkit:flow:Purchasing.flow#Confirm", "ormkit:form:ConfirmPurchaseOrder";
// nil where it has none.
@property (nonatomic, readonly, copy, nullable) NSString *formKey;
// A flow's entry's: the flow's name ("Purchasing", its Purchasing.ormflow)
// and the entry's ("Confirm"); nil for another key.
@property (nonatomic, readonly, copy, nullable) NSString *flowName;
@property (nonatomic, readonly, copy, nullable) NSString *entryName;
// The form it is done with ("ConfirmPurchaseOrder"): its key's, or the
// flow's entry's screen's; nil for another key, or a flow the app has not.
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

// A task done with the form its key names: the form's instance, as the
// session has it (its anchor's element, each element's text, each repeat's
// rows), submitted to it (WorkflowKit.SubmitForm). The server's process
// takes its elements as its variables and goes on; the tasks are asked
// again. NO, and why, where the server refuses it.
- (BOOL)submitForm:(ORMFormSession *)session toTask:(LBTask *)task error:(NSError **)error;
- (BOOL)submitInstance:(NSString *)instance toTask:(LBTask *)task error:(NSError **)error;
+ (NSString *)instanceOf:(ORMFormSession *)session;
// Whether the server could not be reached (no answer, or a 5xx): a step
// waits, rather than being refused.
+ (BOOL)isUnreachable:(nullable NSError *)error;

// A step saved here and waiting (LBAppState's), submitted to its open
// task and forgotten; else why not, said in it. Each waiting, the oldest
// first, till the server cannot be reached: how many went.
- (BOOL)submitWaiting:(LBPendingSubmission *)waiting in:(LBAppState *)state error:(NSError **)error;
// Each not held by another (-hold:).
- (NSUInteger)submitWaitingIn:(LBAppState *)state;
// Held while one submits it (a sync first, Window > Tasks's Submit): no
// other does meanwhile. NO where another holds it.
+ (BOOL)hold:(LBPendingSubmission *)waiting;
+ (void)letGo:(LBPendingSubmission *)waiting;
// The open task done with the form, about the object (a purchase order's
// id); nil where there is none (and nil error), or why it was not read.
- (nullable LBTask *)openTaskOfForm:(NSString *)formName about:(NSString *)businessKey error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
