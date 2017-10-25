/* Teak -- Copyright (C) 2016 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "TeakDeviceConfiguration.h"
#import "Teak+Internal.h"
#import "TeakAppConfiguration.h"
#import <sys/utsname.h>

#import <AdSupport/AdSupport.h>

#define kDeviceIdKey @"TeakDeviceId"

@interface TeakDeviceConfiguration ()
@property (strong, nonatomic, readwrite) NSString* deviceId;
@property (strong, nonatomic, readwrite) NSString* deviceModel;
@property (strong, nonatomic, readwrite) NSString* pushToken;
@property (strong, nonatomic, readwrite) NSString* platformString;
@property (strong, nonatomic, readwrite) NSString* advertisingIdentifier;
@property (strong, nonatomic, readwrite) NSNumber* limitAdTracking;

@property (strong, nonatomic) NSUserDefaults* userDefaults;
@end

@implementation TeakDeviceConfiguration
- (id)initWithAppConfiguration:(nonnull TeakAppConfiguration*)appConfiguration {
  self = [super init];
  if (self) {
    // Load settings
    teak_try {
      self.userDefaults = [NSUserDefaults standardUserDefaults];
    }
    teak_catch_report

        if (self.userDefaults == nil) {
      return nil;
    }

    // Get/create device id
    self.deviceId = [self.userDefaults objectForKey:kDeviceIdKey];
    if (self.deviceId == nil) {
      self.deviceId = [[NSUUID UUID] UUIDString];

      @try {
        [self.userDefaults setObject:self.deviceId forKey:kDeviceIdKey];
        [self.userDefaults synchronize];
      } @catch (NSException* exception) {
        TeakLog_e(@"", @"Error occurred while synchronizing userDefaults.", @{@"error" : exception.reason});
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
    teak_catch_report

        self.platformString = @"ios_0.0";
    teak_try {
      self.platformString = [NSString stringWithFormat:@"ios_%f", [[[UIDevice currentDevice] systemVersion] floatValue]];
    }
    teak_catch_report

        // Get advertising information
        [self getAdvertisingInformation];
  }
  return self;
}

- (void)getAdvertisingInformation {
  ASIdentifierManager* asIdentifierManager = [ASIdentifierManager sharedManager];
  NSString* advertisingIdentifier = asIdentifierManager ? [asIdentifierManager.advertisingIdentifier UUIDString] : nil;
  if (advertisingIdentifier != nil) {
    NSNumber* oldLimitAdtracking = self.limitAdTracking;
    self.limitAdTracking = asIdentifierManager.advertisingTrackingEnabled ? @NO : @YES;
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
  if (self.pushToken != nil && [self.pushToken isEqualToString:pushToken]) return;

  self.pushToken = pushToken;
}

- (NSDictionary*)to_h {
  return @{
    @"deviceId" : self.deviceId,
    @"deviceModel" : self.deviceModel,
    @"pushToken" : _(self.pushToken),
    @"platformString" : self.platformString,
    @"advertisingIdentifier" : _(self.advertisingIdentifier),
    @"limitAdTracking" : self.limitAdTracking != nil ? self.limitAdTracking : @NO
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
                                    [self.limitAdTracking boolValue] ? @"YES" : @"NO",
                                    self.advertisingIdentifier];
}
@end
