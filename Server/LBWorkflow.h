// Logbook's processes (Model/*.bpmn, built by wf-build into
// Logbook.wfdeployment beside the server) run by WorkflowKit's engine in
// the server, beside the logbook's store, and its API served under the
// server's (http://<host>:<Port>/workflow/: Tasks, ProcessInstances, their
// actions; WorkflowKit's WFODataService.h).
//
// Procure to receipt (Model/ProcureToReceipt.bpmn): each purchase order
// saved as a draft, from Reorder or entered, starts it once it is saved, its variable
// purchaseOrder the order's id. Its people's tasks are done with the
// model's forms (ConfirmPurchaseOrder, ReceiveGoods), which the app shows
// in its own screens; the order's actions there (Confirm, Cancel, Receive)
// complete the tasks, as they do from anywhere; its service tasks are
// here:
//
//   orderReceived   fullyReceived, whether nothing of the order is
//                   outstanding
//   closeOrder      the order closed (its Close)
//
// Settings: Workflow, the engine's store (a SQLite file; default
// Workflow.sqlite beside the logbook's; Temporary with a temporary
// logbook); Processes, the built deployment (default
// Logbook.wfdeployment beside the server).

#pragma once
#import <ODataService/ODataServer.h>
#import <WorkflowKit/WorkflowKit.h>

@class PurchaseOrder;

NS_ASSUME_NONNULL_BEGIN

@interface LBWorkflow : NSObject

// The engine over its store, opened, the processes deployed, its service
// tasks those above, over the logbook's store; nil, and why.
- (nullable instancetype)initWithConfiguration:(HSConfiguration *)configuration
                                   coordinator:(NSPersistentStoreCoordinator *)coordinator
                                temporaryStore:(BOOL)temporary
                                         error:(NSError **)error;
@property (nonatomic, readonly, strong) WFProcessEngine *engine;
// Its API, under the server's root. With no sign-in set (the logbook tried
// out), everyone is a trial user who may work every task.
- (ODataService *)serviceAtRoot:(NSURL *)root signedIn:(BOOL)signedIn;

// The processes follow the logbook's saves, whoever made them, once each is
// done (a save refused does nothing): a purchase order saved as a draft
// starts procure to receipt (its id the variable purchaseOrder, and the
// business key); one confirmed or cancelled completes its Confirm the
// order (orderState its state); a receipt of one completes its Receive
// the goods. Posted on the main queue each time the engine has done so.
FOUNDATION_EXPORT NSNotificationName const LBWorkflowDidSettleNotification;

@end

NS_ASSUME_NONNULL_END
