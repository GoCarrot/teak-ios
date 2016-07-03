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

@import AdSupport;
@import StoreKit;

#import <Teak/Teak.h>
#import "Teak+Internal.h"
#import "TeakCache.h"
#import "TeakRequestThread.h"
#import "TeakNotification.h"
#import <sys/utsname.h>
#import "TeakVersion.h"

#define kPushTokenUserDefaultsKey @"TeakPushToken"
#define kDeviceIdKey @"TeakDeviceId"

NSString* const TeakNotificationAvailable = @"TeakNotifiacationAvailableId";
NSString* const TeakNotificationAppLaunch = @"TeakNotificationAppLaunch";

// FB SDK 3.x
NSString *const TeakFBSessionDidBecomeOpenActiveSessionNotification = @"com.facebook.sdk:FBSessionDidBecomeOpenActiveSessionNotification";

// FB SDK 4.x
NSString *const TeakFBSDKAccessTokenDidChangeNotification = @"com.facebook.sdk.FBSDKAccessTokenData.FBSDKAccessTokenDidChangeNotification";
NSString *const TeakFBSDKAccessTokenDidChangeUserID = @"FBSDKAccessTokenDidChangeUserID";
NSString *const TeakFBSDKAccessTokenChangeNewKey = @"FBSDKAccessToken";
NSString *const TeakFBSDKAccessTokenChangeOldKey = @"FBSDKAccessTokenOld";

extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);

extern BOOL isProductionProvisioningProfile(NSString* profilePath);

Teak* _teakSharedInstance;

@interface Teak () <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@property (nonatomic) dispatch_queue_t heartbeatQueue;
@property (nonatomic) dispatch_source_t heartbeat;

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions;

@end

@implementation Teak

+ (Teak*)sharedInstance
{
   return _teakSharedInstance;
}

+ (void)initForApplicationId:(NSString*)appId withClass:(Class)appDelegateClass andSecret:(NSString*)appSecret;
{
   Teak_Plant(appDelegateClass, appId, appSecret);
}

- (void)identifyUser:(NSString*)userId
{
   self.userId = userId;
   [self.sdkRaven setUserValue:userId forKey:@"id"];
   [self.dependentOperationQueue addOperation:self.userIdOperation];
}

- (void)trackEventWithActionId:(NSString*)actionId forObjectTypeId:(NSString*)objectTypeId andObjectInstanceId:(NSString*)objectInstanceId
{
   NSDictionary* payload = @{
      @"action_type" : actionId,
      @"object_type" : objectTypeId,
      @"object_instance_id" : objectInstanceId
   };

   [self.requestThread addRequestForService:TeakRequestServiceMetrics
                                 atEndpoint:@"/me/events"
                                usingMethod:TeakRequestTypePOST
                                withPayload:payload
                                andCallback:nil];
}

////////////////////////////////////////////////////////////////////////////////

- (id)initWithApplicationId:(NSString*)appId andSecret:(NSString*)appSecret
{
   self = [super init];
   if(self)
   {
      // Output version first thing
      self.sdkVersion = [NSString stringWithUTF8String: TEAK_SDK_VERSION];
      NSLog(@"[Teak] iOS SDK Version: %@", self.sdkVersion);

      // App Id/Secret
      self.appId = appId;
      self.appSecret = appSecret;

      // Load settings
      NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
      self.pushToken = [userDefaults stringForKey:kPushTokenUserDefaultsKey];

      // Get/create device id
      self.deviceId = [userDefaults objectForKey:kDeviceIdKey];
      if(self.deviceId == nil)
      {
         self.deviceId = [[NSUUID UUID] UUIDString];
         [userDefaults setObject:self.deviceId forKey:kDeviceIdKey];
         [userDefaults synchronize];
      }

      // Check if this is production mode (default YES)
      self.isProduction = isProductionProvisioningProfile([[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"]);
      self.enableDebugOutput = !self.isProduction;

      // Get device/app information
      struct utsname systemInfo;
      uname(&systemInfo);
      self.deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
      self.sdkPlatform = [NSString stringWithFormat:@"ios_%f",[[[UIDevice currentDevice] systemVersion] floatValue]];
      self.appVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];

      // Set up SDK Raven
      self.sdkRaven = [TeakRaven ravenForTeak:self];

      // Get data path
      NSArray* searchPaths = [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask];
      self.dataPath = [[[searchPaths lastObject] URLByAppendingPathComponent:@"Teak"] path];

      NSError* error = nil;
      BOOL succeeded = [[NSFileManager defaultManager] createDirectoryAtPath:self.dataPath
                                                 withIntermediateDirectories:YES
                                                                  attributes:nil
                                                                       error:&error];
      if(!succeeded)
      {
         NSLog(@"[Teak] Unable to create Teak data path: %@.", error);
         return nil;
      }

      // Create cache
      self.cache = [TeakCache cacheWithPath:self.dataPath];
      if(!self.cache)
      {
         NSLog(@"[Teak] Unable to create Teak cache.");
         return nil;
      }

      // Request thread
      self.requestThread = [[TeakRequestThread alloc] initWithTeak:self];
      if(!self.requestThread)
      {
         NSLog(@"[Teak] Unable to create Teak request thread.");
         return nil;
      }

      // Allocations
      self.priceInfoCompleteDictionary = [[NSMutableDictionary alloc] init];
      self.priceInfoDictionary = [[NSMutableDictionary alloc] init];

      // Heartbeat
      self.heartbeatQueue = dispatch_queue_create("io.teak.sdk.heartbeat", NULL);

      // Dependent operations
      self.dependentOperationQueue = [[NSOperationQueue alloc] init];
   }
   return self;
}

- (void)dealloc
{
   [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)identifyUser
{
   // If last session ended recently, don't re-identify
   NSTimeInterval lastSessionDelta = [[[NSDate alloc] init] timeIntervalSinceDate:self.lastSessionEndedAt];
   if(lastSessionDelta < kMergeLastSessionDeltaSeconds &&
      self.launchedFromTeakNotifId == nil && self.launchedFromDeepLink == nil &&
      (self.pushTokenOperation == nil || !self.pushTokenOperation.isReady)) return;

   NSTimeZone* timeZone = [NSTimeZone localTimeZone];
   float timeZoneOffset = (((float)[timeZone secondsFromGMT]) / 60.0f) / 60.0f;


   NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
   [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
   [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

   NSDictionary* knownPayload = @{
      @"locale" : [[NSLocale preferredLanguages] objectAtIndex:0],
      @"timezone" : [NSString stringWithFormat:@"%f", timeZoneOffset],
      @"happened_at" : [formatter stringFromDate:[[NSDate alloc] init]]
   };

   NSDictionary* adPayload = nil;
   NSString* advertisingIdentifier = [[ASIdentifierManager sharedManager].advertisingIdentifier UUIDString];
   if(advertisingIdentifier != nil)
   {
      adPayload = @{
         @"ios_ad_id" : advertisingIdentifier,
         @"ios_limit_ad_tracking" : [NSNumber numberWithBool:![ASIdentifierManager sharedManager].advertisingTrackingEnabled]
      };
   }

   // Build dependent payload.
   NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:knownPayload];
   if(adPayload != nil)
   {
      [payload addEntriesFromDictionary:adPayload];
   }
   if(self.userIdentifiedThisSession)
   {
      [payload setObject:[NSNumber numberWithBool:YES] forKey:@"do_not_track_event"];
   }
   if(self.pushToken != nil)
   {
      [payload setObject:self.pushToken forKey:@"apns_push_key"];
   }
   else
   {
      [payload setObject:@"" forKey:@"apns_push_key"];
   }
   if(self.launchedFromTeakNotifId != nil)
   {
      [payload setObject:self.launchedFromTeakNotifId forKey:@"teak_notif_id"];
   }
   if(self.launchedFromDeepLink != nil)
   {
      [payload setObject:[self.launchedFromDeepLink absoluteString] forKey:@"deep_link"];
   }
   if(self.fbAccessToken != nil)
   {
      [payload setObject:self.fbAccessToken forKey:@"access_token"];
   }

   NSLog(@"[Teak] Identifying user: %@", self.userId);
   NSLog(@"[Teak]         Timezone: %@", [NSString stringWithFormat:@"%f", timeZoneOffset]);
   NSLog(@"[Teak]           Locale: %@", [[NSLocale preferredLanguages] objectAtIndex:0]);

   if(self.enableDebugOutput && self.pushToken != nil)
   {
      NSString* urlString = [NSString stringWithFormat:@"https://app.teak.io/apps/%@/test_accounts/new?api_key=%@&apns_push_key=%@&device_model=%@&bundle_id=%@&is_sandbox=%@",
                             self.appId,
                             URLEscapedString(self.userId),
                             URLEscapedString(self.pushToken),
                             URLEscapedString(self.deviceModel),
                             URLEscapedString([[NSBundle mainBundle] bundleIdentifier]),
                             self.isProduction ? @"false" : @"true"];
      NSLog(@"If you want to debug or test push notifications on this device please click the link below, or copy/paste into your browser:");
      NSLog(@"%@", urlString);
   }

   // User identified
   self.userIdentifiedThisSession = YES;

   __block Teak* blockSelf = self;
   [self.requestThread addRequestForService:TeakRequestServiceAuth
                                 atEndpoint:[NSString stringWithFormat:@"/games/%@/users.json", self.appId]
                                usingMethod:TeakRequestTypePOST
                                withPayload:payload
                                andCallback:^(TeakRequest *request, NSHTTPURLResponse *response, NSData *data, TeakRequestThread *requestThread) {
                                   NSError* error = nil;
                                   NSDictionary* jsonReply = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                                   if(error == nil)
                                   {
                                      blockSelf.enableDebugOutput |= [[jsonReply valueForKey:@"verbose_logging"] boolValue];
                                      if([[jsonReply valueForKey:@"verbose_logging"] boolValue])
                                      {
                                         NSLog(@"[Teak] Enabling verbose logging via identifyUser()");
                                      }
                                      blockSelf.teakCountryCode = [jsonReply valueForKey:@"country_code"];
                                   }
    }];
}

- (void)fbAccessTokenChanged_4x:(NSNotification*)notification
{
   id newAccessToken = [notification.userInfo objectForKey:TeakFBSDKAccessTokenChangeNewKey];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
   self.fbAccessToken = [newAccessToken performSelector:sel_getUid("tokenString")];
#pragma clang diagnostic pop

   [self.dependentOperationQueue addOperation:self.facebookAccessTokenOperation];
}

- (void)fbAccessTokenChanged_3x:(NSNotification*)notification
{
   Class fbSession = NSClassFromString(@"FBSession");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
   id activeSession = [fbSession performSelector:sel_getUid("activeSession")];
   id accessTokenData = [activeSession performSelector:sel_getUid("accessTokenData")];
   self.fbAccessToken = [accessTokenData performSelector:sel_getUid("accessToken")];
#pragma clang diagnostic pop

   if(self.fbAccessToken != nil)
   {
      [self.dependentOperationQueue addOperation:self.facebookAccessTokenOperation];
   }
}

- (void)sendHeartbeat
{
   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Sending heartbeat for user: %@", self.userId);
   }

   NSString* urlString = [NSString stringWithFormat:
                          @"https://iroko.gocarrot.com/ping?game_id=%@&api_key=%@&sdk_version=%@&sdk_platform=%@&app_version=%@%@&buster=%@",
                          URLEscapedString(self.appId),
                          URLEscapedString(self.userId),
                          URLEscapedString(self.sdkVersion),
                          URLEscapedString(self.sdkPlatform),
                          URLEscapedString(self.appVersion),
                          self.teakCountryCode == nil ? @"" : [NSString stringWithFormat:@"&country_code=%@", self.teakCountryCode],
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

- (BOOL)handleOpenURL:(NSURL*)url
{
   if(url != nil)
   {
      if(self.enableDebugOutput)
      {
         NSLog(@"[Teak] Deep link received: %@", url);
      }

      // Talk to Unity, et. al. to see if we can handle this deep link
      if(YES)
      {
         self.launchedFromDeepLink = url;
         return YES;
      }
   }
   return NO;
}

- (BOOL)application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
   return NO;
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
   // User input dependent operations
   if(self.userIdOperation == nil)
   {
      if(self.userId == nil)
      {
         self.userIdOperation = [NSBlockOperation blockOperationWithBlock:^{
            if(self.enableDebugOutput)
            {
               NSLog(@"[Teak] User Id ready: %@", self.userId);
            }
         }];
      }
      else
      {
         if(self.enableDebugOutput)
         {
            NSLog(@"[Teak] User Id ready: %@", self.userId);
         }
      }
   }

   if(self.facebookAccessTokenOperation == nil)
   {
      if(self.fbAccessToken == nil)
      {
         self.facebookAccessTokenOperation = [NSBlockOperation blockOperationWithBlock:^{
            if(self.enableDebugOutput)
            {
               NSLog(@"[Teak] Facebook Access Token is ready: %@", self.fbAccessToken);
            }
            [self identifyUser];
         }];
         if(self.userIdOperation != nil)
         {
            [self.facebookAccessTokenOperation addDependency:self.userIdOperation];
         }
      }
   }

   // Facebook SDKs
   Class fb4xClass = NSClassFromString(@"FBSDKProfile");
   Class fb3xClass = NSClassFromString(@"FBSession");
   if(fb4xClass != nil)
   {
      BOOL arg = YES;
      SEL enableUpdatesOnAccessTokenChange = NSSelectorFromString(@"enableUpdatesOnAccessTokenChange");
      NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[fb4xClass methodSignatureForSelector:enableUpdatesOnAccessTokenChange]];
      [inv setSelector:enableUpdatesOnAccessTokenChange];
      [inv setTarget:fb4xClass];
      [inv setArgument:&arg atIndex:2];
      [inv invoke];

      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(fbAccessTokenChanged_4x:)
                                                   name:TeakFBSDKAccessTokenDidChangeNotification
                                                 object:nil];
   }
   else if(fb3xClass != nil)
   {
      // accessTokenData
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(fbAccessTokenChanged_3x:)
                                                   name:TeakFBSessionDidBecomeOpenActiveSessionNotification
                                                 object:nil];
   }

   if(self.pushTokenOperation == nil)
   {
      if(self.pushToken == nil)
      {
         self.pushTokenOperation = [NSBlockOperation blockOperationWithBlock:^{
            if(self.enableDebugOutput)
            {
               NSLog(@"[Teak] Push Token is ready: %@", self.pushToken);
            }
            [self identifyUser];
         }];
         if(self.userIdOperation)
         {
            [self.pushTokenOperation addDependency:self.userIdOperation];
         }
      }
   }

   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Lifecycle - application:didFinishLaunchingWithOptions:");
      if(fb4xClass != nil) NSLog(@"[Teak] Using Facebook SDK v4.x");
      else if(fb3xClass != nil) NSLog(@"[Teak] Using Facebook SDK v3.x");
      else NSLog(@"[Teak] Facebook SDK not detected");
   }

   // If the app was not running, we need to check these and invoke them afterwards
   if(launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey])
   {
      [self application:application didReceiveRemoteNotification:launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]];
   }

   if(launchOptions[UIApplicationLaunchOptionsURLKey])
   {
      [self handleOpenURL:launchOptions[UIApplicationLaunchOptionsURLKey]];
   }

   // Set up listeners
   [[SKPaymentQueue defaultQueue] addTransactionObserver:self];

   return NO;
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
   // If iOS 8+ then check first to see if we have permission to change badge, otherwise
   // just go ahead and change it.
   if([application respondsToSelector:@selector(registerUserNotificationSettings:)])
   {
      UIUserNotificationSettings* notificationSettings = [application currentUserNotificationSettings];
      if(notificationSettings.types & UIUserNotificationTypeBadge)
      {
         [application setApplicationIconBadgeNumber:0];
      }
   }
   else
   {
      [application setApplicationIconBadgeNumber:0];
   }

   // Reset session-based things
   self.userIdentifiedThisSession = NO;

   // Configure NSOperation chains

   // User Id has no dependencies
   if(self.userIdOperation == nil)
   {
      if(self.userId == nil)
      {
         self.userIdOperation = [NSBlockOperation blockOperationWithBlock:^{
            if(self.enableDebugOutput)
            {
               NSLog(@"[Teak] User Id is ready: %@", self.userId);
            }
         }];
      }
      else
      {
         if(self.enableDebugOutput)
         {
            NSLog(@"[Teak] User Id is ready: %@", self.userId);
         }
      }
   }

   // Services configuration needs user id
   self.serviceConfigurationOperation = [NSBlockOperation blockOperationWithBlock:^{
      [[Teak sharedInstance] configure];
   }];
   if(self.userIdOperation != nil)
   {
      [self.serviceConfigurationOperation addDependency:self.userIdOperation];
   }

   // Heartbeat needs services and user id, same with request thread
   self.liveConnectionOperation = [NSBlockOperation blockOperationWithBlock:^{
      [self.requestThread start];

      // Heartbeat
      __weak typeof(self) weakSelf = self;
      self.heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.heartbeatQueue);
      dispatch_source_set_event_handler(self.heartbeat, ^{ [weakSelf sendHeartbeat]; });
      dispatch_source_set_timer(self.heartbeat, dispatch_walltime(NULL, 0), 60ull * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
      dispatch_resume(self.heartbeat);
   }];
   if(self.userIdOperation != nil)
   {
      [self.liveConnectionOperation addDependency:self.userIdOperation];
   }
   [self.liveConnectionOperation addDependency:self.serviceConfigurationOperation];
   [self.dependentOperationQueue addOperation:self.liveConnectionOperation];

   // Identify user needs user id
   self.identifyUserOperation = [NSBlockOperation blockOperationWithBlock:^{
      [self identifyUser];
   }];
   if(self.userIdOperation != nil)
   {
      [self.identifyUserOperation addDependency:self.userIdOperation];
   }
   [self.dependentOperationQueue addOperation:self.identifyUserOperation];

   // Facebook access token needs user id
   if(self.facebookAccessTokenOperation == nil)
   {
      if(self.fbAccessToken == nil)
      {
         self.facebookAccessTokenOperation = [NSBlockOperation blockOperationWithBlock:^{
            if(self.enableDebugOutput)
            {
               NSLog(@"[Teak] Facebook Access Token is ready: %@", self.fbAccessToken);
            }
            [self identifyUser];
         }];
         if(self.userIdOperation != nil)
         {
            [self.facebookAccessTokenOperation addDependency:self.userIdOperation];
         }
      }
   }

   // Push token needs user id
   if(self.pushTokenOperation == nil)
   {
      if(self.pushToken == nil)
      {
         self.pushTokenOperation = [NSBlockOperation blockOperationWithBlock:^{
            if(self.enableDebugOutput)
            {
               NSLog(@"[Teak] Push Token is ready: %@", self.pushToken);
            }
            [self identifyUser];
         }];
         if(self.userIdOperation != nil)
         {
            [self.facebookAccessTokenOperation addDependency:self.userIdOperation];
         }
      }
   }

   // Kick off services configuration
   [self.dependentOperationQueue addOperation:self.serviceConfigurationOperation];

   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Lifecycle - applicationDidBecomeActive:");
      NSLog(@"         App Id: %@", self.appId);
      NSLog(@"        Api Key: %@", self.appSecret);
      NSLog(@"    App Version: %@", self.appVersion);
      if(self.launchedFromTeakNotifId != nil)
      {
         NSLog(@"  Teak Notif Id: %@", self.launchedFromTeakNotifId);
      }
      if(self.launchedFromDeepLink != nil)
      {
         NSLog(@"  Deep Link URL: %@", self.launchedFromDeepLink);
      }
   }
}

- (void)applicationWillResignActive:(UIApplication*)application
{
   // Cancel the heartbeat
   if(self.heartbeat != nil) dispatch_source_cancel(self.heartbeat);

   // Stop request thread
   [self.requestThread stop];

   // Clear out operations dependent on user input
   self.userIdOperation = nil;
   self.facebookAccessTokenOperation = nil;

   // Clear launched-by
   self.launchedFromTeakNotifId = nil;
   self.launchedFromDeepLink = nil;

   // Set last-session ended at
   self.lastSessionEndedAt = [[NSDate alloc] init];

   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Lifecycle - applicationWillResignActive:");
   }
}

- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings
{
   [application registerForRemoteNotifications];
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken
{
   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Lifecycle - application:didRegisterForRemoteNotificationsWithDeviceToken:");
   }

   NSString* deviceTokenString = [[[[deviceToken description]
                                    stringByReplacingOccurrencesOfString:@"<" withString:@""]
                                    stringByReplacingOccurrencesOfString:@">" withString:@""]
                                    stringByReplacingOccurrencesOfString:@" " withString:@""];
   if([self.pushToken isEqualToString:deviceTokenString] == NO)
   {
      self.pushToken = deviceTokenString;

      NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
      [userDefaults setObject:deviceTokenString 
                       forKey:kPushTokenUserDefaultsKey];
      [userDefaults synchronize];

      [self.dependentOperationQueue addOperation:self.pushTokenOperation];

      if(self.enableDebugOutput)
      {
         NSLog(@"[Teak] Got new push token: %@", deviceTokenString);
      }
   }
   else
   {
      if(self.enableDebugOutput)
      {
         NSLog(@"[Teak] Using cached push token: %@", self.pushToken);
      }
   }
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error
{
   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Failed to register for push notifications: %@", [error localizedDescription]);
   }
}

- (void)configure
{
   TeakRequest* request = [TeakRequest requestForService:TeakRequestServiceAuth
                                              atEndpoint:[NSString stringWithFormat:@"/games/%@/settings.json", self.appId]
                                             usingMethod:TeakRequestTypePOST
                                             withPayload:@{@"id" : self.appId}
                                                callback:
                           ^(TeakRequest* request, NSHTTPURLResponse* response, NSData* data, TeakRequestThread* requestThread) {

                              NSError* error = nil;
                              NSDictionary* config = [NSJSONSerialization JSONObjectWithData:data
                                                                                     options:kNilOptions
                                                                                       error:&error];
                              if(error)
                              {
                                 NSLog(@"[Teak] Unable to perform services configuration for Teak. Teak is in offline mode.\n%@", error);
                              }
                              else
                              {
                                 self.hostname = @"gocarrot.com";

                                 NSString* sdkSentryDsn = [config valueForKey:@"sdk_sentry_dsn"];
                                 if(sdkSentryDsn)
                                 {
                                    [self.sdkRaven setDSN:sdkSentryDsn];
                                 }

                                 if(self.enableDebugOutput)
                                 {
                                    NSLog(@"[Teak] Services configuration complete: %@", config);
                                 }
                              }
                           }];

   [self.requestThread processRequest:request onHost:@"gocarrot.com"];
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo
{
   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Lifecycle - application:didReceiveRemoteNotification: %@", userInfo);
   }

   NSDictionary* aps = [userInfo objectForKey:@"aps"];
   id teakNotifIdRaw = [aps objectForKey:@"teakNotifId"];
   NSString* teakNotifId = (teakNotifIdRaw == nil || [teakNotifIdRaw isKindOfClass:[NSString class]]) ? teakNotifIdRaw : [teakNotifIdRaw stringValue];

   if(teakNotifId != nil)
   {
      TeakNotification* notif = [TeakNotification notificationFromDictionary:aps];

      if(application.applicationState == UIApplicationStateInactive ||
         application.applicationState == UIApplicationStateBackground)
      {
         // App was opened via push notification
         if(self.enableDebugOutput)
         {
            NSLog(@"[Teak] App Opened from Teak Notification %@", notif);
         }

         self.launchedFromTeakNotifId = teakNotifId;

         if(notif.deepLink != nil)
         {
            [self handleOpenURL:notif.deepLink];
         }

         [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                             object:self
                                                           userInfo:userInfo];
      }
      else
      {
         // Push notification received while app was in foreground
         if(self.enableDebugOutput)
         {
            NSLog(@"[Teak] Teak Notification received in foreground %@", notif);
         }
      }

      [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAvailable
                                                          object:self
                                                        userInfo:userInfo];
   }
   else
   {
      if(self.enableDebugOutput)
      {
         NSLog(@"[Teak] Non-Teak push notification, ignored.");
      }
   }
}

- (void)transactionPurchased:(SKPaymentTransaction*)transaction
{
   NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
   [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
   [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

   NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
   NSData* receipt = [NSData dataWithContentsOfURL:receiptURL];

   NSDictionary* payload = @{
      @"purchase_time" : [formatter stringFromDate:transaction.transactionDate],
      @"product_id" : transaction.payment.productIdentifier,
      @"purchase_token" : [receipt base64EncodedStringWithOptions:0]
   };

   // TODO: What should really happen here is an object that implements SKProductsRequestDelegate
   //       that has all the context for the purchase, instead of using the NSDictionaries.
   [self.priceInfoCompleteDictionary setValue:[NSNumber numberWithBool:NO]
                                       forKey:transaction.payment.productIdentifier];

   SKProductsRequest* req = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObject:transaction.payment.productIdentifier]];
   req.delegate = self;
   [req start];

   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      BOOL stillWaiting = YES;
      do
      {
         sleep(1);
         NSNumber* b = [self.priceInfoCompleteDictionary valueForKey:transaction.payment.productIdentifier];
         stillWaiting = ![b boolValue];
      } while(stillWaiting);

      NSMutableDictionary* fullPayload = [NSMutableDictionary dictionaryWithDictionary:payload];
      [fullPayload addEntriesFromDictionary:[self.priceInfoDictionary valueForKey:transaction.payment.productIdentifier]];
      [self.requestThread addRequestForService:TeakRequestServicePost
                                    atEndpoint:@"/me/purchase"
                                   usingMethod:TeakRequestTypePOST
                                   withPayload:fullPayload
                                   andCallback:nil];
   });
}

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response
{
   if(response.products.count > 0)
   {
      SKProduct* product = [response.products objectAtIndex:0];
      NSLocale* priceLocale = product.priceLocale;
      NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
      NSDecimalNumber* price = product.price;
      [self.priceInfoDictionary setValue:@{
                                           @"price_currency_code" : currencyCode,
                                           @"price_float" : price
                                           }
                                  forKey:product.productIdentifier];
      [self.priceInfoCompleteDictionary setValue:[NSNumber numberWithBool:YES]
                                          forKey:product.productIdentifier];
   }
}

- (void)transactionFailed:(SKPaymentTransaction*)transaction
{
   NSString* errorString = @"unknown";
   switch(transaction.error.code)
   {
      case SKErrorClientInvalid:
         errorString = @"client_invalid";
         break;
      case SKErrorPaymentCancelled:
         errorString = @"payment_canceled";
         break;
      case SKErrorPaymentInvalid:
         errorString = @"payment_invalid";
         break;
      case SKErrorPaymentNotAllowed:
         errorString = @"payment_not_allowed";
         break;
      case SKErrorStoreProductNotAvailable:
         errorString = @"store_product_not_available";
         break;
      default:
         break;
   }

   NSDictionary* payload = @{
      @"product_id" : transaction.payment.productIdentifier,
      @"error_string" : errorString
   };

   [self.requestThread addRequestForService:TeakRequestServiceMetrics
                                 atEndpoint:@"/me/purchase"
                                usingMethod:TeakRequestTypePOST
                                withPayload:payload
                                andCallback:nil];
}

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions
{
   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Lifecycle - paymentQueue:updatedTransactions:");
   }

   for(SKPaymentTransaction* transaction in transactions)
   {
      switch(transaction.transactionState)
      {
         case SKPaymentTransactionStatePurchased:
            [self transactionPurchased:transaction];
            break;
         case SKPaymentTransactionStateFailed:
            [self transactionFailed:transaction];
            break;
         default:
            break;
      }
   }
}

@end

NSString* URLEscapedString(NSString* inString)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
   return (NSString*)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)inString, NULL, (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8));
#pragma clang diagnostic pop
}
