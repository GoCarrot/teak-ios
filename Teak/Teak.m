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

#import <AdSupport/AdSupport.h>
#import <UserNotifications/UNUserNotificationCenter.h>

#import "Teak+Internal.h"
#import <Teak/Teak.h>

#import "TeakRequest.h"
#import "TeakSession.h"

#import "SKPaymentObserver.h"
#import "TeakCore.h"
#import "TeakNotification.h"
#import "TeakReward.h"
#import "TeakVersion.h"

#import "FacebookAccessTokenEvent.h"
#import "LifecycleEvent.h"
#import "PurchaseEvent.h"
#import "PushRegistrationEvent.h"
#import "TrackEventEvent.h"
#import "UserIdEvent.h"

NSString* const TeakNotificationAppLaunch = @"TeakNotificationAppLaunch";
NSString* const TeakOnReward = @"TeakOnReward";

// FB SDK 3.x
NSString* const TeakFBSessionDidBecomeOpenActiveSessionNotification = @"com.facebook.sdk:FBSessionDidBecomeOpenActiveSessionNotification";

// FB SDK 4.x
NSString* const TeakFBSDKAccessTokenDidChangeNotification = @"com.facebook.sdk.FBSDKAccessTokenData.FBSDKAccessTokenDidChangeNotification";
NSString* const TeakFBSDKAccessTokenDidChangeUserID = @"FBSDKAccessTokenDidChangeUserID";
NSString* const TeakFBSDKAccessTokenChangeNewKey = @"FBSDKAccessToken";
NSString* const TeakFBSDKAccessTokenChangeOldKey = @"FBSDKAccessTokenOld";

// AIR/Unity/etc SDK Version Extern
NSDictionary* TeakWrapperSDK = nil;

NSDictionary* TeakVersionDict = nil;

extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);
extern BOOL TeakLink_HandleDeepLink(NSURL* deepLink);

Teak* _teakSharedInstance;

@implementation Teak

+ (Teak*)sharedInstance {
  return _teakSharedInstance;
}

+ (NSURLSession*)sharedURLSession {
  static NSURLSession* session = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURLSessionConfiguration* sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.URLCache = nil;
    sessionConfiguration.URLCredentialStorage = nil;
    sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    sessionConfiguration.HTTPAdditionalHeaders = @{@"X-Teak-DeviceType" : @"API"};
    session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
  });
  return session;
}

+ (void)initForApplicationId:(NSString*)appId withClass:(Class)appDelegateClass andApiKey:(NSString*)apiKey {
  Teak_Plant(appDelegateClass, appId, apiKey);
}

- (void)identifyUser:(NSString*)userIdentifier {
  if (userIdentifier == nil || userIdentifier.length == 0) {
    TeakLog_e(@"identify_user.error", @"User identifier can not be null or empty.");
    return;
  }

  TeakLog_i(@"identify_user", @{@"userId" : userIdentifier});

  [UserIdEvent userIdentified:userIdentifier];
}

- (void)trackEventWithActionId:(NSString*)actionId forObjectTypeId:(NSString*)objectTypeId andObjectInstanceId:(NSString*)objectInstanceId {
  if (actionId == nil || actionId.length == 0) {
    TeakLog_e(@"track_event.error", @"actionId can not be null or empty for trackEvent(), ignoring.");
    return;
  }

  if ((objectInstanceId != nil && objectInstanceId.length > 0) &&
      (objectTypeId == nil || objectTypeId.length == 0)) {
    TeakLog_e(@"track_event.error", @"objectTypeId can not be null or empty if objectInstanceId is present for trackEvent(), ignoring.");
    return;
  }

  TeakLog_i(@"track_event", @{@"actionId" : _(actionId), @"objectTypeId" : _(objectTypeId), @"objectInstanceId" : _(objectInstanceId)});

  NSDictionary* payload = @{
    @"action_type" : actionId,
    @"object_type" : _(objectTypeId),
    @"object_instance_id" : _(objectInstanceId)
  };
  [TrackEventEvent trackedEventWithPayload:payload];
}

- (BOOL)hasUserDisabledPushNotifications:(void (^_Nonnull)(BOOL))callback {
  if (callback == nil) return NO;

  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* _Nonnull settings) {
      switch (settings.authorizationStatus) {
        case UNAuthorizationStatusDenied: {
          callback(YES);
          break;
        }
        // Authorized or NotDetermined means they haven't disabled
        case UNAuthorizationStatusAuthorized:
        case UNAuthorizationStatusNotDetermined: {
          callback(NO);
        } break;
      }
    }];
    return YES;
  }

  return NO;
}

- (void)openSettingsAppToThisAppsSettings {
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
}

- (void)setApplicationBadgeNumber:(int)count {
  // If iOS 8+ then check first to see if we have permission to change badge, otherwise
  // just go ahead and change it.
  if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
    UIUserNotificationSettings* notificationSettings = [[UIApplication sharedApplication] currentUserNotificationSettings];
    if (notificationSettings.types & UIUserNotificationTypeBadge) {
      [[UIApplication sharedApplication] setApplicationIconBadgeNumber:count];
    }
  } else {
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:count];
  }
}

////////////////////////////////////////////////////////////////////////////////

- (id)initWithApplicationId:(NSString*)appId andSecret:(NSString*)appSecret {
  self = [super init];
  if (self) {

    if ([appId length] == 0) {
      [NSException raise:NSInvalidArgumentException format:@"Teak appId cannot be null or empty."];
      return nil;
    }

    if ([appSecret length] == 0) {
      [NSException raise:NSInvalidArgumentException format:@"Teak apiKey cannot be null or empty."];
      return nil;
    }

    // Native SDK version
    self.sdkVersion = [NSString stringWithUTF8String:TEAK_SDK_VERSION];

    // Log messages
    self.log = [[TeakLog alloc] initWithAppId:appId];

    [TeakConfiguration configureForAppId:appId andSecret:appSecret];
    self.configuration = [TeakConfiguration configuration];

    self.enableDebugOutput = self.configuration.debugConfiguration.forceDebug;
    self.enableDebugOutput |= !self.configuration.appConfiguration.isProduction;

    // Add Unity/Air SDK version if applicable
    NSMutableDictionary* sdkDict = [NSMutableDictionary dictionaryWithDictionary:@{@"ios" : self.sdkVersion}];
    if (TeakWrapperSDK != nil) {
      [sdkDict addEntriesFromDictionary:TeakWrapperSDK];
    }
    TeakVersionDict = sdkDict;

    // TODO
    [self.log useSdk:TeakVersionDict];
    [self.log useAppConfiguration:self.configuration.appConfiguration];
    [self.log useDeviceConfiguration:self.configuration.deviceConfiguration];

    // Set up SDK Raven
    self.sdkRaven = [TeakRaven ravenForTeak:self];

    // Operation queue
    self.operationQueue = [[NSOperationQueue alloc] init];

    // Teak Core
    // TODO: This should be factory based
    self.core = [[TeakCore alloc] initForSomething:@"temporary"];

    // Payment observer
    self.paymentObserver = [[SKPaymentObserver alloc] initForSomething:@"temporary"];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)fbAccessTokenChanged_4x:(NSNotification*)notification {
  id newAccessToken = [notification.userInfo objectForKey:TeakFBSDKAccessTokenChangeNewKey];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  id accessToken = [newAccessToken performSelector:sel_getUid("tokenString")];
  if (accessToken != nil && accessToken != [NSNull null]) {
    [FacebookAccessTokenEvent accessTokenUpdated:accessToken];
  }
#pragma clang diagnostic pop
}

- (void)fbAccessTokenChanged_3x:(NSNotification*)notification {
  Class fbSession = NSClassFromString(@"FBSession");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  id activeSession = [fbSession performSelector:sel_getUid("activeSession")];
  id accessTokenData = [activeSession performSelector:sel_getUid("accessTokenData")];
  id accessToken = [accessTokenData performSelector:sel_getUid("accessToken")];
  if (accessToken != nil && accessToken != [NSNull null]) {
    [FacebookAccessTokenEvent accessTokenUpdated:accessToken];
  }
#pragma clang diagnostic pop
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url options:(NSDictionary<NSString*, id>*)options {
  if (url != nil) {
    return [self handleDeepLink:url];
  }

  return NO;
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation {
  if (url != nil) {
    return [self handleDeepLink:url];
  }

  return NO;
}

- (BOOL)handleDeepLink:(nonnull NSURL*)url {
  // Attribution
  [TeakSession didLaunchFromDeepLink:url.absoluteString appConfiguration:self.configuration.appConfiguration deviceConfiguration:self.configuration.deviceConfiguration];

  return TeakLink_HandleDeepLink(url);
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});

  // Facebook SDKs
  Class fb4xClass = NSClassFromString(@"FBSDKProfile");
  Class fb3xClass = NSClassFromString(@"FBSession");
  teak_try {
    if (fb4xClass != nil) {
      BOOL arg = YES;
      SEL enableUpdatesOnAccessTokenChange = NSSelectorFromString(@"enableUpdatesOnAccessTokenChange:");
      NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[fb4xClass methodSignatureForSelector:enableUpdatesOnAccessTokenChange]];
      [inv setSelector:enableUpdatesOnAccessTokenChange];
      [inv setTarget:fb4xClass];
      [inv setArgument:&arg atIndex:2];
      [inv invoke];

      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(fbAccessTokenChanged_4x:)
                                                   name:TeakFBSDKAccessTokenDidChangeNotification
                                                 object:nil];
    } else if (fb3xClass != nil) {
      // accessTokenData
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(fbAccessTokenChanged_3x:)
                                                   name:TeakFBSessionDidBecomeOpenActiveSessionNotification
                                                 object:nil];
    }

    if (self.enableDebugOutput) {
      if (fb4xClass != nil) {
        TeakLog_i(@"facebook.sdk", @{@"version" : @"4.x"});
      } else if (fb3xClass != nil) {
        TeakLog_i(@"facebook.sdk", @{@"version" : @"3.x"});
      } else {
        TeakLog_i(@"facebook.sdk", @{@"version" : [NSNull null]});
      }
    }
  }
  teak_catch_report;

  // Register push notification categories
  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    NSMutableSet* categories = [[NSMutableSet alloc] init];
    for (NSString* key in TeakNotificationCategories) {
      NSDictionary* category = TeakNotificationCategories[key];

      NSMutableArray* actions = [[NSMutableArray alloc] init];
      for (NSArray* actionPair in category[@"actions"]) {
        UNNotificationAction* action = [UNNotificationAction actionWithIdentifier:actionPair[0]
                                                                            title:actionPair[1]
                                                                          options:UNNotificationActionOptionForeground];
        [actions addObject:action];
      }

      UNNotificationCategory* notifCategory = [UNNotificationCategory categoryWithIdentifier:key
                                                                                     actions:actions
                                                                           intentIdentifiers:@[]
                                                                                     options:UNNotificationCategoryOptionCustomDismissAction];
      [categories addObject:notifCategory];
    }
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    [center setNotificationCategories:categories];
  }

  // If the app was not running, we need to check these and invoke them afterwards
  if (launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
    [self application:application didReceiveRemoteNotification:launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]];
  } else if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
    [self application:application openURL:launchOptions[UIApplicationLaunchOptionsURLKey] sourceApplication:launchOptions[UIApplicationLaunchOptionsSourceApplicationKey] annotation:launchOptions[UIApplicationLaunchOptionsAnnotationKey]];
  }

  // Check to see if the user has already enabled push notifications
  BOOL pushEnabled = NO;
  if ([application respondsToSelector:@selector(isRegisteredForRemoteNotifications)]) {
    pushEnabled = [application isRegisteredForRemoteNotifications];
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIRemoteNotificationType types = [application enabledRemoteNotificationTypes];
    pushEnabled = types & UIRemoteNotificationTypeAlert;
#pragma clang diagnostic pop
  }

  // If they've already enabled push, go ahead and register since it won't pop up a box.
  // This is to ensure that we always get didRegisterForRemoteNotificationsWithDeviceToken:
  // even if the app developer doesn't follow Apple's best practices.
  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* _Nonnull settings) {
      switch (settings.authorizationStatus) {
        case UNAuthorizationStatusDenied:
          // They need to go into the Settings and enable it
          break;
        case UNAuthorizationStatusAuthorized: {
          // Already enabled
          [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge
                                completionHandler:^(BOOL granted, NSError* _Nullable error) {
                                  if (granted) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                      [application registerForRemoteNotifications];
                                    });
                                  }
                                }];
        } break;
        case UNAuthorizationStatusNotDetermined:
          // They haven't been asked
          break;
      }
    }];
  } else if (pushEnabled) {
    if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
      UIUserNotificationSettings* settings = application.currentUserNotificationSettings;
      [application registerUserNotificationSettings:settings];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      UIRemoteNotificationType types = [application enabledRemoteNotificationTypes];
      [application registerForRemoteNotificationTypes:types];
#pragma clang diagnostic pop
    }
  }

  // Lifecycle event
  [LifecycleEvent applicationFinishedLaunching];

  return NO;
}

- (void)applicationDidBecomeActive:(UIApplication*)application {
  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});

  // Zero-out the badge count
  [self setApplicationBadgeNumber:0];

  // Lifecycle Event
  [LifecycleEvent applicationActivate];
}

- (void)applicationWillResignActive:(UIApplication*)application {
  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});
  [LifecycleEvent applicationDeactivate];
}

- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
  [application registerForRemoteNotifications];
}

- (void)userNotificationCenter:(UNUserNotificationCenter*)center
       willPresentNotification:(UNNotification*)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
  // When notification is delivered with app in the foreground, mute it like default behavior
  completionHandler(UNNotificationPresentationOptionNone);
}
- (void)userNotificationCenter:(UNUserNotificationCenter*)center
    didReceiveNotificationResponse:(UNNotificationResponse*)response
             withCompletionHandler:(void (^)(void))completionHandler {

  // Call application:didReceiveRemoteNotification: since that is not called in the UNNotificationCenter
  // code path.
  [self application:[UIApplication sharedApplication] didReceiveRemoteNotification:response.notification.request.content.userInfo];
  completionHandler();
  // TODO: HERE is where we report metric that a button was pressed
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
  if (deviceToken == nil) {
    TeakLog_e(@"notification.registration.error", @"Got nil deviceToken. Push is disabled.");
    return;
  }

  NSString* deviceTokenString = [[[[deviceToken description]
      stringByReplacingOccurrencesOfString:@"<"
                                withString:@""]
      stringByReplacingOccurrencesOfString:@">"
                                withString:@""]
      stringByReplacingOccurrencesOfString:@" "
                                withString:@""];
  if (deviceTokenString != nil) {
    TeakLog_i(@"notification.registration.success", @{@"token" : deviceTokenString});
    [PushRegistrationEvent registeredWithToken:deviceTokenString];
  } else {
    TeakLog_e(@"notification.registration.error", @"Got nil deviceTokenString. Push is disabled.");
  }
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
  if (error != nil) {
    TeakLog_e(@"notification.registration.error", @"Failed to register for push notifications.", @{@"error" : _([error localizedDescription])});
  } else {
    TeakLog_e(@"notification.registration.error", @"Failed to register for push notifications.", @{@"error" : @"unknown"});
  }
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo {
  NSDictionary* aps = userInfo[@"aps"];
  NSString* teakNotifId = NSStringOrNilFor(aps[@"teakNotifId"]);

  if (teakNotifId != nil) {
    TeakNotification* notif = [[TeakNotification alloc] initWithDictionary:aps];

    if (notif != nil) {
      BOOL isInBackground = application.applicationState == UIApplicationStateInactive || application.applicationState == UIApplicationStateBackground;

      // TODO: Send notification_received metric

      if (isInBackground) {
        // App was opened via push notification
        TeakLog_i(@"notification.opened", @{@"teakNotifId" : _(teakNotifId)});

        [TeakSession didLaunchFromTeakNotification:teakNotifId
                                  appConfiguration:self.configuration.appConfiguration
                               deviceConfiguration:self.configuration.deviceConfiguration];

        NSMutableDictionary* teakUserInfo = [[NSMutableDictionary alloc] init];
        teakUserInfo[@"teakNotifId"] = teakNotifId;
#define ValueOrNSNull(x) (x == nil ? [NSNull null] : x)
        teakUserInfo[@"teakRewardId"] = ValueOrNSNull([aps[@"teakRewardId"] stringValue]);
        teakUserInfo[@"teakScheduleName"] = ValueOrNSNull(aps[@"teakScheduleName"]);
        teakUserInfo[@"teakCreativeName"] = ValueOrNSNull(aps[@"teakCreativeName"]);
#undef ValueOrNSNull
        teakUserInfo[@"incentivized"] = aps[@"teakRewardId"] == nil ? @NO : @YES;

        if (notif.teakRewardId != nil) {
          TeakReward* reward = [TeakReward rewardForRewardId:notif.teakRewardId];
          if (reward != nil) {
            __weak TeakReward* weakReward = reward;
            reward.onComplete = ^() {
              __strong TeakReward* blockReward = weakReward;

              [teakUserInfo setValue:blockReward.json == nil ? [NSNull null] : blockReward.json forKey:@"teakReward"];
              if (blockReward.json != nil) {
                [teakUserInfo addEntriesFromDictionary:blockReward.json];
                [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
                  [[NSNotificationCenter defaultCenter] postNotificationName:TeakOnReward
                                                                      object:self
                                                                    userInfo:teakUserInfo];
                }];
              }

              [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
                [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                                    object:self
                                                                  userInfo:teakUserInfo];
              }];
            };
          } else {
            [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
              [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                                  object:self
                                                                userInfo:teakUserInfo];
            }];
          }
        } else {
          [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
            [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                                object:self
                                                              userInfo:teakUserInfo];
          }];
        }

        // If there's a deep link, see if Teak handles it. Otherwise use openURL.
        if (notif.teakDeepLink != nil) {
          if (![self handleDeepLink:notif.teakDeepLink] && [application canOpenURL:notif.teakDeepLink]) {

            // iOS 10+
            if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
              [application openURL:notif.teakDeepLink
                            options:@{}
                  completionHandler:^(BOOL success){
                      // This handler intentionally left blank
                  }];

              // iOS < 10
            } else {
              [application openURL:notif.teakDeepLink];
            }
          }
        }
      } else {
        // Push notification received while app was in foreground
        TeakLog_i(@"notification.foreground", @{@"teakNotifId" : _(teakNotifId)});
      }
    }
  } else {
    TeakLog_i(@"notification.non_teak", userInfo);
  }
}

- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler {
  if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {

    // Make sure the URL we fetch is https
    NSURLComponents* components = [NSURLComponents componentsWithURL:userActivity.webpageURL
                                             resolvingAgainstBaseURL:YES];
    components.scheme = @"https";
    NSURL* fetchUrl = components.URL;

    // Fetch the data for the short link
    NSURLSessionDataTask* task = [[Teak sharedURLSession] dataTaskWithURL:fetchUrl
                                                        completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
                                                          NSURL* attributionUrl = userActivity.webpageURL;

                                                          if (error == nil) {
                                                            NSDictionary* reply = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                                                            if (error == nil) {
                                                              NSString* iOSPath = reply[@"iOSPath"];
                                                              if (iOSPath != nil) {
                                                                attributionUrl = [NSURL URLWithString:[NSString stringWithFormat:@"teak%@://%@", self.configuration.appConfiguration.appId, iOSPath]];
                                                              }
                                                            }
                                                          }

                                                          // Attribution
                                                          [TeakSession didLaunchFromDeepLink:attributionUrl.absoluteString appConfiguration:self.configuration.appConfiguration deviceConfiguration:self.configuration.deviceConfiguration];

                                                          TeakLink_HandleDeepLink(attributionUrl);
                                                        }];
    [task resume];
  }

  return YES;
}

@end
