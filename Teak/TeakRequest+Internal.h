#import "TeakRequest.h"

@interface TeakRequest ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull endpoint;
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull payload;
@property (copy, nonatomic, readwrite) TeakRequestResponse _Nullable callback;
@property (strong, nonatomic) NSString* _Nonnull hostname;
@property (strong, nonatomic) NSString* _Nonnull requestId;
@property (strong, nonatomic) TeakSession* _Nonnull session;
@property (strong, nonatomic) NSDate* _Nonnull sendDate;

@property (strong, nonatomic, readwrite) TeakBatchConfiguration* _Nonnull batch;
@property (strong, nonatomic, readwrite) TeakRetryConfiguration* _Nonnull retry;
@property (nonatomic, readwrite) BOOL blackhole;

@property (strong, nonatomic, readwrite) NSString* _Nonnull method;

- (nullable TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload;
@end
