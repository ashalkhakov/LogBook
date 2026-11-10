#import "LBFormHost.h"
#import <ORMRuntime/ORMForm.h>
#import <ORMRuntime/ORMFormSession.h>
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

static NSError *LBFormError(NSString *text) {
    return [NSError errorWithDomain:@"LBFormHost" code:1 userInfo:@{ NSLocalizedDescriptionKey : text }];
}

@implementation LBFormHost {
    NSString *_document;
    ORMFormSession *_session;
    NSArray<NSString *> *_formMessages;
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
        _document = [xml copy];
        _session = [[ORMFormSession alloc] initWithForm:form given:given];
        _formMessages = @[];
    }
    return self;
}

- (ORMForm *)form { return _session.form; }
- (NSDictionary<NSString *, NSString *> *)given { return _session.given; }
- (ORMFormSession *)session { return _session; }
- (NSString *)key { return _session.key; }
- (void)setKey:(NSString *)key { _session.key = key; }

- (void)useContext:(NSManagedObjectContext *)context saving:(BOOL (^)(NSManagedObjectContext *, NSError **))saving {
    [_session useContext:context saving:saving];
}

- (void)useServiceRoot:(NSURL *)root model:(NSManagedObjectModel *)model signIn:(ODataSignIn *)signIn {
    LBFormServiceTransport *transport = [[LBFormServiceTransport alloc] init];
    transport.signIn = signIn;
    [_session useServiceRoot:root model:model transport:transport];
}

- (NSArray<NSString *> *)formMessages { return _formMessages; }
- (NSString *)savedKey { return _session.savedKey; }

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

/* The values as XML: its document element the anchor's entity, an element
   of each, in the form's order. */
- (NSString *)XMLOf:(NSDictionary<NSString *, NSString *> *)values {
    NSXMLElement *root = [NSXMLElement elementWithName:self.form.entityName];
    for (ORMFormElement *element in self.form.elements) {
        [root addChild:[NSXMLElement elementWithName:element.name stringValue:values[element.name] ?: @""]];
    }
    return [root XMLString];
}

- (NSDictionary<NSString *, NSString *> *)valuesOfXML:(NSString *)xml {
    NSXMLDocument *document = xml ? [[NSXMLDocument alloc] initWithXMLString:xml options:0 error:NULL] : nil;
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSXMLNode *child in [[document rootElement] children]) {
        if ([child kind] == NSXMLElementKind) values[[child localName]] = [child stringValue] ?: @"";
    }
    return values;
}

- (XFSubmissionResponse *)read:(NSDictionary *)values error:(NSError **)error {
    if ([values[self.form.keyElement] length] > 0) _session.key = values[self.form.keyElement];
    if (![_session open:error]) return nil;
    return LBFormResponse(200, [self XMLOf:_session.values]);
}

- (XFSubmissionResponse *)choices:(NSString *)name values:(NSDictionary *)values error:(NSError **)error {
    [_session setValues:values];
    NSArray<NSString *> *keys = [_session choicesNamed:name error:error];
    if (!keys) return nil;
    NSXMLElement *choices = [NSXMLElement elementWithName:@"choices"];
    for (NSString *key in keys) {
        NSXMLElement *item = [NSXMLElement elementWithName:@"item"];
        [item addChild:[NSXMLElement elementWithName:@"key" stringValue:key]];
        [choices addChild:item];
    }
    return LBFormResponse(200, [choices XMLString]);
}

- (XFSubmissionResponse *)save:(XFSubmissionRequest *)request error:(NSError **)error {
    [_session setValues:[self valuesOfXML:request.body]];
    _formMessages = @[];
    NSError *failure = nil;
    if (![_session save:&failure]) {
        if (failure) {
            if (error) *error = failure;
            return nil;
        }
        /* Refused: what is said of a field said there, the rest the form's. */
        NSMutableDictionary *atFields = [NSMutableDictionary dictionary];
        NSMutableArray *messages = [NSMutableArray array];
        [_session.errors enumerateKeysAndObjectsUsingBlock:^(NSString *element, NSString *text, BOOL *stop) {
            if ([element length] > 0 && [self.form elementNamed:element]) atFields[element] = text;
            else [messages addObject:text];
        }];
        [messages addObjectsFromArray:[_processor.model setHostErrors:atFields]];
        _formMessages = messages;
        return LBFormResponse(422, @"<refused/>");
    }
    return LBFormResponse(200, [self XMLOf:_session.values]);
}

@end
