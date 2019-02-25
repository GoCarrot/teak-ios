#import "TeakRemoteConfiguration.h"

#import "RemoteConfigurationEvent.h"
#import "Teak+Internal.h"
#import "TeakAppConfiguration.h"
#import "TeakLink.h"
#import "TeakRequest.h"
#import "TeakSession.h"

@interface TeakRemoteConfiguration ()
@property (strong, nonatomic, readwrite) NSString* hostname;
@property (strong, nonatomic, readwrite) NSString* sdkSentryDsn;
@property (strong, nonatomic, readwrite) NSString* appSentryDsn;
@property (strong, nonatomic, readwrite) NSDictionary* endpointConfigurations;
@end

@implementation TeakRemoteConfiguration

- (TeakRemoteConfiguration*)initForSession:(nonnull TeakSession*)session {
  self = [super init];
  if (self) {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      __strong typeof(self) blockSelf = weakSelf;
      [blockSelf configureForSession:session];
    });
  }
  return self;
}

- (void)configureForSession:(nonnull TeakSession*)session {
  NSBlockOperation* configOp = [NSBlockOperation blockOperationWithBlock:^{
    NSDictionary* payload = @{@"id" : session.appConfiguration.appId,
                              @"deep_link_routes" : [TeakLink routeNamesAndDescriptions]};

    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forEndpoint:[NSString stringWithFormat:@"/games/%@/settings.json", session.appConfiguration.appId]
                                               withPayload:payload
                                                  callback:^(NSDictionary* reply) {
                                                    self.hostname = @"gocarrot.com";

                                                    NSString* sdkSentryDsn = reply[@"sdk_sentry_dsn"];
                                                    if (sdkSentryDsn != nil && sdkSentryDsn != (NSString*)[NSNull null]) {
                                                      self.sdkSentryDsn = sdkSentryDsn;
                                                    }

                                                    // Optionally blackhole calls to [UIApplication unregisterForRemoteNotifications]
                                                    teak_try {
                                                      BOOL blackholeUnregisterForRemoteNotifications = [reply[@"blackhole_unregister_for_remote_notifications"] boolValue];
                                                      NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
                                                      [userDefaults setBool:blackholeUnregisterForRemoteNotifications forKey:kBlackholeUnregisterForRemoteNotifications];
                                                    }
                                                    teak_catch_report;

                                                    // Batching/endpoint configuration
                                                    self.endpointConfigurations = reply[@"endpoint_configurations"];

                                                    [RemoteConfigurationEvent remoteConfigurationReady:self];
                                                  }];
    [request send];
  }];

  [configOp addDependency:[Teak sharedInstance].hostAppplicationDidFinishLaunchingWithOptions];
  if ([Teak sharedInstance].waitForDeepLinkOperation != nil) {
    [configOp addDependency:[Teak sharedInstance].waitForDeepLinkOperation];
  }

  [[Teak sharedInstance].operationQueue addOperation:configOp];
}

- (NSDictionary*)to_h {
  return @{
    @"hostname" : self.hostname,
    @"sdkSentryDsn" : self.sdkSentryDsn,
    @"appSentryDsn" : self.appSentryDsn
  };
}

@end
