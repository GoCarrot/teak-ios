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
- (id)init {
  self = [super init];
  if (self) {
#define IS_FEATURE_ENABLED(_feature) ([[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] == nil) ? YES : [[[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] boolValue]
    self.enableIDFA = IS_FEATURE_ENABLED(kTeakEnableIDFA);
    self.enableFacebookAccessToken = IS_FEATURE_ENABLED(kTeakEnableFacebook);
    self.enablePushKey = IS_FEATURE_ENABLED(kTeakEnablePushKey);
#undef IS_FEATURE_ENABLED

    // Check to see if IDFA has been disabled by the OS
    ASIdentifierManager* asIdentifierManager = [ASIdentifierManager sharedManager];
    if (asIdentifierManager != nil) self.enableIDFA &= [asIdentifierManager isAdvertisingTrackingEnabled];
  }
  return self;
}

- (NSDictionary*)to_h {
  return @{
    @"enableIDFA" : [NSNumber numberWithBool:self.enableIDFA],
    @"enableFacebookAccessToken" : [NSNumber numberWithBool:self.enableFacebookAccessToken],
    @"enablePushKey" : [NSNumber numberWithBool:self.enablePushKey],
  };
}

- (void)addConfigurationFromDeveloper:(NSArray*)optOutList {
  if (optOutList != nil) {
    self.enableIDFA &= ![optOutList containsObject:TeakOptOutIdfa];
    self.enableFacebookAccessToken &= ![optOutList containsObject:TeakOptOutFacebook];
    self.enablePushKey &= ![optOutList containsObject:TeakOptOutPushKey];
  }
}
@end
