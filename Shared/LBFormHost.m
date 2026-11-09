#import "LBFormHost.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMQueryOData.h>
#import <ODataKit/ODataTransport.h>
#import <ODataSync/ODataSignIn.h>

/* Requests to the service as ODataKit's transports take them: through the
   sign-in where there is one (its credentials), else the default. */
@interface LBFormServiceTransport : NSObject <ODataTransport>
@property (nonatomic, strong) ODataSignIn *signIn;
@end

@implementation LBFormServiceTransport

- (void)startExchange:(ODataExchange *)exchange {
    if (!_signIn) {
        [ODataDefaultTransport() startExchange:exchange];
        return;
    }
    [_signIn send:exchange.request done:^(NSData *data, NSHTTPURLResponse *response, NSError *error) {
        exchange.data = data;
        exchange.URLResponse = response;
        exchange.error = error;
        [exchange finish];
    }];
}

@end

/* Until done says so: the main run loop kept turning meanwhile, so that an
   answer finished on it (a sign-in's) arrives. */
static void LBFormWait(BOOL (^done)(void)) {
    while (!done()) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

/* A value of the service's JSON as the instance has it. */
static NSString *LBFormText(id value, NSString *keyName) {
    if ([value isKindOfClass:[NSArray class]]) return LBFormText([value firstObject], keyName);
    if ([value isKindOfClass:[NSDictionary class]]) {
        for (NSString *name in value) {
            if ([name caseInsensitiveCompare:keyName ?: @""] == NSOrderedSame) return LBFormText(value[name], nil);
        }
        return @"";
    }
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSUUID class]]) return [value UUIDString];
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    return @"";
}

static NSError *LBFormError(NSString *text) {
    return [NSError errorWithDomain:@"LBFormHost" code:1 userInfo:@{ NSLocalizedDescriptionKey : text }];
}

@implementation LBFormHost {
    NSString *_document;
    NSManagedObjectContext *_context;
    BOOL (^_saving)(NSManagedObjectContext *, NSError **);
    NSURL *_root;
    NSManagedObjectModel *_model;
    LBFormServiceTransport *_transport;
    /* The object as the service gave it, to change no more of it than was
       changed, and its version (If-Match). */
    NSDictionary<NSString *, NSString *> *_original;
    NSString *_etag;
    NSArray<NSString *> *_formMessages;
    NSString *_savedKey;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithFormNamed:(NSString *)name
                         inBundle:(NSBundle *)bundle
                            given:(NSDictionary<NSString *, NSString *> *)given
                            error:(NSError **)error {
    NSString *path = [bundle pathForResource:name ofType:@"xhtml"];
    NSString *xml = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error] : nil;
    NSString *tablePath = [bundle pathForResource:name ofType:@"ormform"];
    id table = tablePath ? [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:tablePath]
                                                                     options:0 format:NULL error:error] : nil;
    ORMForm *form = table ? [ORMForm formWithPropertyList:table error:error] : nil;
    if (!xml || !form) {
        if (error && (!path || !tablePath)) *error = LBFormError([NSString stringWithFormat:@"There is no form %@.", name]);
        return nil;
    }
    return [self initWithForm:form document:xml given:given];
}

- (instancetype)initWithForm:(ORMForm *)form document:(NSString *)xml given:(NSDictionary<NSString *, NSString *> *)given {
    if ((self = [super init])) {
        _form = form;
        _document = [xml copy];
        _given = [given copy];
        _formMessages = @[];
    }
    return self;
}

- (void)useContext:(NSManagedObjectContext *)context saving:(BOOL (^)(NSManagedObjectContext *, NSError **))saving {
    _context = context;
    _saving = [saving copy];
    _root = nil;
}

- (void)useServiceRoot:(NSURL *)root model:(NSManagedObjectModel *)model signIn:(ODataSignIn *)signIn {
    _root = root;
    _model = model;
    _transport = [[LBFormServiceTransport alloc] init];
    _transport.signIn = signIn;
    _context = nil;
}

- (NSArray<NSString *> *)formMessages { return _formMessages; }
- (NSString *)savedKey { return _savedKey; }

- (XFProcessor *)makeProcessor:(NSError **)error {
    XFSchemeTransport *transport = [[XFSchemeTransport alloc] init];
    __weak LBFormHost *weakSelf = self;
    [transport setHandler:^XFSubmissionResponse *(XFSubmissionRequest *request, NSError **failure) {
        return [weakSelf answer:request error:failure];
    } forScheme:@"form"];
    _processor = [XFProcessor processorWithXMLString:_document baseURL:nil transport:transport error:error];
    return _processor;
}

- (NSDictionary<NSString *, NSString *> *)instance {
    XFXMLElement *root = [[_processor.model defaultInstance] documentElement];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (XFXMLNode *child in root.children) {
        if (child.kind == XFXMLElementKind && child.localName) values[child.localName] = child.stringValue ?: @"";
    }
    return values;
}

#pragma mark What the form asks

/* "form:choices/driver?id=&vehicle=V1" as the name ("choices/driver") and
   the values. */
static NSString *LBFormName(NSString *url, NSDictionary **values) {
    NSString *rest = [url substringFromIndex:[@"form:" length]];
    NSRange question = [rest rangeOfString:@"?"];
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    if (question.location != NSNotFound) {
        for (NSString *pair in [[rest substringFromIndex:NSMaxRange(question)] componentsSeparatedByString:@"&"]) {
            NSRange equals = [pair rangeOfString:@"="];
            if (equals.location == NSNotFound) continue;
            NSString *name = [[pair substringToIndex:equals.location] stringByRemovingPercentEncoding];
            NSString *value = [[[pair substringFromIndex:NSMaxRange(equals)] stringByReplacingOccurrencesOfString:@"+" withString:@" "]
                stringByRemovingPercentEncoding];
            if (name) query[name] = value ?: @"";
        }
        rest = [rest substringToIndex:question.location];
    }
    *values = query;
    return rest;
}

- (XFSubmissionResponse *)answer:(XFSubmissionRequest *)request error:(NSError **)error {
    if (![[request.URLString lowercaseString] hasPrefix:@"form:"]) {
        if (error) *error = LBFormError(@"Not the form's.");
        return nil;
    }
    NSDictionary *values = nil;
    NSString *name = LBFormName(request.URLString, &values);
    if ([name isEqualToString:@"read"]) return [self read:values error:error];
    if ([name hasPrefix:@"choices/"]) return [self choices:[name substringFromIndex:[@"choices/" length]] values:values error:error];
    if ([name isEqualToString:@"save"]) return [self save:request error:error];
    if (error) *error = LBFormError([NSString stringWithFormat:@"The form asks for %@, which Logbook does not answer.", name]);
    return nil;
}

static XFSubmissionResponse *LBFormResponse(NSInteger status, NSString *xml) {
    XFSubmissionResponse *response = [[XFSubmissionResponse alloc] init];
    response.statusCode = status;
    response.body = xml;
    response.mediaType = @"application/xml";
    response.headers = @{ @"Content-Type" : @"application/xml" };
    return response;
}

/* The instance as XML: its document element the anchor's entity, an
   element of each, in the form's order. */
- (NSString *)XMLOf:(NSDictionary<NSString *, NSString *> *)instance {
    NSXMLElement *root = [NSXMLElement elementWithName:_form.entityName];
    for (ORMFormElement *element in _form.elements) {
        [root addChild:[NSXMLElement elementWithName:element.name stringValue:instance[element.name] ?: @""]];
    }
    return [root XMLString];
}

- (NSDictionary<NSString *, NSString *> *)instanceOfXML:(NSString *)xml {
    NSXMLDocument *document = xml ? [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL] : nil;
    NSMutableDictionary *instance = [NSMutableDictionary dictionary];
    for (NSXMLNode *child in [[document rootElement] children]) {
        if ([child kind] == NSXMLElementKind) instance[[child localName]] = [child stringValue] ?: @"";
    }
    return instance;
}

- (XFSubmissionResponse *)read:(NSDictionary *)values error:(NSError **)error {
    NSString *key = [values[_form.keyElement] length] > 0 ? values[_form.keyElement] : _key;
    _original = nil;
    _etag = nil;
    if ([key length] == 0) return LBFormResponse(200, [self XMLOf:[_form instanceGiven:_given]]);
    NSDictionary *instance = _context ? [_form readKey:key inContext:_context error:error] : [self readFromService:key error:error];
    if (!instance) return nil;
    _original = _context ? nil : instance;
    return LBFormResponse(200, [self XMLOf:instance]);
}

/* Every row the request reads from the service, and its objects. */
- (NSArray<NSArray *> *)rowsOf:(ORMQueryOData *)request objects:(NSArray **)objects error:(NSError **)error {
    ORMQueryODataCursor *cursor = [request cursorWithTransport:_transport serviceRoot:_root];
    NSMutableArray *rows = [NSMutableArray array], *read = [NSMutableArray array];
    __block NSError *failure = nil;
    while (!cursor.atEnd && !failure) {
        __block BOOL done = NO;
        [cursor nextPage:100 completion:^(ORMQueryResult *page, NSError *pageError) {
            [rows addObjectsFromArray:page.rows ?: @[]];
            [read addObjectsFromArray:page.objects ?: @[]];
            failure = page ? nil : pageError;
            done = YES;
        }];
        LBFormWait(^BOOL { return done; });
    }
    if (failure) {
        if (error) *error = failure;
        return nil;
    }
    if (objects) *objects = read;
    return rows;
}

- (NSDictionary<NSString *, NSString *> *)readFromService:(NSString *)key error:(NSError **)error {
    ORMQueryOData *request = [_form readRequestForKey:key model:_model error:error];
    NSArray *objects = nil;
    NSArray *rows = request ? [self rowsOf:request objects:&objects error:error] : nil;
    if (!rows) return nil;
    if ([rows count] == 0) {
        if (error) *error = LBFormError([NSString stringWithFormat:@"There is no %@ %@.", _form.entityName, key]);
        return nil;
    }
    id object = [objects firstObject];
    _etag = [object isKindOfClass:[NSDictionary class]] ? object[@"@odata.etag"] : nil;
    return [_form instanceOfRow:[rows firstObject]];
}

- (XFSubmissionResponse *)choices:(NSString *)name values:(NSDictionary *)values error:(NSError **)error {
    NSArray<NSString *> *keys;
    if (_context) {
        keys = [_form choicesNamed:name values:values inContext:_context error:error];
    } else {
        ORMQueryOData *request = [_form choicesRequestNamed:name values:values model:_model error:error];
        NSArray *rows = request ? [self rowsOf:request objects:NULL error:error] : nil;
        NSMutableArray *found = rows ? [NSMutableArray array] : nil;
        for (NSArray *row in rows) {
            NSString *key = LBFormText([row firstObject], [_form elementNamed:name].keyName);
            if ([key length] > 0 && ![found containsObject:key]) [found addObject:key];
        }
        keys = found;
    }
    if (!keys) return nil;
    NSXMLElement *choices = [NSXMLElement elementWithName:@"choices"];
    for (NSString *key in keys) {
        NSXMLElement *item = [NSXMLElement elementWithName:@"item"];
        [item addChild:[NSXMLElement elementWithName:@"key" stringValue:key]];
        [choices addChild:item];
    }
    return LBFormResponse(200, [choices XMLString]);
}

/* Refused: what is said of a field said there, the rest the form's. */
- (XFSubmissionResponse *)refused:(NSDictionary<NSString *, NSString *> *)errors {
    NSMutableDictionary *atFields = [NSMutableDictionary dictionary];
    NSMutableArray *messages = [NSMutableArray array];
    [errors enumerateKeysAndObjectsUsingBlock:^(NSString *element, NSString *text, BOOL *stop) {
        if ([element length] > 0 && [self->_form elementNamed:element]) atFields[element] = text;
        else [messages addObject:text];
    }];
    [messages addObjectsFromArray:[_processor.model setHostErrors:atFields]];
    _formMessages = messages;
    return LBFormResponse(422, @"<refused/>");
}

- (XFSubmissionResponse *)save:(XFSubmissionRequest *)request error:(NSError **)error {
    NSDictionary *instance = [self instanceOfXML:request.body];
    _formMessages = @[];
    _savedKey = nil;
    if (_context) {
        NSDictionary *errors = nil;
        NSError *failure = nil;
        NSManagedObject *saved = [_form save:instance inContext:_context saving:_saving errors:&errors error:&failure];
        if (!saved) {
            /* The context the form's own: what saving it changed before it
               was refused (the rules' preparations) undone too. */
            [_context rollback];
            return [self refused:[errors count] ? errors : @{ @"" : failure.localizedDescription ?: @"Not saved." }];
        }
        _savedKey = LBFormText([saved valueForKey:_form.keyElement], nil);
        return LBFormResponse(200, [self XMLOf:[_form readKey:_savedKey inContext:_context error:NULL] ?: instance]);
    }
    ORMFormRequest *save = [_form saveRequestFor:instance original:_original etag:_etag model:_model error:error];
    if (!save) return nil;
    NSMutableURLRequest *http = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:save.path relativeToURL:_root]];
    http.HTTPMethod = save.method;
    http.HTTPBody = [save bodyData];
    [save.headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [http setValue:value forHTTPHeaderField:name];
    }];
    [http setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [http setValue:@"return=representation" forHTTPHeaderField:@"Prefer"];
    ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:http target:nil action:NULL];
    [_transport startExchange:exchange];
    LBFormWait(^BOOL { return exchange.isFinished; });
    NSInteger status = [(NSHTTPURLResponse *)exchange.URLResponse statusCode];
    if (exchange.error || status == 0) {
        if (error) *error = exchange.error ?: LBFormError(@"The server did not answer.");
        return nil;
    }
    if (status >= 400) {
        NSDictionary *errors = [_form elementErrorsOfResponse:exchange.data ?: [NSData data] model:_model];
        return [self refused:[errors count] ? errors : @{ @"" : [NSString stringWithFormat:@"The server refused it (%ld).", (long)status] }];
    }
    NSString *key = instance[_form.keyElement];
    if ([key length] == 0 && exchange.data) {
        key = LBFormText([NSJSONSerialization JSONObjectWithData:exchange.data options:0 error:NULL], _form.keyElement);
    }
    _savedKey = key;
    NSDictionary *read = [key length] ? [self readFromService:key error:NULL] : nil;
    _original = read;
    return LBFormResponse(200, [self XMLOf:read ?: instance]);
}

@end
