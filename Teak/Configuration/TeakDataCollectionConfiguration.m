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
@property (strong, nonatomic) ASIdentifierManager* asIdentifierManager;
@property (strong, nonatomic) NSArray* optOutList;
@end

@implementation TeakDataCollectionConfiguration
- (id)init {
  self = [super init];
  if (self) {
    self.asIdentifierManager = [ASIdentifierManager sharedManager];
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

  if (self.optOutList != nil) {
    self.enableIDFA &= ![self.optOutList containsObject:TeakOptOutIdfa];
    self.enableFacebookAccessToken &= ![self.optOutList containsObject:TeakOptOutFacebook];
    self.enablePushKey &= ![self.optOutList containsObject:TeakOptOutPushKey];
  }

  if (self.asIdentifierManager != nil) {
    self.enableIDFA &= [self.asIdentifierManager isAdvertisingTrackingEnabled];
  }
}

- (NSDictionary*)to_h {
  return @{
    @"enableIDFA" : [NSNumber numberWithBool:self.enableIDFA],
    @"enableFacebookAccessToken" : [NSNumber numberWithBool:self.enableFacebookAccessToken],
    @"enablePushKey" : [NSNumber numberWithBool:self.enablePushKey],
  };
}

- (void)addConfigurationFromDeveloper:(NSArray*)optOutList {
  self.optOutList = optOutList;
  [self determineFeatures];
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
