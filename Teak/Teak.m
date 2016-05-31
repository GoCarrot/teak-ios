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

NSString* const TeakNotificationAvailable = @"TeakNotifiacationAvailableId";

// FB SDK 3.x
NSString *const TeakFBSessionDidBecomeOpenActiveSessionNotification = @"com.facebook.sdk:FBSessionDidBecomeOpenActiveSessionNotification";

// FB SDK 4.x
NSString *const TeakFBSDKAccessTokenDidChangeNotification = @"com.facebook.sdk.FBSDKAccessTokenData.FBSDKAccessTokenDidChangeNotification";
NSString *const TeakFBSDKAccessTokenDidChangeUserID = @"FBSDKAccessTokenDidChangeUserID";
NSString *const TeakFBSDKAccessTokenChangeNewKey = @"FBSDKAccessToken";
NSString *const TeakFBSDKAccessTokenChangeOldKey = @"FBSDKAccessTokenOld";

extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);

@interface Teak () <SKPaymentTransactionObserver>

@property (nonatomic) dispatch_queue_t heartbeatQueue;
@property (nonatomic) dispatch_source_t heartbeat;

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions;

@end

@implementation Teak

+ (Teak*)sharedInstance
{
   static Teak* sharedInstance = nil;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      sharedInstance = [[Teak alloc] init];
   });
   return sharedInstance;
}

+ (void)initForApplicationId:(NSString*)appId withClass:(Class)appDelegateClass andSecret:(NSString*)appSecret;
{
   Teak_Plant(appDelegateClass, appId, appSecret);
}

- (void)identifyUser:(NSString*)userId
{
   self.userId = userId;
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
                                withPayload:payload];
}

////////////////////////////////////////////////////////////////////////////////

- (id)init
{
   self = [super init];
   if(self)
   {
      // Load settings
      NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
      self.pushToken = [userDefaults stringForKey:kPushTokenUserDefaultsKey];

      // Check if this is production mode
      NSData* data = [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"]];
      self.isProduction = (data == nil);
      self.enableDebugOutput = self.isProduction;

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
         NSLog(@"Unable to create Teak request thread.");
         return nil;
      }

      // Set up some parameters
      self.sdkVersion = [NSString stringWithUTF8String: TEAK_SDK_VERSION];
      self.sdkPlatform = [NSString stringWithFormat:@"ios_%f",[[[UIDevice currentDevice] systemVersion] floatValue]];
      self.appVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];

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
   if(lastSessionDelta < kMergeLastSessionDeltaSeconds) return;

   NSTimeZone* timeZone = [NSTimeZone localTimeZone];
   float timeZoneOffset = (((float)[timeZone secondsFromGMT]) / 60.0f) / 60.0f;

   NSString* language = [[NSLocale preferredLanguages] objectAtIndex:0];
   NSDictionary* languageDic = [NSLocale componentsFromLocaleIdentifier:language];
   NSString* countryCode = [languageDic objectForKey:@"kCFLocaleCountryCodeKey"];
   NSString* languageCode = [languageDic objectForKey:@"kCFLocaleLanguageCodeKey"];

   NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
   [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
   [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

   NSDictionary* knownPayload = @{
      @"locale" : [NSString stringWithFormat:@"%@_%@", languageCode, countryCode],
      @"timezone" : [NSString stringWithFormat:@"%f", timeZoneOffset],
      @"ios_ad_id" : self.advertisingIdentifier,
      @"ios_limit_ad_tracking" : self.advertisingTrackingLimited,
      @"happened_at" : [formatter stringFromDate:[[NSDate alloc] init]]
   };

   // Build dependent payload.
   NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:knownPayload];
   if(self.userIdentifiedThisSession)
   {
      [payload setObject:[NSNumber numberWithBool:YES] forKey:@"do_not_track_event"];
   }
   if(self.pushToken != nil)
   {
      [payload setObject:self.pushToken forKey:@"apns_push_key"];
      [payload setObject:[NSNumber numberWithBool:self.isProduction] forKey:@"is_sandbox"];
   }
   else
   {
      [payload setObject:@"" forKey:@"apns_push_key"];
      [payload setObject:[NSNumber numberWithBool:self.isProduction] forKey:@"is_sandbox"];
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

   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Identifying user: %@", payload);
   }

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

   [self.requestThread addRequestForService:TeakRequestServiceAuth
                                 atEndpoint:[NSString stringWithFormat:@"/games/%@/users.json", self.appId]
                                usingMethod:TeakRequestTypePOST
                                withPayload:payload];
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
                          @"https://iroko.gocarrot.com/ping?game_id=%@&api_key=%@&sdk_version=%@&sdk_platform=%@&app_version=%@&buster=%@",
                          URLEscapedString(self.appId),
                          URLEscapedString(self.userId),
                          URLEscapedString(self.sdkVersion),
                          URLEscapedString(self.sdkPlatform),
                          URLEscapedString(self.appVersion),
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
   // Set up listeners
   [[SKPaymentQueue defaultQueue] addTransactionObserver:self];

   struct utsname systemInfo;
   uname(&systemInfo);
   self.deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];

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

   // Get advertising info
   self.advertisingTrackingLimited = [NSNumber numberWithBool:![ASIdentifierManager sharedManager].advertisingTrackingEnabled];
   self.advertisingIdentifier = [[ASIdentifierManager sharedManager].advertisingIdentifier UUIDString];

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
      NSLog(@"   Teak Version: %@", self.sdkVersion);
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
   NSString* teakNotifId = [aps objectForKey:@"teakNotifId"];

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
      @"appstore_name" : @"apple",
      @"purchase_time" : [formatter stringFromDate:transaction.transactionDate],
      @"product_id" : transaction.payment.productIdentifier,
      @"purchase_token" : [receipt base64EncodedStringWithOptions:0]
   };

   [self.requestThread addRequestForService:TeakRequestServicePost
                                 atEndpoint:@"/me/purchase"
                                usingMethod:TeakRequestTypePOST
                                withPayload:payload];
}

- (void)transactionFailed:(SKPaymentTransaction*)transaction
{
   NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
   [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
   [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

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
      @"appstore_name" : @"apple",
      @"purchase_time" : [formatter stringFromDate:transaction.transactionDate],
      @"product_id" : transaction.payment.productIdentifier,
      @"error_string" : errorString
   };

   [self.requestThread addRequestForService:TeakRequestServiceMetrics
                                 atEndpoint:@"/me/purchase"
                                usingMethod:TeakRequestTypePOST
                                withPayload:payload];
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
