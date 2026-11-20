#import <Foundation/Foundation.h>

@class TeakRequest;
@class TeakSession;

extern NSString* _Nonnull const TeakRequest_POST;
extern NSString* _Nonnull const TeakRequest_DELETE;

typedef void (^TeakRequestResponse)(NSDictionary* _Nonnull reply);

@interface TeakBatchConfiguration : NSObject
@property (nonatomic) float time;
@property (nonatomic) long count;
@property (nonatomic) float maximumWaitTime;
@end

@interface TeakRetryConfiguration : NSObject
@property (nonatomic) float jitter;
@property (strong, nonatomic) NSArray* _Nonnull times;
@end

@interface TeakRequest : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull endpoint;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull payload;
@property (copy, nonatomic, readonly) TeakRequestResponse _Nullable callback;

@property (strong, nonatomic, readonly) TeakBatchConfiguration* _Nonnull batch;
@property (strong, nonatomic, readonly) TeakRetryConfiguration* _Nonnull retry;
@property (nonatomic, readonly) BOOL blackhole;

@property (strong, nonatomic, readonly) NSString* _Nonnull method;

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback;
+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback;
- (nullable TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload;

// YES if a send was handed to the network, so the callback will run when it is done. NO if nothing
// was sent (the endpoint is blackholed, or building or transmitting the send raised); the callback
// will not run. Subclasses that send later (a batch, the user profile) return YES without
// promising a callback.
- (BOOL)send;
@end
