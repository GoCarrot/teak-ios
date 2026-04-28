#import <Foundation/Foundation.h>

@class TeakAppConfiguration;
@class TeakSession;

@interface TeakRemoteConfiguration : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull hostname;
@property (strong, nonatomic, readonly) NSString* _Nullable sdkSentryDsn;
@property (strong, nonatomic, readonly) NSString* _Nullable appSentryDsn;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull endpointConfigurations;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull dynamicParameters;
@property (nonatomic, readonly) BOOL enhancedIntegrationChecks;
@property (nonatomic, readonly) int heartbeatInterval;
@property (strong, nonatomic, readonly) NSArray* _Nonnull channelCategories;
@property (nonatomic, readonly) NSTimeInterval claimPollInitialDelay;
@property (nonatomic, readonly) NSTimeInterval claimPollCeiling;

/// Cross-SDK fallback values for the click-time JWT-claim poll cadence.
/// These are the source-of-truth defaults — both this class's
/// ``-initForSession:`` and any callers that don't have a live remote
/// configuration on hand should read from these accessors rather than
/// re-declaring the literal seconds. Server config overrides live on the
/// per-instance ``claimPollInitialDelay`` / ``claimPollCeiling`` properties.
+ (NSTimeInterval)defaultClaimPollInitialDelay;
+ (NSTimeInterval)defaultClaimPollCeiling;

- (TeakRemoteConfiguration* _Nullable)initForSession:(TeakSession* _Nonnull)session;
- (nonnull NSDictionary*)to_h;
@end
