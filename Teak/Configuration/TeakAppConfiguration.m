#import "TeakAppConfiguration.h"
#import "Teak+Internal.h"

extern BOOL isProductionProvisioningProfile(NSString* profilePath);

BOOL Teak_isProductionBuild() {
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
      self.appVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
    }
    teak_catch_report;

    self.appVersionName = @"unknown";
    teak_try {
      self.appVersionName = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleVersion"];
    }
    teak_catch_report;

#define kTeakLogTrace @"TeakLogTrace"
#define IS_FEATURE_ENABLED(_feature) ([[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] == nil) ? NO : [[[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] boolValue]
    self.traceLog = IS_FEATURE_ENABLED(kTeakLogTrace);
#undef IS_FEATURE_ENABLED
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
    @"traceLog" : self.traceLog ? @YES : @NO
  };
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> app-id: %@; api-key: %@; bundle-id: %@; app-version: %@; is-production: %@; trace-log: %@",
                                    NSStringFromClass([self class]),
                                    self, // @"0x%016llx"
                                    self.appId,
                                    self.apiKey,
                                    self.bundleId,
                                    self.appVersion,
                                    self.isProduction ? @"YES" : @"NO",
                                    self.traceLog ? @"YES" : @"NO"];
}
@end
