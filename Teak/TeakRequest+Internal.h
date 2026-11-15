#import "TeakRequest.h"

// Stop policy for isRetryableSocketError: retries — see shouldRetrySocketError:retryCount:.
extern const NSUInteger TeakRequestMaxSocketRetries;

// One logical send of a request, frozen when -send runs. A retry resends this, so it goes out
// with the same request_id and bytes however the request has changed since.
@interface TeakRequestSend : NSObject
@property (strong, nonatomic, readonly) TeakRequest* _Nonnull request;
@property (strong, nonatomic, readonly) NSString* _Nonnull requestId;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull payload;
@property (strong, nonatomic, readonly) NSString* _Nonnull stringToSign;
@property (strong, nonatomic, readonly) NSString* _Nonnull signature;
@property (strong, nonatomic, readonly) NSURLRequest* _Nonnull urlRequest;
@property (strong, nonatomic) NSDate* _Nullable sendDate;
// A retry is scheduled only from the reply to the attempt before it, so attempts never overlap.
@property (nonatomic) NSUInteger socketErrorRetries;
@property (nonatomic) NSUInteger serverErrorRetries;

- (nonnull instancetype)initWithRequest:(nonnull TeakRequest*)request;
- (nonnull NSDictionary*)to_h;
@end

@interface TeakRequest ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull endpoint;
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull payload;
@property (copy, nonatomic, readwrite) TeakRequestResponse _Nullable callback;
@property (strong, nonatomic) NSString* _Nonnull hostname;
@property (strong, nonatomic) TeakSession* _Nonnull session;

@property (strong, nonatomic, readwrite) TeakBatchConfiguration* _Nonnull batch;
@property (strong, nonatomic, readwrite) TeakRetryConfiguration* _Nonnull retry;
@property (nonatomic, readwrite) BOOL blackhole;

@property (strong, nonatomic, readwrite) NSString* _Nonnull method;

// Puts one send on the wire. -send builds a new send and transmits it; a retry transmits
// the same send again without going back through -send, so the gates subclasses put in
// -send (the profile's pending-update check, a batch's no-op) can't swallow it.
- (void)transmitSend:(TeakRequestSend* _Nonnull)send;

// The reply to one transmission of `send`: retries it, or hands the reply to the callback.
- (void)response:(NSHTTPURLResponse* _Nullable)response payload:(NSDictionary* _Nullable)payload withError:(NSError* _Nullable)error forSend:(TeakRequestSend* _Nonnull)send;

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

// A fresh id for one logical send, sent as request_id.
+ (NSString* _Nonnull)generateRequestId;
@end
