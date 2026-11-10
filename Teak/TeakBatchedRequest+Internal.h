#pragma once

#import "TeakRequest.h"

@interface TeakBatchedRequest : TeakRequest
@property (strong, nonatomic) dispatch_block_t scheduledBlock;
@property (strong, nonatomic) NSMutableArray* callbacks;
@property (strong, nonatomic) NSMutableArray* batchContents;
@property (nonatomic) BOOL sent;
@property (strong, nonatomic) NSDate* _Nonnull firstAddTime;

- (void)send;               // No-op
- (void)reallyActuallySend; // Actually send

- (void)sendNow;
- (void)prepareAndSend;
- (BOOL)cancel;

+ (nullable TeakBatchedRequest*)addRequestIntoBatch:(nonnull TeakBatchedRequest*)batchedRequest withSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback;

+ (nullable TeakBatchedRequest*)batchRequestWithSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback;
@end

@interface TeakTrackEventBatchedRequest : TeakBatchedRequest
- (nonnull TeakBatchedRequest*)initWithSession:(nonnull TeakSession*)session;
+ (nonnull TeakTrackEventBatchedRequest*)currentBatchForSession:(nonnull TeakSession*)session;

- (void)prepareAndSend;

+ (nullable TeakBatchedRequest*)batchRequestWithSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback;

+ (BOOL)payload:(nonnull NSDictionary*)a isEqualToPayload:(nullable NSDictionary*)b;
@end
