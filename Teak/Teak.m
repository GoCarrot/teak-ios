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

#define kPushTokenUserDefaultsKey @"TeakPushToken"
#define kTeakVersion @"1.0"

NSString* const TeakServicesConfiguredNotification = @"TeakServicesConfiguredNotification";
NSString* const TeakPushTokenReceived = @"TeakPushTokenReceived";
NSString* const TeakUserIdAvailableNotification = @"TeakUserIdAvailableNotification";
NSString* const TeakAccessTokenAvailableNotification = @"TeakAccessTokenAvailableNotification";

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
      /*
      if(![NSError instancesRespondToSelector:@selector(fberrorShouldNotifyUser)])
      {
         NSException *exception = [NSException exceptionWithName:@"AdditionalLinkerFlagRequired"
                                                          reason:@"Use of the Carrot SDK requires adding '-ObjC' to the 'Other Linker Flags' setting of your Xcode Project. See: https://gocarrot.com/docs/ios for more information."
                                                        userInfo:nil];
         @throw exception;
      }*/

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
   [[NSNotificationCenter defaultCenter] postNotificationName:TeakUserIdAvailableNotification object:self];
}

- (void)setFacebookAccessToken:(NSString*)accessToken
{
   self.fbAccessToken = accessToken;
   [[NSNotificationCenter defaultCenter] postNotificationName:TeakAccessTokenAvailableNotification object:self];
}

////////////////////////////////////////////////////////////////////////////////

- (void)onTeakServicesAvailable
{
   // We need the User Id in order to do the next thing
   if(self.enableDebugOutput)
   {
      NSLog(@"onTeakServicesAvailable");
   }
}

- (void)onUserIdAvailable
{
   // It would be great to have the FB Access Token and/or the Push Token
   if(self.enableDebugOutput)
   {
      NSLog(@"onUserIdAvailable");
   }

   [self identifyUser];
}

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
         NSLog(@"Unable to create Teak data path: %@.", error);
         return nil;
      }

      // Create cache
      self.cache = [TeakCache cacheWithPath:self.dataPath];
      if(!self.cache)
      {
         NSLog(@"Unable to create Teak cache.");
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
      __weak typeof(self) weakSelf = self;
      self.heartbeatQueue = dispatch_queue_create("io.teak.sdk.heartbeat", NULL);
      self.heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.heartbeatQueue);
      dispatch_source_set_event_handler(self.heartbeat, ^{ [weakSelf sendHeartbeat]; });
   }
   return self;
}

- (void)dealloc
{
   // Unregister all listeners
   [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)identifyUser
{
   NSTimeZone* timeZone = [NSTimeZone localTimeZone];//[NSTimeZone timeZoneWithName:@"Europe/Berlin"];
   float timeZoneOffset = (((float)[timeZone secondsFromGMT]) / 60.0f) / 60.0f;

   NSDictionary* knownPayload = @{
      @"api_key" : self.userId,
      @"timezone" : [NSString stringWithFormat:@"%f", timeZoneOffset],
      @"ios_ad_id" : self.advertisingIdentifier,
      @"ios_limit_ad_tracking" : self.advertisingTrackingLimited,
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
      NSLog(@"Identifying user: %@", payload);
   }

   // User identified
   self.userIdentifiedThisSession = YES;

   // Do the thing
   {
      // When successful
      dispatch_source_set_timer(self.heartbeat, dispatch_walltime(NULL, 0), 60ull * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);
      dispatch_resume(self.heartbeat);
   }
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
   [[[NSURLSession sharedSession] dataTaskWithRequest:request] resume];
}

- (BOOL)handleOpenURL:(NSURL*)url
{
   return NO;
}

- (BOOL)application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
   // Set up listeners
   [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
   
   [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(onTeakServicesAvailable)
                                                name:TeakServicesConfiguredNotification
                                              object:nil];
   [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(onUserIdAvailable)
                                                name:TeakUserIdAvailableNotification
                                              object:nil];

   return NO;
}

- (void)beginApplicationSession:(UIApplication*)application
{
   // Get advertising info
   self.advertisingTrackingLimited = [NSNumber numberWithBool:![ASIdentifierManager sharedManager].advertisingTrackingEnabled];
   self.advertisingIdentifier = [[ASIdentifierManager sharedManager].advertisingIdentifier UUIDString];

   [[Teak sharedInstance] configure];
}

- (void)endApplicationSession:(UIApplication*)application
{
   // Cancel the heartbeat
   dispatch_source_cancel(self.heartbeat);

   // Need to start a new session metric
   self.userIdentifiedThisSession = NO;
}

- (void)setDevicePushToken:(NSData*)deviceToken
{
   // TODO: Double check formatting for SNS
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

      [[NSNotificationCenter defaultCenter] postNotificationName:TeakPushTokenReceived object:self];
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
   [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
      if(error)
      {
         NSLog(@"Unable to perform services discovery for Teak. Teak is in offline mode.\n%@", error);
      }
      else
      {
         NSDictionary* services = [NSJSONSerialization JSONObjectWithData:data
                                                                  options:kNilOptions
                                                                    error:&error];
         if(error)
         {
            NSLog(@"Unable to perform services discovery for Teak. Teak is in offline mode.\n%@", error);
         }
         else
         {/*
            self.postHostname = [services objectForKey:@"post"] == [NSNull null] ? nil : [services objectForKey:@"post"];
            self.authHostname = [services objectForKey:@"auth"] == [NSNull null] ? nil : [services objectForKey:@"auth"];
            self.metricsHostname = [services objectForKey:@"metrics"] == [NSNull null] ? nil : [services objectForKey:@"metrics"];
            self.sessionId = [services objectForKey:@"session_id"] == [NSNull null] ? nil : [services objectForKey:@"session_id"];*/
            if(self.enableDebugOutput)
            {
               NSLog(@"Services discovery complete: %@", services);
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:TeakServicesConfiguredNotification object:self];
         }
      }
   }] resume];
}

- (void)transactionPurchased:(SKPaymentTransaction*)transaction
{
   NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
   [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
   [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

   NSDictionary* payload = @{
      @"app_id" : self.appId,
      @"user_id" : self.userId,
      @"network_id" : [NSNumber numberWithInt:2],
      @"happened_at" : [formatter stringFromDate:transaction.transactionDate],
      @"product_name" : transaction.payment.productIdentifier,
      @"platform_id" : transaction.transactionIdentifier
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
