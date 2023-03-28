#import "TeakAppConfiguration.h"
#import "Teak+Internal.h"

extern BOOL isProductionProvisioningProfile(NSString* profilePath);

BOOL Teak_isProductionBuild(void) {
  static BOOL isProduction;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    teak_try {
      isProduction = isProductionProvisioningProfile([[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"]);
    }
    teak_catch_report;
  });

  return isProduction;
}

@interface TeakAppConfiguration ()
@property (strong, nonatomic, readwrite) NSString* appId;
@property (strong, nonatomic, readwrite) NSString* apiKey;
@property (strong, nonatomic, readwrite) NSString* bundleId;
@property (strong, nonatomic, readwrite) NSString* appVersion;
@property (strong, nonatomic, readwrite) NSString* _Nonnull appVersionName;
@property (strong, nonatomic, readwrite) NSSet* urlSchemes;
@property (nonatomic, readwrite) BOOL isProduction;
@property (nonatomic, readwrite) BOOL traceLog;
@property (nonatomic, readwrite) BOOL sdk5Behaviors;
@property (nonatomic, readwrite) BOOL doNotRefreshPushToken;
@end

@implementation TeakAppConfiguration
- (id)initWithAppId:(nonnull NSString*)appId apiKey:(nonnull NSString*)apiKey {
  self = [super init];
  if (self) {
    self.appId = appId;
    self.apiKey = apiKey;

    // By default we listen to teakXXXXXX URL schemes
    self.urlSchemes = [NSSet setWithObjects:
                                 [NSString stringWithFormat:@"teak%@", self.appId],
                                 nil];

    @try {
      self.bundleId = [[NSBundle mainBundle] bundleIdentifier];
    } @catch (NSException* exception) {
      [NSException raise:NSObjectNotAvailableException format:@"Failed to get Bundle Id."];
      return nil;
    }

    self.isProduction = Teak_isProductionBuild();

    self.appVersion = @"unknown";
    teak_try {
      NSString* appVersion = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
      if (appVersion != nil) {
        self.appVersion = appVersion;
      }
    }
    teak_catch_report;

    self.appVersionName = @"unknown";
    teak_try {
      NSString* appVersionName = [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"];
      if (appVersionName != nil) {
        self.appVersionName = appVersionName;
      }
    }
    teak_catch_report;

#define kTeakLogTrace @"TeakLogTrace"
#define kTeakSDK5Behaviors @"TeakSDK5Behaviors"
#define kTeakDoNotRefreshPushToken @"TeakDoNotRefreshPushToken"

#define IS_FEATURE_ENABLED_DEFAULT(_feature, _default) ([[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] == nil) ? _default : [[[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] boolValue]
#define IS_FEATURE_ENABLED(_feature) IS_FEATURE_ENABLED_DEFAULT(_feature, NO)
    self.traceLog = IS_FEATURE_ENABLED(kTeakLogTrace);
    self.sdk5Behaviors = IS_FEATURE_ENABLED_DEFAULT(kTeakSDK5Behaviors, YES);
    self.doNotRefreshPushToken = IS_FEATURE_ENABLED(kTeakDoNotRefreshPushToken);
#undef IS_FEATURE_ENABLED
#undef IS_FEATURE_ENABLED_DEFAULT
  }
  return self;
}

- (NSDictionary*)to_h {
  return @{
    @"appId" : self.appId,
    @"apiKey" : self.apiKey,
    @"bundleId" : self.bundleId,
    @"appVersion" : self.appVersion,
    @"isProduction" : self.isProduction ? @YES : @NO,
    @"traceLog" : self.traceLog ? @YES : @NO,
    @"sdk5Behaviors" : self.sdk5Behaviors ? @YES : @NO
  };
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> app-id: %@; api-key: %@; bundle-id: %@; app-version: %@; is-production: %@; trace-log: %@; sdk5-behaviors: %@",
                                    NSStringFromClass([self class]),
                                    self, // @"0x%016llx"
                                    self.appId,
                                    self.apiKey,
                                    self.bundleId,
                                    self.appVersion,
                                    self.isProduction ? @"YES" : @"NO",
                                    self.traceLog ? @"YES" : @"NO",
                                    self.sdk5Behaviors ? @"YES" : @"NO"];
}
@end
