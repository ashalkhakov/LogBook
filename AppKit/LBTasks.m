#import "LBTasks.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>
#import <ORMRuntime/ORMFlowSession.h>
#import <ODataSync/ODataSignIn.h>
#import "LBConflicts.h"

NSNotificationName const LBTasksDidChangeNotification = @"LBTasksDidChange";

static NSString * const LBModelFormPrefix = @"ormkit:form:";
static NSString * const LBModelFlowPrefix = @"ormkit:flow:";

static NSString * const LBTasksErrorDomain = @"LBTasks";

/* Its code the server's status (0: none, the request not answered). */
static NSError *LBTasksError(NSString *message, NSInteger status) {
    return [NSError errorWithDomain:LBTasksErrorDomain code:status userInfo:@{ NSLocalizedDescriptionKey : message }];
}

@interface LBTask ()
@property (nonatomic, readwrite, copy) NSString *taskId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *formKey;
@property (nonatomic, readwrite, copy) NSString *businessKey;
@property (nonatomic, readwrite, strong) NSDate *createdAt;
@end

@implementation LBTask

/* "Purchasing.flow#Confirm": the file and the entry. */
- (NSArray<NSString *> *)flowParts {
    if (![_formKey hasPrefix:LBModelFlowPrefix]) return nil;
    NSArray *parts = [[_formKey substringFromIndex:LBModelFlowPrefix.length] componentsSeparatedByString:@"#"];
    return parts.count == 2 && [parts[0] hasSuffix:@".flow"] && [parts[1] length] ? parts : nil;
}

- (NSString *)flowName {
    return [[self flowParts].firstObject stringByDeletingPathExtension];
}

- (NSString *)entryName {
    return [self flowParts].lastObject;
}

- (NSString *)formName {
    if ([_formKey hasPrefix:LBModelFormPrefix]) return [_formKey substringFromIndex:LBModelFormPrefix.length];
    NSString *flowName = self.flowName;
    if (!flowName) return nil;
    ORMFlowSession *flow = [ORMFlowSession flowNamed:flowName error:NULL];
    return [flow beginAt:self.entryName key:nil error:NULL].formName;
}

@end

@implementation LBTasks {
    ODataSignIn *_signIn;
}

- (instancetype)initWithServiceRoot:(NSURL *)serviceRoot signIn:(ODataSignIn *)signIn {
    if ((self = [super init])) {
        _workflowRoot = [[NSURL URLWithString:@"../workflow/" relativeToURL:serviceRoot] absoluteURL];
        _signIn = signIn;
    }
    return self;
}

/* The request sent, signed in where the store is (the sign-in's access
   token as a bearer: refreshed, and sent again, once the server refuses
   it), and its answer awaited. ODataSignIn's -send: is its own way to the
   identity provider, and signs nothing. */
- (NSData *)send:(NSMutableURLRequest *)request status:(NSInteger *)status error:(NSError **)error {
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    __block NSData *data = nil;
    __block NSHTTPURLResponse *response = nil;
    __block NSError *failure = nil;
    __block BOOL done = NO;
    ODataSignIn *signIn = _signIn.isSignedIn && _signIn.kind == ODataSignInOpenID ? _signIn : nil;
    /* Off the main thread: a refresh asks the identity provider, waited for. */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int attempt = 0; attempt < 2; attempt++) {
            NSString *token = signIn ? [signIn accessTokenForAuthorization:nil refresh:attempt > 0] : nil;
            if (token.length) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
            dispatch_semaphore_t answered = dispatch_semaphore_create(0);
            [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
                data = d;
                response = [r isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)r : nil;
                failure = e;
                dispatch_semaphore_signal(answered);
            }] resume];
            dispatch_semaphore_wait(answered, DISPATCH_TIME_FOREVER);
            if (!signIn || response.statusCode != 401) break;
        }
        done = YES;
    });
    while (!done) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    *status = response.statusCode;
    if (failure || response.statusCode >= 400) {
        NSDictionary *body = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSString *said = [body isKindOfClass:[NSDictionary class]] ? body[@"error"][@"message"] : nil;
        if (error) *error = failure ?: LBTasksError(said ?: [NSString stringWithFormat:@"The server answered %ld.", (long)response.statusCode],
                                                    response.statusCode);
        return nil;
    }
    return data ?: [NSData data];
}

- (NSArray<LBTask *> *)openTasks:(NSError **)error {
    NSURL *url = [NSURL URLWithString:@"Tasks?$expand=Form($select=FormKey),ProcessInstance($select=BusinessKey)&$orderby=CreatedAt"
                        relativeToURL:_workflowRoot];
    NSInteger status = 0;
    NSData *data = [self send:[NSMutableURLRequest requestWithURL:url] status:&status error:error];
    NSDictionary *body = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
    if (![body isKindOfClass:[NSDictionary class]]) return nil;
    NSISO8601DateFormatter *dates = [[NSISO8601DateFormatter alloc] init];
    dates.formatOptions |= NSISO8601DateFormatWithFractionalSeconds;
    NSMutableArray *tasks = [NSMutableArray array];
    for (NSDictionary *row in body[@"value"]) {
        LBTask *task = [[LBTask alloc] init];
        task.taskId = [row[@"TaskId"] description];
        task.name = [row[@"Name"] description] ?: @"";
        id form = row[@"Form"], instance = row[@"ProcessInstance"];
        task.formKey = [form isKindOfClass:[NSDictionary class]] && [form[@"FormKey"] isKindOfClass:[NSString class]] ? form[@"FormKey"] : nil;
        task.businessKey = [instance isKindOfClass:[NSDictionary class]] && [instance[@"BusinessKey"] isKindOfClass:[NSString class]]
            ? instance[@"BusinessKey"] : nil;
        NSString *created = [row[@"CreatedAt"] isKindOfClass:[NSString class]] ? row[@"CreatedAt"] : nil;
        task.createdAt = created ? ([dates dateFromString:created] ?: [[NSISO8601DateFormatter new] dateFromString:created]) : nil;
        [tasks addObject:task];
    }
    return tasks;
}

/* The text of an element of the instance, escaped. */
static NSString *LBInstanceElement(NSString *name, NSString *inner) {
    return [NSString stringWithFormat:@"<%@>%@</%@>", name, inner, name];
}

static NSString *LBEscaped(NSString *text) {
    NSMutableString *escaped = [text mutableCopy] ?: [NSMutableString string];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

+ (NSString *)instanceOf:(ORMFormSession *)session {
    ORMForm *form = session.form;
    NSMutableString *inner = [NSMutableString string];
    for (ORMFormElement *element in form.elements) {
        [inner appendString:LBInstanceElement(element.name, LBEscaped([[session valueForElement:element.name] description]))];
    }
    for (NSString *name in [form repeatNames]) {
        ORMForm *repeat = [form repeatNamed:name];
        for (NSDictionary *row in [session rowsOfRepeat:name]) {
            NSMutableString *cells = [NSMutableString string];
            for (ORMFormElement *element in repeat.elements) {
                [cells appendString:LBInstanceElement(element.name, LBEscaped([row[element.name] description]))];
            }
            [inner appendString:LBInstanceElement(name, cells)];
        }
    }
    return LBInstanceElement(form.entityName ?: @"instance", inner);
}

- (BOOL)submitForm:(ORMFormSession *)session toTask:(LBTask *)task error:(NSError **)error {
    return [self submitInstance:[LBTasks instanceOf:session] toTask:task error:error];
}

+ (BOOL)isUnreachable:(NSError *)error {
    if ([error.domain isEqualToString:NSURLErrorDomain]) return YES;
    return [error.domain isEqualToString:LBTasksErrorDomain] && (error.code == 0 || error.code >= 500);
}

- (BOOL)submitWaiting:(LBPendingSubmission *)waiting in:(LBAppState *)state error:(NSError **)error {
    NSError *failure = nil;
    LBTask *task = [self openTaskOfForm:waiting.formName about:waiting.businessKey error:&failure];
    if (!task && !failure) {
        failure = LBTasksError(@"Its task is not open at the server: done another way, or not reached yet. Start it again, or wait.", 404);
    }
    if (task && [self submitInstance:waiting.instance toTask:task error:&failure]) {
        [state removeSubmission:waiting];
        return YES;
    }
    [state noteSubmission:waiting failed:failure.localizedDescription ?: @"Not submitted."];
    if (error) *error = failure;
    return NO;
}

/* The steps being submitted, by whoever holds them. */
static NSMutableSet<NSManagedObjectID *> *LBHeld;

+ (BOOL)hold:(LBPendingSubmission *)waiting {
    if (!LBHeld) LBHeld = [NSMutableSet set];
    if (!waiting.managedObjectContext || [LBHeld containsObject:waiting.objectID]) return NO;
    [LBHeld addObject:waiting.objectID];
    return YES;
}

+ (void)letGo:(LBPendingSubmission *)waiting {
    [LBHeld removeObject:waiting.objectID];
}

- (NSUInteger)submitWaitingIn:(LBAppState *)state {
    NSUInteger submitted = 0;
    for (LBPendingSubmission *waiting in [state pendingSubmissions]) {
        if (![LBTasks hold:waiting]) continue;
        NSManagedObjectID *held = waiting.objectID;
        NSError *error = nil;
        BOOL went = [self submitWaiting:waiting in:state error:&error];
        [LBHeld removeObject:held];
        if (went) submitted++;
        else if ([LBTasks isUnreachable:error]) break;
    }
    return submitted;
}

- (BOOL)submitInstance:(NSString *)instance toTask:(LBTask *)task error:(NSError **)error {
    NSString *path = [NSString stringWithFormat:@"Tasks('%@')/WorkflowKit.SubmitForm", task.taskId];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path relativeToURL:_workflowRoot]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"Instance" : instance ?: @"" } options:0 error:error];
    NSInteger status = 0;
    if (!request.HTTPBody || ![self send:request status:&status error:error]) return NO;
    [self noteChange];
    return YES;
}

- (LBTask *)openTaskOfForm:(NSString *)formName about:(NSString *)businessKey error:(NSError **)error {
    NSArray<LBTask *> *open = [self openTasks:error];
    if (!open) return nil;
    for (LBTask *task in open) {
        if ([task.formName isEqualToString:formName] && [task.businessKey isEqualToString:businessKey]) return task;
    }
    if (error) *error = nil;
    return nil;
}

- (void)noteChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:LBTasksDidChangeNotification object:self];
}

@end
