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

#import "Teak+Internal.h"
#import "TeakSession.h"
#import "TeakRequest.h"
#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakDebugConfiguration.h"

#define LOG_TAG "Teak:Session"
#define kSameSessionDeltaSeconds 120

TeakSession* currentSession;
NSString* const currentSessionMutex = @"TeakCurrentSessionMutex";

@interface TeakSession ()
@property (strong, nonatomic) TeakState* currentState;
@property (strong, nonatomic) TeakState* previousState;
@property (strong, nonatomic) NSDate* startDate;
@property (strong, nonatomic) NSDate* endDate;
@property (strong, nonatomic) NSString* countryCode;
@property (strong, nonatomic) dispatch_queue_t heartbeatQueue;
@property (strong, nonatomic) dispatch_source_t heartbeat;
@property (strong, nonatomic) NSString* launchedFromTeakNotifId;
@property (strong, nonatomic) NSString* launchedFromDeepLink;
@property (strong, nonatomic) NSMutableArray* attributionChain;

@property (strong, nonatomic, readwrite) NSString* userId;
@property (strong, nonatomic, readwrite) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic, readwrite) TeakDeviceConfiguration* deviceConfiguration;
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;
@end

@implementation TeakSession

DefineTeakState(Allocated, (@[@"Created", @"Expiring"]))
DefineTeakState(Created, (@[@"Configured", @"Expiring"]))
DefineTeakState(Configured, (@[@"UserIdentified", @"Expiring"]))
DefineTeakState(UserIdentified, (@[@"Expiring"]))
DefineTeakState(Expiring, (@[@"Configured", @"UserIdentified", @"Expired"]))
DefineTeakState(Expired, (@[]))

+ (NSMutableArray*)whenUserIdIsReadyRunBlocks
{
   static NSMutableArray* ret = nil;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      ret = [[NSMutableArray alloc] init];
   });
   return ret;
}

+ (void)whenUserIdIsReadyRun:(nonnull UserIdReadyBlock)block {
   @synchronized (currentSessionMutex) {
      if (currentSession != nil && currentSession.currentState == [TeakSession UserIdentified]) {
         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            block(currentSession);
         });
      } else {
         [[TeakSession whenUserIdIsReadyRunBlocks] addObject:[block copy]];
      }
   }
}

- (BOOL)setState:(nonnull TeakState*)newState {
   @synchronized (self) {
      if (self.currentState == newState) {
         TeakLog("Session State transition to same state (%@). Ignoring.", self.currentState);
         return NO;
      }

      if (![self.currentState canTransitionToState:newState]) {
         TeakLog("Invalid Session State transition (%@ -> %@). Ignoring.", self.currentState, newState);
         return NO;
      }

      NSMutableArray* invalidValuesForTransition = [[NSMutableArray alloc] init];

      // Check the data that should be valid before transitioning to the next state. Perform any
      // logic that should occur on transition.
      if (newState == [TeakSession Created]) {
         if (self.startDate == nil) {
            [invalidValuesForTransition addObject:@[@"startDate", @"nil"]];
         } else if (self.appConfiguration == nil) {
            [invalidValuesForTransition addObject:@[@"appConfiguration", @"nil"]];
            //invalidValuesForTransition.add(new Object[]{"appConfiguration", "null"});
         } else if (self.deviceConfiguration == nil) {
            [invalidValuesForTransition addObject:@[@"deviceConfiguration", @"nil"]];
         }
      } else if (newState == [TeakSession UserIdentified]) {
         if (self.userId == nil) {
            [invalidValuesForTransition addObject:@[@"userId", @"nil"]];
         } else if (self.heartbeatQueue != nil) {
            [invalidValuesForTransition addObject:@[@"heartbeat", [NSString stringWithFormat:@"%p", self.heartbeatQueue]]];
         }
      }

      // Print out any invalid values
      if (invalidValuesForTransition.count > 0) {
         TeakLog(@"Invalid Session value%s while trying to transition from %@ -> %@. Invalidating Session.",
                                      invalidValuesForTransition.count > 1 ? "s" : "", self.currentState, newState);

         for (NSArray* elem in invalidValuesForTransition) {
            TeakLog(@"\t%@: %@", elem[0], elem[1]);
         }

         // Invalidate this session
         [self setState:[TeakState Invalid]];
         return NO;
      }

      self.previousState = self.currentState;
      self.currentState = newState;

      TeakDebugLog(@"Session State transition from %@ -> %@.", self.previousState, self.currentState);

      return YES;
   }
}

- (void)identifyUser {
   @synchronized (self) {
      // Time zone
      NSTimeZone* timeZone = [NSTimeZone localTimeZone];
      float timeZoneOffset = (((float)[timeZone secondsFromGMT]) / 60.0f) / 60.0f;
      NSString* timeZoneString = [NSString stringWithFormat:@"%f", timeZoneOffset];
      if (timeZoneString == nil) {
         timeZoneString = @"unknown";
      }

      // Locale
      NSString* locale = nil;
      @try {
         locale = [[NSLocale preferredLanguages] objectAtIndex:0];
      } @catch (NSException *exception) {
         locale = @"unknown"; // TODO: report
      }

      NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
         @"locale" : locale,
         @"timezone" : timeZoneString
      }];

      if (self.deviceConfiguration.advertisingIdentifier != nil) {
         [payload setObject:self.deviceConfiguration.advertisingIdentifier forKey:@"ios_ad_id"];
         [payload setObject:self.deviceConfiguration.limitAdTracking forKey:@"ios_limit_ad_tracking"];
      }

      if (self.currentState == [TeakSession UserIdentified]) {
         [payload setObject:@YES forKey:@"do_not_track_event"];
      }

      if (self.deviceConfiguration.pushToken != nil) {
         [payload setObject:self.deviceConfiguration.pushToken forKey:@"apns_push_key"];
      } else {
         [payload setObject:@"" forKey:@"apns_push_key"];
      }

      if (self.launchedFromTeakNotifId != nil) {
         [payload setObject:self.launchedFromTeakNotifId forKey:@"teak_notif_id"];
      }

      if (self.launchedFromDeepLink != nil) {
         [payload setObject:self.launchedFromDeepLink forKey:@"deep_link"];
      }

      if ([Teak sharedInstance].fbAccessToken != nil) {
         [payload setObject:[Teak sharedInstance].fbAccessToken forKey:@"access_token"];
      }

      NSLog(@"[Teak] Identifying user: %@", self.userId);
      NSLog(@"[Teak]         Timezone: %@", [NSString stringWithFormat:@"%f", timeZoneOffset]);
      NSLog(@"[Teak]           Locale: %@", [[NSLocale preferredLanguages] objectAtIndex:0]);
      NSLog(@"[Teak]    APNS Push Key: %@", [payload objectForKey:@"apns_push_key"]);

      __block typeof(self) blockSelf = self;
      TeakRequest* request = [[TeakRequest alloc]
                              initWithSession:self
                              forEndpoint:[NSString stringWithFormat:@"/games/%@/users.json", self.appConfiguration.appId]
                              withPayload:payload
                              callback:^(NSURLResponse* response, NSDictionary* reply) {
                                 // TODO: Check response
                                 if (YES) {
                                    bool forceDebug = [[reply valueForKey:@"verbose_logging"] boolValue];
                                    [[Teak sharedInstance].debugConfiguration setForceDebugPreference:forceDebug];
                                    [Teak sharedInstance].enableDebugOutput |= forceDebug;
                                    blockSelf.countryCode = [reply valueForKey:@"country_code"];

                                    // For 'do_not_track_event'
                                    if (blockSelf.currentState != [TeakSession UserIdentified]) {
                                       [blockSelf setState:[TeakSession UserIdentified]];
                                    }
                                 }
                              }];
      [request send];
   }
}

- (void)sendHeartbeat {
   TeakDebugLog(@"Sending heartbeat for user: %@", self.userId);

   NSString* urlString = [NSString stringWithFormat:
                          @"https://iroko.gocarrot.com/ping?game_id=%@&api_key=%@&sdk_version=%@&sdk_platform=%@&app_version=%@%@&buster=%@",
                          URLEscapedString(self.appConfiguration.appId),
                          URLEscapedString(self.userId),
                          URLEscapedString([Teak sharedInstance].sdkVersion),
                          URLEscapedString(self.deviceConfiguration.platformString),
                          URLEscapedString(self.appConfiguration.appVersion),
                          self.countryCode == nil ? @"" : [NSString stringWithFormat:@"&country_code=%@", self.countryCode],
                          URLEscapedString([NSUUID UUID].UUIDString)];

   NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                        timeoutInterval:120];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
   [NSURLConnection sendSynchronousRequest:request
                         returningResponse:nil
                                     error:nil];
#pragma clang diagnostic pop
}

- (TeakSession*)initWithAppConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
   self = [super init];
   if (self) {
      self.currentState = [TeakSession Allocated];
      self.startDate = [[NSDate alloc] init];
      self.appConfiguration = appConfiguration;
      self.deviceConfiguration = deviceConfiguration;
      self.attributionChain = [[NSMutableArray alloc] init];

      RegisterKeyValueObserverFor(self.deviceConfiguration, advertisingIdentifier);
      RegisterKeyValueObserverFor(self.deviceConfiguration, pushToken);
      RegisterKeyValueObserverFor(self, currentState);
      RegisterKeyValueObserverFor([Teak sharedInstance], fbAccessToken);

      [self setState:[TeakSession Created]];
   }
   return self;
}

- (void)dealloc {
   // This observer is only registered in the 'Created' state
   if([self currentState] == [TeakSession Created]) {
      UnRegisterKeyValueObserverFor(self.remoteConfiguration, hostname);
   }
   UnRegisterKeyValueObserverFor(self.deviceConfiguration, advertisingIdentifier);
   UnRegisterKeyValueObserverFor(self.deviceConfiguration, pushToken);
   UnRegisterKeyValueObserverFor(self, currentState);
   UnRegisterKeyValueObserverFor([Teak sharedInstance], fbAccessToken);
}

+ (void)setUserId:(nonnull NSString*)userId {
   if(userId.length == 0) {
      TeakLog(@"userId cannot be nil or empty.");
      return;
   }

   @synchronized (currentSessionMutex) {
      @synchronized (currentSession) {
         if (currentSession.userId != nil && ![currentSession.userId isEqualToString:userId]) {
            TeakSession* newSession = [[TeakSession alloc] initWithAppConfiguration:currentSession.appConfiguration
                                                                deviceConfiguration:currentSession.deviceConfiguration];
            newSession.userId = userId;
            [newSession.attributionChain addObjectsFromArray:currentSession.attributionChain];

            [currentSession setState:[TeakSession Expiring]];
            [currentSession setState:[TeakSession Expired]];

            currentSession = newSession;
         }

         currentSession.userId = userId;

         if (currentSession.currentState == [TeakSession Configured]) {
            [currentSession identifyUser];
         }
      }
   }
}

+ (void)addAttribution:(nonnull NSString*)attribution forKey:(nonnull NSString*)key appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
   @synchronized (currentSessionMutex) {
      // Call getCurrentSession() so the null || Expired logic stays in one place
      [TeakSession currentSessionForAppConfiguration:appConfiguration deviceConfiguration:deviceConfiguration];

      // It's a new session if there's a new launch from a notification
      if ([currentSession valueForKey:key] == nil || ![attribution isEqualToString:[currentSession valueForKey:key]]) {
         TeakDebugLog(@"New session attribution source, creating new session. %@", currentSession != nil ? currentSession : @"");

         TeakSession* oldSession = currentSession;
         currentSession = [[TeakSession alloc] initWithAppConfiguration:oldSession.appConfiguration
                                                    deviceConfiguration:oldSession.deviceConfiguration];

         if (oldSession != nil) {
            [currentSession.attributionChain addObjectsFromArray:oldSession.attributionChain];
            if (oldSession.userId != nil) {
               currentSession.userId = oldSession.userId;
            }
         }

         [oldSession setState:[TeakSession Expiring]];
         [oldSession setState:[TeakSession Expired]];
      }

      [currentSession setValue:attribution forKey:key];
      [currentSession.attributionChain addObject:attribution];

      if (currentSession.currentState == [TeakSession UserIdentified]) {
         [currentSession identifyUser];
      }
   }
}

+ (void)applicationDidBecomeActive:(UIApplication*)application appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
   @synchronized (currentSessionMutex) {
      [TeakSession currentSessionForAppConfiguration:appConfiguration deviceConfiguration:deviceConfiguration];

      if (currentSession.currentState == [TeakSession Expiring]) {
         [currentSession setState:currentSession.previousState];
      }
   }
}

+ (void)applicationWillResignActive:(UIApplication*)application appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
   @synchronized (currentSessionMutex) {
      [currentSession setState:[TeakSession Expiring]];
   }
}

+ (void)didLaunchFromTeakNotification:(nonnull NSString*)teakNotifId appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
   [TeakSession addAttribution:teakNotifId forKey:NSStringFromSelector(@selector(launchedFromTeakNotifId)) appConfiguration:appConfiguration deviceConfiguration:deviceConfiguration];
}

+ (void)didLaunchFromDeepLink:(nonnull NSString*)deepLink appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
   [TeakSession addAttribution:deepLink forKey:NSStringFromSelector(@selector(launchedFromDeepLink)) appConfiguration:appConfiguration deviceConfiguration:deviceConfiguration];
}

+ (TeakSession*)currentSessionForAppConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
   @synchronized (currentSessionMutex) {
      if (currentSession == nil || [currentSession hasExpired]) {
         TeakDebugLog(@"Previous Session expired, creating new session. %@", currentSession != nil ? currentSession : @"");

         TeakSession* oldSession = currentSession;
         currentSession = [[TeakSession alloc] initWithAppConfiguration:appConfiguration deviceConfiguration:deviceConfiguration];

         if (oldSession != nil) {
            [currentSession.attributionChain addObjectsFromArray:oldSession.attributionChain];
            if (oldSession.userId != nil) {
               currentSession.userId = oldSession.userId;
            }
         }
      }
      return currentSession;
   }
}

KeyValueObserverFor(Teak, fbAccessToken) {
   if (oldValue == nil || ![newValue isEqualToString:oldValue]) {
      @synchronized (self) {
         if (self.currentState == [TeakSession UserIdentified]) {
            [self identifyUser];
         }
      }
   }
}

KeyValueObserverFor(TeakSession, currentState) {
   @synchronized (self) {
      if (oldValue == [TeakSession Created]) {
         UnRegisterKeyValueObserverFor(self.remoteConfiguration, hostname);
      }

      if (newValue == [TeakSession Created]) {
         self.remoteConfiguration = [[TeakRemoteConfiguration alloc] initForSession:self];
         RegisterKeyValueObserverFor(self.remoteConfiguration, hostname);
      } else if (newValue == [TeakSession Configured]) {

         if (self.userId != nil) {
            [self identifyUser];
         }
      } else if (newValue == [TeakSession UserIdentified]) {
         self.heartbeatQueue = dispatch_queue_create("io.teak.sdk.heartbeat", NULL);

         // Heartbeat
         __block typeof(self) blockSelf = self;
         self.heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.heartbeatQueue);
         dispatch_source_set_event_handler(self.heartbeat, ^{ [blockSelf sendHeartbeat]; });

         // TODO: If RemoteConfiguration specifies a different rate, use that
         dispatch_source_set_timer(self.heartbeat, dispatch_walltime(NULL, 0), 60ull * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
         dispatch_resume(self.heartbeat);

         // Process WhenUserIdIsReadyRun queue
         @synchronized (currentSessionMutex) {
            NSMutableArray* blocks = [TeakSession whenUserIdIsReadyRunBlocks];
            for (UserIdReadyBlock block in blocks) {
               dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                  block(self);
               });
            }
            [blocks removeAllObjects];
         }
      } else if (newValue == [TeakSession Expiring]) {
         self.endDate = [[NSDate alloc] init];

         // Stop heartbeat, Expiring->Expiring is possible, so no invalid data here
         if (self.heartbeat != nil) {
            dispatch_source_cancel(self.heartbeat);
         }
         self.heartbeat = nil;
         self.heartbeatQueue = nil;
      } else if (newValue == [TeakSession Expired]) {
         // TODO: Report Session to server, once we collect that info.
      }
   }
}

KeyValueObserverFor(TeakDeviceConfiguration, advertisingIdentifier) {
   @synchronized (self) {
      if (self.currentState == [TeakSession UserIdentified]) {
         [self identifyUser];
      }
   }
}

KeyValueObserverFor(TeakDeviceConfiguration, pushToken) {
   [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
      if([Teak sharedInstance].enableDebugOutput && self.deviceConfiguration.pushToken != nil) {
         NSString* urlString = [NSString stringWithFormat:@"https://app.teak.io/apps/%@/test_accounts/new?api_key=%@&apns_push_key=%@&device_model=%@&bundle_id=%@&is_sandbox=%@&device_id=%@",
         URLEscapedString(self.appConfiguration.appId),
         URLEscapedString(self.appConfiguration.apiKey),
         URLEscapedString(self.deviceConfiguration.pushToken),
         URLEscapedString(self.deviceConfiguration.deviceModel),
         URLEscapedString(self.appConfiguration.bundleId),
         self.appConfiguration.isProduction ? @"false" : @"true",
         URLEscapedString(self.deviceConfiguration.deviceId)];
         TeakLog(@"If you want to debug or test push notifications on this device please click the link below, or copy/paste into your browser:");
         TeakLog(@"%@", urlString);
      }

      [session identifyUser];
   }];
}

KeyValueObserverFor(TeakRemoteConfiguration, hostname) {
   [self setState:[TeakSession Configured]];
}

- (BOOL)hasExpired {
   @synchronized (self) {
      if (self.currentState == [TeakSession Expiring] && [[[NSDate alloc] init] timeIntervalSinceDate:self.endDate] > kSameSessionDeltaSeconds) {
         [self setState:[TeakSession Expired]];
      }
      return self.currentState == [TeakSession Expired];
   }
}

KeyValueObserverSupported

@end
