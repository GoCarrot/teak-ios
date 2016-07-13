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

#import "TeakDebugConfiguration.h"
#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakSession.h"

#import "TeakCache.h"
#import "TeakRequestThread.h"
#import "TeakNotification.h"
#import "TeakVersion.h"

#define LOG_TAG "Teak"

NSString* const TeakNotificationAvailable = @"TeakNotifiacationAvailableId";
NSString* const TeakNotificationAppLaunch = @"TeakNotificationAppLaunch";

// FB SDK 3.x
NSString* const TeakFBSessionDidBecomeOpenActiveSessionNotification = @"com.facebook.sdk:FBSessionDidBecomeOpenActiveSessionNotification";

// FB SDK 4.x
NSString* const TeakFBSDKAccessTokenDidChangeNotification = @"com.facebook.sdk.FBSDKAccessTokenData.FBSDKAccessTokenDidChangeNotification";
NSString* const TeakFBSDKAccessTokenDidChangeUserID = @"FBSDKAccessTokenDidChangeUserID";
NSString* const TeakFBSDKAccessTokenChangeNewKey = @"FBSDKAccessToken";
NSString* const TeakFBSDKAccessTokenChangeOldKey = @"FBSDKAccessTokenOld";

extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);

Teak* _teakSharedInstance;

@interface Teak () <SKPaymentTransactionObserver, SKProductsRequestDelegate>

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions;

@end

@implementation Teak

+ (Teak*)sharedInstance {
   return _teakSharedInstance;
}

+ (void)initForApplicationId:(NSString*)appId withClass:(Class)appDelegateClass andSecret:(NSString*)appSecret; {
   Teak_Plant(appDelegateClass, appId, appSecret);
}

- (void)identifyUser:(NSString*)userIdentifier {
   TeakLog("identifyUser(): %@", userIdentifier);

   if (userIdentifier == nil || userIdentifier.length == 0) {
      TeakLog("User identifier can not be null or empty.");
      return;
   }

   [self.sdkRaven setUserValue:userIdentifier forKey:@"id"];
   [TeakSession setUserId:userIdentifier];
}

- (void)trackEventWithActionId:(NSString*)actionId forObjectTypeId:(NSString*)objectTypeId andObjectInstanceId:(NSString*)objectInstanceId
{
   // TODO: Dear god, past-Pat, do some input validation...
   NSDictionary* payload = @{
      @"action_type" : actionId,
      @"object_type" : objectTypeId,
      @"object_instance_id" : objectInstanceId
   };

   // TODO: When user id is ready
   [self.requestThread addRequestForService:TeakRequestServiceMetrics
                                 atEndpoint:@"/me/events"
                                withPayload:payload
                                andCallback:nil];
}

////////////////////////////////////////////////////////////////////////////////

- (id)initWithApplicationId:(NSString*)appId andSecret:(NSString*)appSecret {
   self = [super init];
   if(self) {
      // Output version first thing
      self.sdkVersion = [NSString stringWithUTF8String: TEAK_SDK_VERSION];
      TeakLog(@"iOS SDK Version: %@", self.sdkVersion);

      if ([appId length] == 0) {
         TeakLog(@"appId cannot be null or empty");
         return nil;
      }

      if ([appSecret length] == 0) {
         TeakLog(@"appSecret cannot be null or empty");
         return nil;
      }

      // TODO: Adobe AIR Version print

      // Debug Configuration
      self.debugConfiguration = [[TeakDebugConfiguration alloc] init];
      self.enableDebugOutput = self.debugConfiguration.forceDebug;

      // App Configuration
      self.appConfiguration = [[TeakAppConfiguration alloc] initWithAppId:appId apiKey:appSecret];
      if (self.appConfiguration == nil) {
         TeakLog(@"AppConfiguration is nil.");
         return nil;
      }
      self.enableDebugOutput |= !self.appConfiguration.isProduction;

      if (self.enableDebugOutput) {
         TeakLog(@"%@", self.appConfiguration);
      }

      // Device Configuration
      self.deviceConfiguration = [[TeakDeviceConfiguration alloc] initWithAppConfiguration:self.appConfiguration];
      if (self.deviceConfiguration == nil) {
         TeakLog(@"DeviceConfiguration is nil.");
         return nil;
      }

      if (self.enableDebugOutput) {
         TeakLog(@"%@", self.deviceConfiguration);

         // TODO: Print bug report info
      }

      // TODO: RemoteConfiguration event listeners

      // Set up SDK Raven
      self.sdkRaven = [TeakRaven ravenForTeak:self];

      // Create cache
      self.cache = [[TeakCache alloc] init];
      if(!self.cache) {
         TeakLog(@"Unable to create Teak cache. Teak is disabled.");
         return nil;
      }

      // --

      // Allocations
      self.priceInfoCompleteDictionary = [[NSMutableDictionary alloc] init];
      self.priceInfoDictionary = [[NSMutableDictionary alloc] init];

      // Dependent operations
      self.dependentOperationQueue = [[NSOperationQueue alloc] init];
   }
   return self;
}

- (void)dealloc {
   [[NSNotificationCenter defaultCenter] removeObserver:self];
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


// TODO: iOS 9 added this delegate method, deprecated the other one
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url options:(NSDictionary<NSString *,id>*)options {
   if (self.enableDebugOutput) {
      TeakLog(@"%@", url);
   }

   if (url != nil && [self handleDeepLink:url]) {
      [TeakSession didLaunchFromDeepLink:url.absoluteString appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];
      return YES;
   }

   return NO;
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation {
   if (self.enableDebugOutput) {
      TeakLog(@"%@", url);
   }

   if (url != nil && [self handleDeepLink:url]) {
      [TeakSession didLaunchFromDeepLink:url.absoluteString appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];
      return YES;
   }

   return NO;
}

- (BOOL)handleDeepLink:(nonnull NSURL*)url {
   if (YES) { // TODO: Talk to Unity, et. al. to see if we can handle this deep link
      // TODO: Deep link navigation
      return YES;
   }
   return NO;
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
   // Facebook SDKs
   Class fb4xClass = NSClassFromString(@"FBSDKProfile");
   Class fb3xClass = NSClassFromString(@"FBSession");
   if (fb4xClass != nil) {
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
   } else if (fb3xClass != nil) {
      // accessTokenData
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(fbAccessTokenChanged_3x:)
                                                   name:TeakFBSessionDidBecomeOpenActiveSessionNotification
                                                 object:nil];
   }

   if (self.enableDebugOutput) {
      if(fb4xClass != nil) TeakLog(@"Using Facebook SDK v4.x");
      else if(fb3xClass != nil) TeakLog(@"Using Facebook SDK v3.x");
      else TeakLog(@"Facebook SDK not detected");
   }

   // If the app was not running, we need to check these and invoke them afterwards
   if (launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
      [self application:application didReceiveRemoteNotification:launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]];
   } else if(launchOptions[UIApplicationLaunchOptionsURLKey]) {
      [self application:application openURL:launchOptions[UIApplicationLaunchOptionsURLKey] sourceApplication:launchOptions[UIApplicationLaunchOptionsSourceApplicationKey] annotation:launchOptions[UIApplicationLaunchOptionsAnnotationKey]];
   }

   // Set up listeners
   [[SKPaymentQueue defaultQueue] addTransactionObserver:self];

   // Call 'applicationWillEnterForeground:' to hit the code in there
   [self applicationWillEnterForeground:application];

   return NO;
}

- (void)applicationWillEnterForeground:(UIApplication*)application {
   // If iOS 8+ then check first to see if we have permission to change badge, otherwise
   // just go ahead and change it.
   if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
      UIUserNotificationSettings* notificationSettings = [application currentUserNotificationSettings];
      if (notificationSettings.types & UIUserNotificationTypeBadge) {
         [application setApplicationIconBadgeNumber:0];
      }
   } else {
      [application setApplicationIconBadgeNumber:0];
   }

   [TeakSession applicationWillEnterForeground:application appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];
}

- (void)applicationWillResignActive:(UIApplication*)application {
   [TeakSession applicationWillResignActive:application appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];
}

- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
   [application registerForRemoteNotifications];
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
   if (deviceToken == nil) {
      TeakLog(@"Got nil deviceToken. Push is disabled.");
      return;
   }

   NSString* deviceTokenString = [[[[deviceToken description]
                                    stringByReplacingOccurrencesOfString:@"<" withString:@""]
                                    stringByReplacingOccurrencesOfString:@">" withString:@""]
                                    stringByReplacingOccurrencesOfString:@" " withString:@""];
   if (deviceTokenString != nil) {
      [self.deviceConfiguration assignPushToken:deviceTokenString];
   } else {
      TeakLog(@"Got nil deviceTokenString. Push is disabled.");
   }
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
   TeakLog(@"Failed to register for push notifications: %@", [error localizedDescription]);
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo {
   if (self.enableDebugOutput) {
      TeakLog(@"%@", userInfo);
   }

   NSDictionary* aps = [userInfo objectForKey:@"aps"];
   NSString* teakNotifId = NSStringOrNilFor([aps objectForKey:@"teakNotifId"]);

   if (teakNotifId != nil) {
      TeakNotification* notif = [TeakNotification notificationFromDictionary:aps];

      if (application.applicationState == UIApplicationStateInactive || application.applicationState == UIApplicationStateBackground) {
         // App was opened via push notification
         if (self.enableDebugOutput) {
            TeakLog(@"App Opened from Teak Notification %@", notif);
         }

         [TeakSession didLaunchFromTeakNotification:teakNotifId appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];

         if (notif.deepLink != nil) {
            [self handleDeepLink:notif.deepLink];
         }

         [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                             object:self
                                                           userInfo:userInfo];
      } else {
         // Push notification received while app was in foreground
         if (self.enableDebugOutput) {
            TeakLog(@"Teak Notification received in foreground %@", notif);
         }
      }

      [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAvailable
                                                          object:self
                                                        userInfo:userInfo];
   } else {
      if (self.enableDebugOutput) {
         TeakLog(@"Non-Teak push notification, ignored.");
      }
   }
}

- (void)transactionPurchased:(SKPaymentTransaction*)transaction
{
   NSDictionary* payload;
   teak_try
   {
      teak_log_breadcrumb(@"Building date formatter");
      NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
      [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
      [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

      teak_log_breadcrumb(@"Getting info from App Store receipt");
      NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
      NSData* receipt = [NSData dataWithContentsOfURL:receiptURL];

      teak_log_breadcrumb(@"Building payload");
      payload = @{
         @"purchase_time" : [formatter stringFromDate:transaction.transactionDate],
         @"product_id" : transaction.payment.productIdentifier,
         @"purchase_token" : [receipt base64EncodedStringWithOptions:0]
      };

      teak_log_data_breadcrumb(@"Payload built, submitting SKProductsRequest", payload);

      // TODO: What should really happen here is an object that implements SKProductsRequestDelegate
      //       that has all the context for the purchase, instead of using the NSDictionaries.
      [self.priceInfoCompleteDictionary setValue:[NSNumber numberWithBool:NO]
                                          forKey:transaction.payment.productIdentifier];

      SKProductsRequest* req = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObject:transaction.payment.productIdentifier]];
      req.delegate = self;
      [req start];
   }
   teak_catch_report

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
      
      // TODO: When user id is ready
      [self.requestThread addRequestForService:TeakRequestServicePost
                                    atEndpoint:@"/me/purchase"
                                   withPayload:fullPayload
                                   andCallback:nil];
   });
}

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response
{
   if(response.products.count > 0)
   {
      teak_try
      {
         teak_log_breadcrumb(@"Collecting product response info");
         SKProduct* product = [response.products objectAtIndex:0];
         NSLocale* priceLocale = product.priceLocale;
         NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
         NSDecimalNumber* price = product.price;

         teak_log_data_breadcrumb(@"Assigning product info", @{@"sku" : product.productIdentifier});
         [self.priceInfoDictionary setValue:@{
                                              @"price_currency_code" : currencyCode,
                                              @"price_float" : price
                                              }
                                     forKey:product.productIdentifier];
         [self.priceInfoCompleteDictionary setValue:[NSNumber numberWithBool:YES]
                                             forKey:product.productIdentifier];
      }
      teak_catch_report
   }
}

- (void)transactionFailed:(SKPaymentTransaction*)transaction
{
   teak_try
   {
      teak_log_breadcrumb(@"Determining status");
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
      teak_log_data_breadcrumb(@"Got transaction error code", @{@"transaction.error.code" : errorString});

      NSDictionary* payload = @{
         @"product_id" : transaction.payment.productIdentifier,
         @"error_string" : errorString
      };

      teak_log_data_breadcrumb(@"Reporting purchase failed", payload);
      
      // TODO: When user id is ready
      [self.requestThread addRequestForService:TeakRequestServiceMetrics
                                    atEndpoint:@"/me/purchase"
                                   withPayload:payload
                                   andCallback:nil];
   }
   teak_catch_report
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
