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
#import "TeakIAPMetric.h"
#import "TeakCache.h"
#import "TeakRequestThread.h"

#define kPushTokenUserDefaultsKey @"TeakPushToken"
#define kTeakVersion @"1.0"

NSString* const TeakNotificationAvailable = @"TeakNotifiacationAvailableId";

extern void Teak_Plant(Class appDelegateClass, NSString* appSecret);

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
   [Teak sharedInstance].appId = appId;
   [Teak sharedInstance].appSecret = appSecret;
   Teak_Plant(appDelegateClass, appSecret);
}

- (void)identifyUser:(NSString*)userId
{
   self.userId = userId;
   [self.dependentOperationQueue addOperation:self.userIdOperation];
}

- (void)setFacebookAccessToken:(NSString*)accessToken
{
   self.fbAccessToken = accessToken;
   [self.dependentOperationQueue addOperation:self.facebookAccessTokenOperation];
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

#if DEBUG
      self.enableDebugOutput = YES;
#else
      self.enableDebugOutput = NO;
#endif

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
         NSLog(@"Unable to create Carrot request thread.");
         return nil;
      }

      // Set up some parameters
      NSOperatingSystemVersion systemVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
      self.sdkVersion = kTeakVersion;
      self.sdkPlatform = [NSString stringWithFormat:@"ios_%ld.%ld.%ld",
                          (long)systemVersion.majorVersion,
                          (long)systemVersion.minorVersion,
                          (long)systemVersion.patchVersion];
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

}

- (void)identifyUser
{
   NSTimeZone* timeZone = [NSTimeZone localTimeZone];//[NSTimeZone timeZoneWithName:@"Europe/Berlin"];
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
   }
   if(self.launchedFromTeakNotifId != nil)
   {
      [payload setObject:self.launchedFromTeakNotifId forKey:@"teak_notif_id"];
   }
   if(self.fbAccessToken != nil)
   {
      [payload setObject:self.fbAccessToken forKey:@"access_token"];
   }

   // Happy path logging
   if(self.enableDebugOutput)
   {
      NSLog(@"[Teak] Identifying user: %@", payload);
   }

   // User identified
   self.userIdentifiedThisSession = YES;

   [self.requestThread addRequestForService:TeakRequestServiceAuth
                                 atEndpoint:[NSString stringWithFormat:@"/games/%@/users.json", self.appId]
                                usingMethod:TeakRequestTypePOST
                                withPayload:payload];
}

- (void)sendHeartbeat
{
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
   [NSURLConnection sendSynchronousRequest:request
                         returningResponse:nil
                                     error:nil];
}

- (BOOL)handleOpenURL:(NSURL*)url
{
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

   // User input dependent operations
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

   return NO;
}

- (void)beginApplicationSession:(UIApplication*)application
{
   // Get advertising info
   self.advertisingTrackingLimited = [NSNumber numberWithBool:![ASIdentifierManager sharedManager].advertisingTrackingEnabled];
   self.advertisingIdentifier = [[ASIdentifierManager sharedManager].advertisingIdentifier UUIDString];

   // Reset session-based things
   self.userIdentifiedThisSession = NO;

   // Configure NSOperation chains
   self.serviceConfigurationOperation = [NSBlockOperation blockOperationWithBlock:^{
      [[Teak sharedInstance] configure];
   }];

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

   // Heartbeat needs services and user id, same with request thread
   self.liveConnectionOperation = [NSBlockOperation blockOperationWithBlock:^{
      // TODO: Check if online
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
}

- (void)endApplicationSession:(UIApplication*)application
{
   // Cancel the heartbeat
   dispatch_source_cancel(self.heartbeat);

   // Stop request thread
   [self.requestThread stop];

   // Clear out operations dependent on user input
   self.userIdOperation = nil;
   self.facebookAccessTokenOperation = nil;
}

- (void)setDevicePushToken:(NSData*)deviceToken
{
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
   }
}

- (void)configure
{
   NSString* urlString = [NSString stringWithFormat:@"https://%@/services.json?sdk_version=%@&sdk_platform=%@&game_id=%@&app_version=%@",
                          kTeakServicesHostname,
                          URLEscapedString(self.sdkVersion),
                          URLEscapedString(self.sdkPlatform),
                          URLEscapedString(self.appId),
                          URLEscapedString(self.appVersion)];
   NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                        timeoutInterval:120];
   NSError* error = nil;
   NSData* data = [NSURLConnection sendSynchronousRequest:request
                                        returningResponse:nil
                                                    error:&error];
   if(error)
   {
      NSLog(@"[Teak] Unable to perform services discovery for Teak. Teak is in offline mode.\n%@", error);
   }
   else
   {
      NSDictionary* services = [NSJSONSerialization JSONObjectWithData:data
                                                               options:kNilOptions
                                                                 error:&error];
      if(error)
      {
         NSLog(@"[Teak] Unable to perform services discovery for Teak. Teak is in offline mode.\n%@", error);
      }
      else
      {
         self.postHostname = [services objectForKey:@"post"] == [NSNull null] ? nil : [services objectForKey:@"post"];
         self.authHostname = [services objectForKey:@"auth"] == [NSNull null] ? nil : [services objectForKey:@"auth"];
         self.metricsHostname = [services objectForKey:@"metrics"] == [NSNull null] ? nil : [services objectForKey:@"metrics"];
         if(self.enableDebugOutput)
         {
            NSLog(@"[Teak] Services discovery complete: %@", services);
         }
      }
   }
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo
{
   if(application.applicationState == UIApplicationStateInactive ||
      application.applicationState == UIApplicationStateBackground)
   {
      // App was opened via push notification
      NSLog(@"App opened via push: %@", userInfo);
   }
   else
   {
      // Push notification received while app was in foreground
      NSLog(@"Foreground push received: %@", userInfo);
   }

   [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAvailable
                                                       object:self
                                                     userInfo:userInfo];
}

- (void)transactionPurchased:(SKPaymentTransaction*)transaction
{
   NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
   [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
   [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

   NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
   NSData* receipt = [NSData dataWithContentsOfURL:receiptURL];

   NSDictionary* payload = @{
      @"app_id" : self.appId,
      @"user_id" : self.userId,
      @"network_id" : [NSNumber numberWithInt:2],
      @"happened_at" : [formatter stringFromDate:transaction.transactionDate],
      @"product_name" : transaction.payment.productIdentifier,
      @"platform_id" : [receipt base64EncodedStringWithOptions:0]
   };

   [TeakIAPMetric sendTransaction:transaction withPayload:payload];
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
      @"app_id" : self.appId,
      @"user_id" : self.userId,
      @"network_id" : [NSNumber numberWithInt:2],
      @"happened_at" : [formatter stringFromDate:transaction.transactionDate],
      @"product_name" : transaction.payment.productIdentifier,
      @"platform_id" : transaction.transactionIdentifier,
      @"purchase_status" : errorString
   };

   [TeakIAPMetric sendTransaction:transaction withPayload:payload];
}

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions
{
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
   return (NSString*)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)inString, NULL, (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8));
}
