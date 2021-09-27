#import "TeakDataCollectionConfiguration.h"
#import <Teak/Teak.h>

#import <AdSupport/AdSupport.h>

#define kTeakEnableIDFA @"TeakEnableIDFA"
#define kTeakEnableFacebook @"TeakEnableFacebook"
#define kTeakEnablePushKey @"TeakEnablePushKey"

@interface TeakDataCollectionConfiguration ()
@property (nonatomic, readwrite) BOOL enableIDFA;
@property (nonatomic, readwrite) BOOL enableFacebookAccessToken;
@property (nonatomic, readwrite) BOOL enablePushKey;
@end

@implementation TeakDataCollectionConfiguration

+ (BOOL)adTrackingAuthorized {
  Class atTrackingManagerClass = objc_getClass("ATTrackingManager");
  if (atTrackingManagerClass != nil) {
    return [[atTrackingManagerClass valueForKey:@"trackingAuthorizationStatus"] intValue] == 3;
  }

  return [ASIdentifierManager sharedManager].advertisingTrackingEnabled;
}

- (id)init {
  self = [super init];
  if (self) {
    [TeakEvent addEventHandler:self];

    [self determineFeatures];
  }
  return self;
}

- (void)determineFeatures {
#define IS_FEATURE_ENABLED(_feature) ([[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] == nil) ? YES : [[[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] boolValue]
  self.enableIDFA = IS_FEATURE_ENABLED(kTeakEnableIDFA);
  self.enableFacebookAccessToken = IS_FEATURE_ENABLED(kTeakEnableFacebook);
  self.enablePushKey = IS_FEATURE_ENABLED(kTeakEnablePushKey);
#undef IS_FEATURE_ENABLED

  self.enableIDFA &= [TeakDataCollectionConfiguration adTrackingAuthorized];
}

- (NSDictionary*)to_h {
  return @{
    @"enableIDFA" : [NSNumber numberWithBool:self.enableIDFA],
    @"enableFacebookAccessToken" : [NSNumber numberWithBool:self.enableFacebookAccessToken],
    @"enablePushKey" : [NSNumber numberWithBool:self.enablePushKey],
  };
}

- (void)addConfigurationFromDeveloper:(TeakUserConfiguration*)userConfiguration {
  [self determineFeatures];

  self.enableIDFA &= !userConfiguration.optOutIdfa;
  self.enableFacebookAccessToken &= !userConfiguration.optOutFacebook;
  self.enablePushKey &= !userConfiguration.optOutPushKey;
}

- (void)dealloc {
  [TeakEvent removeEventHandler:self];
}

- (void)handleEvent:(TeakEvent* _Nonnull)event {
  switch (event.type) {
    case LifecycleActivate: {
      [self determineFeatures];
    } break;
    default:
      break;
  }
}

@end
