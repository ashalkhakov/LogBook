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
// in its own screens, submitting through the order's actions (Confirm,
// Cancel, Receive) and then completing the task; its service tasks are
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

// Each purchase order saved as a draft, by any context over the logbook's
// store, starts procure to receipt once it is saved (its id the variable
// purchaseOrder, and the business key): a save refused starts nothing.

@end

NS_ASSUME_NONNULL_END
