#import "LBTasks.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>
#import <ODataSync/ODataSignIn.h>

NSNotificationName const LBTasksDidChangeNotification = @"LBTasksDidChange";

static NSString * const LBModelFormPrefix = @"ormkit:form:";

static NSError *LBTasksError(NSString *message) {
    return [NSError errorWithDomain:@"LBTasks" code:1 userInfo:@{ NSLocalizedDescriptionKey : message }];
}

@interface LBTask ()
@property (nonatomic, readwrite, copy) NSString *taskId;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *formKey;
@property (nonatomic, readwrite, copy) NSString *businessKey;
@property (nonatomic, readwrite, strong) NSDate *createdAt;
@end

@implementation LBTask

- (NSString *)formName {
    return [_formKey hasPrefix:LBModelFormPrefix] ? [_formKey substringFromIndex:LBModelFormPrefix.length] : nil;
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

/* The request sent, signed in where the store is, and its answer awaited. */
- (NSData *)send:(NSMutableURLRequest *)request status:(NSInteger *)status error:(NSError **)error {
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    __block NSData *data = nil;
    __block NSHTTPURLResponse *response = nil;
    __block NSError *failure = nil;
    __block BOOL done = NO;
    void (^finish)(NSData *, NSURLResponse *, NSError *) = ^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d;
        response = (NSHTTPURLResponse *)r;
        failure = e;
        done = YES;
    };
    if (_signIn) {
        [_signIn send:request done:^(NSData *d, NSHTTPURLResponse *r, NSError *e) { finish(d, r, e); }];
    } else {
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:finish] resume];
    }
    while (!done) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    *status = response.statusCode;
    if (failure || response.statusCode >= 400) {
        NSDictionary *body = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSString *said = [body isKindOfClass:[NSDictionary class]] ? body[@"error"][@"message"] : nil;
        if (error) *error = failure ?: LBTasksError(said ?: [NSString stringWithFormat:@"The server answered %ld.", (long)response.statusCode]);
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
    NSString *path = [NSString stringWithFormat:@"Tasks('%@')/WorkflowKit.SubmitForm", task.taskId];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path relativeToURL:_workflowRoot]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"Instance" : [LBTasks instanceOf:session] } options:0 error:error];
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
