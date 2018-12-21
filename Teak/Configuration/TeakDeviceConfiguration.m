#import "TeakDeviceConfiguration.h"
#import "PushRegistrationEvent.h"
#import "Teak+Internal.h"
#import <Teak/Teak.h>
#import <sys/utsname.h>

#import <AdSupport/AdSupport.h>

#define kDeviceIdKey @"TeakDeviceId"

NSString* const TeakDeviceConfiguration_NotificationDisplayState_Enabled = @"true";
NSString* const TeakDeviceConfiguration_NotificationDisplayState_Disabled = @"false";
NSString* const TeakDeviceConfiguration_NotificationDisplayState_NotDetermined = @"not_determined";

@interface TeakDeviceConfiguration ()
@property (strong, nonatomic, readwrite) NSString* deviceId;
@property (strong, nonatomic, readwrite) NSString* deviceModel;
@property (strong, nonatomic, readwrite) NSString* pushToken;
@property (strong, nonatomic, readwrite) NSString* platformString;
@property (strong, nonatomic, readwrite) NSString* advertisingIdentifier;
@property (strong, nonatomic, readwrite) NSString* notificationDisplayEnabled;
@property (nonatomic, readwrite) BOOL limitAdTracking;

@property (strong, nonatomic) NSUserDefaults* userDefaults;
@end

@implementation TeakDeviceConfiguration
- (id)init {
  self = [super init];
  if (self) {
    // Load settings
    teak_try {
      self.userDefaults = [NSUserDefaults standardUserDefaults];
    }
    teak_catch_report;

    if (self.userDefaults == nil) {
      return nil;
    }

    // Get/create device id
    self.deviceId = [self.userDefaults objectForKey:kDeviceIdKey];
    if (self.deviceId == nil) {
      self.deviceId = [[NSUUID UUID] UUIDString];

      @try {
        [self.userDefaults setObject:self.deviceId forKey:kDeviceIdKey];
      } @catch (NSException* exception) {
        TeakLog_e(@"device_configuration", @"Error occurred while assigning userDefaults.", @{@"error" : exception.reason});
        return nil;
      }
    }

    // Get device/app information
    struct utsname systemInfo;
    uname(&systemInfo);

    self.deviceModel = @"unknown";
    teak_try {
      self.deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    }
    teak_catch_report;

    self.platformString = @"ios_0.0";
    teak_try {
      self.platformString = [NSString stringWithFormat:@"ios_%@", [[UIDevice currentDevice] systemVersion]];
    }
    teak_catch_report;

    // Make sure these are not nil
    self.advertisingIdentifier = @"";
    self.pushToken = @"";

    [TeakEvent addEventHandler:self];

    // Get advertising information
    [self getAdvertisingInformation];

    // Default notification display state
    self.notificationDisplayEnabled = TeakDeviceConfiguration_NotificationDisplayState_NotDetermined;

    // Run this for the first time
    [self updateValuesThatCouldHaveChanged];
  }
  return self;
}

- (void)getAdvertisingInformation {
  ASIdentifierManager* asIdentifierManager = [ASIdentifierManager sharedManager];
  NSString* advertisingIdentifier = asIdentifierManager ? [asIdentifierManager.advertisingIdentifier UUIDString] : nil;
  if (advertisingIdentifier != nil) {
    BOOL oldLimitAdtracking = self.limitAdTracking;
    self.limitAdTracking = asIdentifierManager.advertisingTrackingEnabled;
    if (self.limitAdTracking != oldLimitAdtracking || ![self.advertisingIdentifier isEqualToString:advertisingIdentifier]) {
      self.advertisingIdentifier = advertisingIdentifier; // Triggers KVO
    }
  } else {
    __weak typeof(self) weakSelf = self;

    // TODO: Exponential backoff?
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      [weakSelf getAdvertisingInformation];
    });
  }
}

- (void)assignPushToken:(nonnull NSString*)pushToken {
  if ([self.pushToken isEqualToString:pushToken]) return;

  self.pushToken = pushToken;
}

- (void)updateValuesThatCouldHaveChanged {
  [[Teak sharedInstance].pushState determineCurrentPushStateWithCompletionHandler:^(TeakState* pushState) {
    NSString* newNotificationDisplayState = TeakDeviceConfiguration_NotificationDisplayState_NotDetermined;
    if (pushState == [TeakPushState Authorized] || pushState == [TeakPushState Provisional]) {
      newNotificationDisplayState = TeakDeviceConfiguration_NotificationDisplayState_Enabled;
    } else if (pushState == [TeakPushState Denied]) {
      newNotificationDisplayState = TeakDeviceConfiguration_NotificationDisplayState_Disabled;
    }

    // Only asign if different for KVO
    if (![self.notificationDisplayEnabled isEqualToString:newNotificationDisplayState]) {
      self.notificationDisplayEnabled = newNotificationDisplayState;
    }
  }];
}

- (NSDictionary*)to_h {
  return @{
    @"deviceId" : self.deviceId,
    @"deviceModel" : self.deviceModel,
    @"pushToken" : self.pushToken,
    @"platformString" : self.platformString,
    @"advertisingIdentifier" : self.advertisingIdentifier,
    @"limitAdTracking" : [NSNumber numberWithBool:self.limitAdTracking],
    @"notificationDisplayEnabled" : self.notificationDisplayEnabled
  };
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> device-id: %@; device-model: %@; push-token: %@; platform-string: %@; advertising-tracking-enabled: %@; advertising-identifier: %@",
                                    NSStringFromClass([self class]),
                                    self,
                                    self.deviceId,
                                    self.deviceModel,
                                    self.pushToken,
                                    self.platformString,
                                    self.limitAdTracking ? @"YES" : @"NO",
                                    self.advertisingIdentifier];
}

- (void)dealloc {
  [TeakEvent removeEventHandler:self];
}

- (void)handleEvent:(TeakEvent* _Nonnull)event {
  switch (event.type) {
    case PushRegistered: {
      NSString* pushToken = ((PushRegistrationEvent*)event).token;
      // Check before assignment so KVO isn't triggered unless it should be
      if (self.pushToken == nil || ![self.pushToken isEqualToString:pushToken]) {
        self.pushToken = pushToken;
      }
    } break;
    case PushUnRegistered: {
      if (self.pushToken != nil) self.pushToken = nil;
    } break;
    case LifecycleActivate: {
      [self updateValuesThatCouldHaveChanged];
    } break;
    default:
      break;
  }
}

@end
