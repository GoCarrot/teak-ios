#import "TeakOperation.h"
#import "TeakSession.h"
#import "TeakRequest.h"

const static NSString* const kEndpoint = @"endpoint";
const static NSString* const kPayload = @"payload";

id parseReplyFor_channel_state(NSDictionary* _Nonnull reply);

@interface TeakOperationChannelStateResult ()
@property (nonatomic, readwrite) BOOL error;
@property (strong, nonatomic, readwrite) NSString* state;
@property (strong, nonatomic, readwrite) NSString* channel;
@property (strong, nonatomic, readwrite) NSDictionary* errors;
@end

@implementation TeakOperationChannelStateResult
@end

@implementation TeakOperation

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint {
  return [TeakOperation forEndpoint:endpoint withPayload:@{}];
}

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload {
  return [[TeakOperation alloc] initForEndpoint:endpoint withPayload:payload];
}

- (id)initForEndpoint:(nonnull NSString*)endpoint withPayload:(nullable NSDictionary*)payload {
  
  // TODO: Put any pre-send validation here
  
  self = [self initWithTarget:self selector:@selector(performRequest:) object:@{ kEndpoint : endpoint, kPayload : payload }];
  return self;
}

- (id)performRequest:(id)requestParams {
  __block id ret = nil;

  NSString* endpoint = requestParams[kEndpoint];
  NSDictionary* payload = requestParams[kPayload];

  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forEndpoint:endpoint
                                               withPayload:payload
                                                    method:TeakRequest_POST
                                                  callback:^(NSDictionary* reply) {
                                                    if ([@"/me/channel_state" isEqualToString:endpoint]) {
                                                      ret = parseReplyFor_channel_state(reply);
                                                    } else {
                                                      // TODO: Do we need to initWithDictionary and copy?
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

id parseReplyFor_channel_state(NSDictionary* _Nonnull reply) {
  TeakOperationChannelStateResult* result = [[TeakOperationChannelStateResult alloc] init];
  result.error = ![@"ok" isEqualToString:reply[@"status"]];
  result.state = reply[@"state"];
  result.channel = reply[@"channel"];
  result.errors = reply[@"errors"];
  return result;
}

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

/// C Interface for TeakOperationChannelStateResult

BOOL TeakOperationChannelStateResult_isError(TeakOperationChannelStateResult* result) {
  return [result error];
}

NSString* TeakOperationChannelStateResult_getState(TeakOperationChannelStateResult* result) {
  return [result state];
}

NSString* TeakOperationChannelStateResult_getChannel(TeakOperationChannelStateResult* result) {
  return [result channel];
}

NSDictionary* TeakOperationChannelStateResult_getErrors(TeakOperationChannelStateResult* result) {
  return [result errors];
}
