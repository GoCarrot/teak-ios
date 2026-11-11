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
  return [[TeakOperationResult alloc] initWithStatus:@"error" andErrors:@{@"exception" : @[ TeakValueOrNSNull(exception.reason) ]}];
}

// The invocation's target. NSInvocation retains its target, so the operation can't be its own
// target without retaining itself; this object holds the work and nothing that points back.
@interface TeakOperationWork : NSObject
@property (atomic, copy, nullable) id (^replyParser)(NSDictionary* _Nonnull);
@end

@implementation TeakOperationWork

- (id)returnResult:(id)result {
  return result;
}

- (id)performRequest:(id)requestParams {
  NSString* endpoint = nil;
  @try {
    endpoint = requestParams[kEndpoint];
    return [self sendRequestToEndpoint:endpoint withPayload:requestParams[kPayload]];
  } @catch (NSException* exception) {
    return TeakOperationResultForException(endpoint, exception);
  }
}

- (id)sendRequestToEndpoint:(NSString*)endpoint withPayload:(NSDictionary*)payload {
  __block id ret = nil;

  id (^replyParser)(NSDictionary* _Nonnull) = self.replyParser;
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forEndpoint:endpoint
                                               withPayload:payload
                                                    method:TeakRequest_POST
                                                  callback:^(NSDictionary* reply) {
                                                    // Runs on the request's thread, outside -performRequest:'s @try, and
                                                    // must signal or the operation never finishes.
                                                    @try {
                                                      ret = replyParser != nil ? replyParser(reply) : reply;
                                                    } @catch (NSException* exception) {
                                                      ret = TeakOperationResultForException(endpoint, exception);
                                                    }
                                                    dispatch_semaphore_signal(sema);
                                                  }];
    [request send];
  }];
  dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
  return ret;
}

@end

@interface TeakOperation ()
@property (nonatomic, strong) TeakOperationWork* work;
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
  return [[TeakOperation alloc] initForEndpoint:endpoint withPayload:payload replyParser:replyParser];
}

- (id)initWithResult:(nonnull id)result {
  TeakOperationWork* work = [[TeakOperationWork alloc] init];
  self = [self initWithTarget:work selector:@selector(returnResult:) object:result];
  if (self) {
    _work = work;
  }
  return self;
}

- (id)initForEndpoint:(nonnull NSString*)endpoint withPayload:(nullable NSDictionary*)payload replyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull))replyParser {

  // TODO: Put any pre-send validation here

  TeakOperationWork* work = [[TeakOperationWork alloc] init];
  work.replyParser = replyParser;
  self = [self initWithTarget:work selector:@selector(performRequest:) object:@{kEndpoint : endpoint, kPayload : payload}];
  if (self) {
    _work = work;
  }
  return self;
}

- (id (^)(NSDictionary* _Nonnull))replyParser {
  return self.work.replyParser;
}

- (void)setReplyParser:(id (^)(NSDictionary* _Nonnull))replyParser {
  self.work.replyParser = replyParser;
}

// NSInvocationOperation re-raises from -result anything the invocation raised, and raises if the
// operation was cancelled before it ran. Callers read -result without a @try, so report those as
// an error result instead.
- (id)result {
  @try {
    return [super result];
  } @catch (NSException* exception) {
    return TeakOperationResultForException(nil, exception);
  }
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
