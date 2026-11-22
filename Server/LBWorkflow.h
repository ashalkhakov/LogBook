// Logbook's processes (Model/*.bpmn, built by wf-build into
// Logbook.wfdeployment beside the server) run by WorkflowKit's engine in
// the server, beside the logbook's store, and its API served under the
// server's (http://<host>:<Port>/workflow/: Tasks, ProcessInstances, their
// actions; WorkflowKit's WFODataService.h).
//
// Procure to receipt (Model/ProcureToReceipt.bpmn): each purchase order
// saved as a draft, from Reorder or entered, starts it once it is saved, its variable
// purchaseOrder the order's id, catalog its catalog's. Confirm the order
// is offered to the catalog's managers, Receive the goods to its keepers,
// as the logbook's permissions say who they are (-rolesAuthenticatorOver:). Its people's tasks are done with the
// entries of the model's flow Purchasing (Model/Purchasing.flow: Confirm,
// its ConfirmPurchaseOrder; Receive, its ReceiveGoods), whose screens the
// app shows in its own views: what a form saves is the logbook's, and its instance
// submitted to the task (WorkflowKit.SubmitForm) completes it, its
// elements the process's variables (orderState); its service tasks are
// here:
//
//   orderReceived   fullyReceived, whether nothing of the order is
//                   outstanding
//   closeOrder      the order closed (its Close)
//
// Order to cash (Model/OrderToCash.bpmn) is a sale's, as that is a
// purchase's: each sale order saved as a draft starts it (not a service's
// or a tyre change's sale of its parts, shipped as it is saved), its
// variable saleOrder the order's id, catalog its catalog's; Confirm the
// order the managers', Ship the goods the keepers', done with the flow
// Selling (Model/Selling.flow: Confirm, its ConfirmSaleOrder; Ship, its
// ShipGoods). Its service tasks:
//
//   orderShipped    fullyShipped, whether nothing of the order is
//                   outstanding
//   closeSaleOrder  the order closed (its Close)
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
// Signed in, its API's authenticator: the server's, the user's roles
// added as the logbook's permissions make them -- the claims manager and
// keeper, the catalogs (ids) they manage and keep -- and the task list
// theirs to work (Tasks.Work). The processes offer each task to its
// catalog's (candidate groups manager:<catalog>, keeper:<catalog>).
- (id<HSAuthenticator>)rolesAuthenticatorOver:(id<HSAuthenticator>)authenticator;

// A purchase order saved as a draft, whoever saved it, starts procure to
// receipt once the save is done (a save refused does nothing): its id the
// variable purchaseOrder, and the business key. Its tasks are completed by
// their forms' submissions, not by the facts saved. Posted on the main
// queue each time the engine has done so.
FOUNDATION_EXPORT NSNotificationName const LBWorkflowDidSettleNotification;

@end

NS_ASSUME_NONNULL_END
