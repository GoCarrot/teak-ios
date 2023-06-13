#import "TeakOperation.h"
#import "TeakRequest.h"
#import "TeakSession.h"

const static NSString* const kEndpoint = @"endpoint";
const static NSString* const kPayload = @"payload";

@implementation TeakOperationResult
- (nonnull NSDictionary*)toDictionary {
  return @{
    @"error" : self.error ? @"true" : @"false",
    @"errors" : ValueOrNSNull(self.errors)
  };
}
@end

@implementation TeakOperationChannelStateResult
- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [NSMutableDictionary dictionaryWithDictionary:[super toDictionary]];
  [ret addEntriesFromDictionary:@{
    @"state" : ValueOrNSNull(self.state),
    @"channel" : ValueOrNSNull(self.channel),
  }];
  return ret;
}
@end

@implementation TeakOperationCategoryStateResult
- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [NSMutableDictionary dictionaryWithDictionary:[super toDictionary]];
  [ret addEntriesFromDictionary:@{
    @"category" : ValueOrNSNull(self.category)
  }];
  return ret;
}
@end

@implementation TeakOperationNotificationResult
- (nonnull NSDictionary*)toDictionary {
  NSMutableDictionary* ret = [NSMutableDictionary dictionaryWithDictionary:[super toDictionary]];
  [ret addEntriesFromDictionary:@{
    @"schedule_ids" : self.scheduleIds
  }];
  return ret;
}
@end

@interface TeakOperation ()
@property (nonatomic, copy, nullable) id (^replyParser)(NSDictionary* _Nonnull);
@end

@implementation TeakOperation

+ (nonnull TeakOperation*)withResult:(nonnull id)result {
  return [[TeakOperation alloc] initWithResult:result];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint {
  return [TeakOperation forEndpoint:endpoint withPayload:@{}];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload {
  return [TeakOperation forEndpoint:endpoint withPayload:@{} replyParser:nil];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint replyParser:(nullable id _Nullable(^)(NSDictionary* _Nonnull))replyParser {
  return [TeakOperation forEndpoint:endpoint withPayload:@{} replyParser:replyParser];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload replyParser:(nullable id _Nullable(^)(NSDictionary* _Nonnull))replyParser {
  return [[TeakOperation alloc] initForEndpoint:endpoint withPayload:payload replyParser:replyParser];
}

- (id)initWithResult:(nonnull id)result {
  self = [self initWithTarget:self selector:@selector(returnResult:) object:result];
  return self;
}

- (id)initForEndpoint:(nonnull NSString*)endpoint withPayload:(nullable NSDictionary*)payload replyParser:(nullable id _Nullable(^)(NSDictionary* _Nonnull))replyParser {

  // TODO: Put any pre-send validation here

  self = [self initWithTarget:self selector:@selector(performRequest:) object:@{kEndpoint : endpoint, kPayload : payload}];
  if (self) {
    self.replyParser = replyParser;
  }
  return self;
}

- (id)returnResult:(id)result {
  return result;
}

- (id)performRequest:(id)requestParams {
  __block id ret = nil;

  NSString* endpoint = requestParams[kEndpoint];
  NSDictionary* payload = requestParams[kPayload];

  __weak typeof(self) weakSelf = self;
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forEndpoint:endpoint
                                               withPayload:payload
                                                    method:TeakRequest_POST
                                                  callback:^(NSDictionary* reply) {
                                                    __strong typeof(self) blockSelf = weakSelf;
                                                    if (blockSelf.replyParser != nil) {
                                                      ret = blockSelf.replyParser(reply);
                                                    } else {
                                                      ret = reply;
                                                    }
                                                    dispatch_semaphore_signal(sema);
                                                  }];
    [request send];
  }];
  dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
  return ret;
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
