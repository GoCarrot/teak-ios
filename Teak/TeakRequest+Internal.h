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
@property (nonatomic) NSUInteger socketErrorRetryCount;

@property (strong, nonatomic, readwrite) NSString* _Nonnull method;

- (nullable TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload;

// Parse an HTTP response body into a reply dictionary. Always returns a
// dictionary — nil/empty/non-JSON/non-object bodies all collapse to @{} so
// downstream code (reply parsers, dictionary literals) never sees nil.
// On parse/shape failures, `*outError` (when provided) is set to a non-nil
// NSError so callers can surface the failure to logging. On nil/empty data
// or a successful parse, `*outError` is left unchanged.
+ (NSDictionary* _Nonnull)parseJSONResponseData:(NSData* _Nullable)data
                                          error:(NSError* _Nullable* _Nullable)outError;

// Resolve the user-facing title for a `report_client_error` payload.
// Returns the dict's "title" when present and a string, otherwise
// "Configuration Error". Never nil — the result is used as a key into the
// integration checker's error dictionary.
+ (NSString* _Nonnull)titleForClientError:(NSDictionary* _Nullable)clientError;

// Returns YES when `error` is the OS-closed-socket transport failure
// (ECONNABORTED) that occurs when a pooled connection is reused after the
// app returns from background and the OS has torn down the underlying
// socket without reopening it. Checks both the top-level domain/code and,
// for robustness against API surfaces that nest it, NSUnderlyingErrorKey.
+ (BOOL)isRetryableSocketError:(NSError* _Nullable)error;

// Returns YES when `error` is a retryable socket error (see
// isRetryableSocketError:) and `retryCount` hasn't reached the stop policy
// (TeakRequestMaxSocketRetries) yet.
+ (BOOL)shouldRetrySocketError:(NSError* _Nullable)error retryCount:(NSUInteger)retryCount;
@end
