#import "TeakOperation.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import "TeakHelpers.h"
#import "TeakLog.h"

const static NSString* const kEndpoint = @"endpoint";
const static NSString* const kPayload = @"payload";

@interface TeakOperationResult ()
@property (nonatomic, strong, readwrite) NSString* _Nonnull status;
@property (nonatomic, strong, readwrite) NSDictionary* _Nullable errors;
@property (nonatomic) BOOL error;
@end

@implementation TeakOperationResult
- (nonnull TeakOperationResult*)initWithStatus:(nullable NSString*)status andErrors:(nullable NSDictionary*)errors {
  self = [super init];
  if(self) {
    if(!status) {
      status = @"error";
    }
    self.status = status;
    self.error = ![@"ok" isEqualToString:status];
    self.errors = errors;
  }
  return self;
}

- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [[NSMutableDictionary alloc] init];
  ret[@"status"] = self.status;
  ret[@"error"] = TeakStringForBool(self.error);
  ret[@"errors"] = self.errors;
  return ret;
}
@end

@implementation TeakOperationChannelStateResult
- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [NSMutableDictionary dictionaryWithDictionary:[super toDictionary]];
  ret[@"state"] = self.state;
  ret[@"channel"] = self.channel;
  return ret;
}
@end

@implementation TeakOperationCategoryStateResult
- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [NSMutableDictionary dictionaryWithDictionary:[super toDictionary]];
  ret[@"category"] = self.category;
  return ret;
}
@end

@implementation TeakOperationNotificationResult
- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [NSMutableDictionary dictionaryWithDictionary:[super toDictionary]];
  ret[@"schedule_ids"] = self.scheduleIds;
  return ret;
}
@end

@implementation TeakOperationLiveActivityCancelResult
- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [NSMutableDictionary dictionaryWithDictionary:[super toDictionary]];
  ret[@"canceled"] = @(self.canceled);
  return ret;
}
@end

// Logs a raise from an operation's work and returns the error result the operation finishes with.
static TeakOperationResult* TeakOperationResultForException(NSString* _Nullable endpoint, NSException* _Nonnull exception) {
  TeakLog_e(@"operation.error", @{
    @"endpoint" : TeakValueOrNSNull(endpoint),
    @"exception" : TeakValueOrNSNull(exception.description)
  });
  return [[TeakOperationResult alloc] initWithStatus:@"error" andErrors:@{@"exception" : @[ exception.reason ? exception.reason : exception.name ]}];
}

// The invocation's target. NSInvocation retains its target, so the operation can't be its own
// target without retaining itself; this object holds the work and nothing that points back.
@interface TeakOperationWork : NSObject
@property (nonatomic, copy, readonly, nullable) id (^replyParser)(NSDictionary* _Nonnull);
- (instancetype)initWithReplyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull))replyParser;
@end

@implementation TeakOperationWork

- (instancetype)initWithReplyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull))replyParser {
  self = [super init];
  if (self) {
    _replyParser = [replyParser copy];
  }
  return self;
}

- (id)returnResult:(id)result {
  return result;
}

// The invocation's selector for request operations. Request operations never run their invocation:
// -[TeakRequestOperation start] sends the request instead. The invocation only carries the parameters.
- (id)performRequest:(id)requestParams {
  return nil;
}

// Calls completion on another queue with the result the operation finishes with.
- (void)sendRequest:(NSDictionary*)requestParams withSession:(TeakSession*)session completion:(void (^)(id _Nullable))completion {
  NSString* endpoint = requestParams[kEndpoint];
  NSDictionary* payload = requestParams[kPayload];
  id (^replyParser)(NSDictionary* _Nonnull) = self.replyParser;
  @try {
    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forEndpoint:endpoint
                                               withPayload:payload
                                                    method:TeakRequest_POST
                                                  callback:^(NSDictionary* reply) {
                                                    id ret = nil;
                                                    @try {
                                                      ret = replyParser != nil ? replyParser(reply) : reply;
                                                    } @catch (NSException* exception) {
                                                      ret = TeakOperationResultForException(endpoint, exception);
                                                    }
                                                    completion(ret);
                                                  }];
    if (request == nil) {
      // The request already logged why it couldn't be built, and it will never call back.
      completion([[TeakOperationResult alloc] initWithStatus:@"error" andErrors:@{@"request" : @[ @"request could not be created" ]}]);
      return;
    }
    [request send];
  } @catch (NSException* exception) {
    completion(TeakOperationResultForException(endpoint, exception));
  }
}

@end

static TeakOperationResult* TeakOperationCanceledResult(void) {
  return [[TeakOperationResult alloc] initWithStatus:@"error" andErrors:@{@"operation" : @[ @"operation was canceled" ]}];
}

@interface TeakOperation ()
- (id)initWithResult:(nonnull id)result;
@end

// Built by the forEndpoint: factories. Asynchronous: while it waits for an identified user and for
// the reply, it holds no thread. It reports its own executing/finished state.
@interface TeakRequestOperation : TeakOperation {
  BOOL _requestExecuting;
  BOOL _requestFinished;
  BOOL _requestFinishing;
  id _requestResult;
}
- (id)initForEndpoint:(nonnull NSString*)endpoint withPayload:(nullable NSDictionary*)payload replyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull))replyParser;
- (void)finishWithResult:(nullable id)result;
@end

@implementation TeakOperation

+ (nonnull TeakOperation*)withResult:(nonnull id)result {
  return [[TeakOperation alloc] initWithResult:result];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint {
  return [TeakOperation forEndpoint:endpoint withPayload:@{}];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload {
  return [TeakOperation forEndpoint:endpoint withPayload:payload replyParser:nil];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint replyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull))replyParser {
  return [TeakOperation forEndpoint:endpoint withPayload:@{} replyParser:replyParser];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload replyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull))replyParser {
  return [[TeakRequestOperation alloc] initForEndpoint:endpoint withPayload:payload replyParser:replyParser];
}

- (id)initWithResult:(nonnull id)result {
  return [self initWithTarget:[[TeakOperationWork alloc] initWithReplyParser:nil] selector:@selector(returnResult:) object:result];
}

// Read by tests to exercise reply parsing without sending a request.
- (id (^)(NSDictionary* _Nonnull))replyParser {
  return ((TeakOperationWork*)self.invocation.target).replyParser;
}

// NSInvocationOperation raises from -result if the operation was cancelled, and re-raises anything
// the invocation raised. Callers read -result without a @try, so report those as an error result.
- (id)result {
  @try {
    return [super result];
  } @catch (NSException* exception) {
    if (self.isCancelled) {
      return TeakOperationCanceledResult();
    }
    return TeakOperationResultForException(nil, exception);
  }
}

@end

@implementation TeakRequestOperation

- (id)initForEndpoint:(nonnull NSString*)endpoint withPayload:(nullable NSDictionary*)payload replyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull))replyParser {

  // TODO: Put any pre-send validation here

  TeakOperationWork* work = [[TeakOperationWork alloc] initWithReplyParser:replyParser];
  return [self initWithTarget:work selector:@selector(performRequest:) object:@{kEndpoint : endpoint, kPayload : payload}];
}

- (BOOL)isAsynchronous {
  return YES;
}

- (BOOL)isExecuting {
  @synchronized(self) {
    return _requestExecuting;
  }
}

- (BOOL)isFinished {
  @synchronized(self) {
    return _requestFinished;
  }
}

- (void)start {
  @synchronized(self) {
    if (_requestExecuting || _requestFinishing) {
      return;
    }
  }
  if (self.isCancelled) {
    [self finishWithResult:TeakOperationCanceledResult()];
    return;
  }

  [self willChangeValueForKey:@"isExecuting"];
  @synchronized(self) {
    _requestExecuting = YES;
  }
  [self didChangeValueForKey:@"isExecuting"];
  // A cancel that landed before isExecuting went up found nothing to finish.
  if (self.isCancelled) {
    [self finishWithResult:TeakOperationCanceledResult()];
    return;
  }

  // Weak while waiting for a user: a cancelled operation is finished and nothing needs it, so the
  // waiting block mustn't keep it, or its work, alive. Strong once sending, until the reply finishes it.
  __weak TeakRequestOperation* weakSelf = self;
  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequestOperation* op = weakSelf;
    if (op == nil || op.isFinished || op.isCancelled) {
      return;
    }
    TeakOperationWork* work = op.invocation.target;
    [work sendRequest:[op requestParams]
          withSession:session
           completion:^(id _Nullable result) {
             [op finishWithResult:result];
           }];
  }];
}

- (NSDictionary*)requestParams {
  __unsafe_unretained NSDictionary* requestParams = nil;
  [self.invocation getArgument:&requestParams atIndex:2];
  return requestParams;
}

- (void)cancel {
  [super cancel];
  BOOL executing = NO;
  @synchronized(self) {
    executing = _requestExecuting;
  }
  // Not started yet: -start sees the cancel and finishes.
  if (executing) {
    [self finishWithResult:TeakOperationCanceledResult()];
  }
}

// Finishes once; later calls (a reply after a cancel) are ignored. The result is stored before
// isFinished reads YES, so anyone who sees the operation finished can read its result.
- (void)finishWithResult:(id)result {
  @synchronized(self) {
    if (_requestFinishing) {
      return;
    }
    _requestFinishing = YES;
    _requestResult = result;
  }
  [self willChangeValueForKey:@"isExecuting"];
  [self willChangeValueForKey:@"isFinished"];
  @synchronized(self) {
    _requestExecuting = NO;
    _requestFinished = YES;
  }
  [self didChangeValueForKey:@"isFinished"];
  [self didChangeValueForKey:@"isExecuting"];
}

// The invocation never runs, so NSInvocationOperation has no result; report the one it finished with.
- (id)result {
  @synchronized(self) {
    if (_requestFinishing) {
      return _requestResult;
    }
  }
  return self.isCancelled ? TeakOperationCanceledResult() : nil;
}

@end

/// C interface for TeakOperation

id TeakOperation_getResult(TeakOperation* op) {
  return [op result];
}

void TeakOperation_cancel(TeakOperation* op) {
  [op cancel];
}

BOOL TeakOperation_isFinished(TeakOperation* op) {
  return [op isFinished];
}

BOOL TeakOperation_isCanceled(TeakOperation* op) {
  return [op isCancelled];
}

/// C Interface for TeakOperationResult

BOOL TeakOperationResult_isError(TeakOperationResult* result) {
  return [result error];
}

NSDictionary* TeakOperationResult_getErrors(TeakOperationResult* result) {
  return [result errors];
}

/// C Interface for TeakOperationChannelStateResult

NSString* TeakOperationChannelStateResult_getState(TeakOperationChannelStateResult* result) {
  return [result state];
}

NSString* TeakOperationChannelStateResult_getChannel(TeakOperationChannelStateResult* result) {
  return [result channel];
}
