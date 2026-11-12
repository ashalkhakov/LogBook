#import "LBTasks.h"
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

- (void)noteChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:LBTasksDidChangeNotification object:self];
}

@end
