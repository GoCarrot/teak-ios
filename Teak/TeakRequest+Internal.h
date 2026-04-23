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

// Parse an HTTP response body into a reply dictionary. Always returns a
// dictionary — nil/empty/non-JSON/non-object bodies all collapse to @{} so
// downstream code (reply parsers, dictionary literals) never sees nil.
+ (NSDictionary* _Nonnull)parseJSONResponseData:(NSData* _Nullable)data;

// Resolve the user-facing title for a `report_client_error` payload.
// Returns the dict's "title" when present and a string, otherwise
// "Configuration Error". Never nil — the result is used as a key into the
// integration checker's error dictionary.
+ (NSString* _Nonnull)titleForClientError:(NSDictionary* _Nullable)clientError;
@end
