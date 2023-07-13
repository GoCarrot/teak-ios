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

- (TeakRemoteConfiguration* _Nullable)initForSession:(TeakSession* _Nonnull)session;
- (nonnull NSDictionary*)to_h;
@end
