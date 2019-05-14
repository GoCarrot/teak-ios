#import <Foundation/Foundation.h>

@class TeakRequest;
@class TeakSession;

typedef void (^TeakRequestResponse)(NSDictionary* _Nonnull reply);

@interface TeakBatchConfiguration : NSObject
@property (nonatomic) float time;
@property (nonatomic) long count;
@property (nonatomic) float maximumWaitTime;
@end

@interface TeakRetryConfiguration : NSObject
@property (nonatomic) float jitter;
@property (strong, nonatomic) NSArray* _Nonnull times;
@property (nonatomic) NSUInteger retryIndex;
@end

@interface TeakRequest : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull endpoint;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull payload;
@property (copy, nonatomic, readonly) TeakRequestResponse _Nullable callback;

@property (strong, nonatomic, readonly) TeakBatchConfiguration* _Nonnull batch;
@property (strong, nonatomic, readonly) TeakRetryConfiguration* _Nonnull retry;
@property (nonatomic, readonly) BOOL blackhole;

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback;
+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback;
- (nullable TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload;

- (void)send;
- (NSDictionary* _Nonnull)to_h;
@end
