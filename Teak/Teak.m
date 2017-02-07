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
#import "TeakRequest.h"

#import "TeakNotification.h"
#import "TeakReward.h"
#import "TeakVersion.h"

#define LOG_TAG "Teak"

NSString* const TeakNotificationAppLaunch = @"TeakNotificationAppLaunch";

// FB SDK 3.x
NSString* const TeakFBSessionDidBecomeOpenActiveSessionNotification = @"com.facebook.sdk:FBSessionDidBecomeOpenActiveSessionNotification";

// FB SDK 4.x
NSString* const TeakFBSDKAccessTokenDidChangeNotification = @"com.facebook.sdk.FBSDKAccessTokenData.FBSDKAccessTokenDidChangeNotification";
NSString* const TeakFBSDKAccessTokenDidChangeUserID = @"FBSDKAccessTokenDidChangeUserID";
NSString* const TeakFBSDKAccessTokenChangeNewKey = @"FBSDKAccessToken";
NSString* const TeakFBSDKAccessTokenChangeOldKey = @"FBSDKAccessTokenOld";

extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);
extern BOOL TeakLink_HandleDeepLink(NSString* deepLink);

Teak* _teakSharedInstance;

@interface Teak () <SKPaymentTransactionObserver>
- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions;
@end

typedef void (^TeakProductRequestCallback)(NSDictionary* priceInfo, SKProductsResponse* response);

@interface TeakProductRequest : NSObject<SKProductsRequestDelegate>
@property (copy, nonatomic) TeakProductRequestCallback callback;
@property (strong, nonatomic) SKProductsRequest* productsRequest;

+ (TeakProductRequest*)productRequestForSku:(NSString*)sku callback:(TeakProductRequestCallback)callback;

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response;
@end

@implementation Teak

+ (Teak*)sharedInstance {
   return _teakSharedInstance;
}

+ (void)initForApplicationId:(NSString*)appId withClass:(Class)appDelegateClass andApiKey:(NSString*)apiKey {
   Teak_Plant(appDelegateClass, appId, apiKey);
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
   if (actionId == nil || actionId.length == 0) {
      TeakLog(@"actionId can not be nil or empty for trackEvent(), ignoring.");
      return;
   }

   if ((objectInstanceId == nil || objectInstanceId.length == 0) &&
       (objectTypeId == nil || objectTypeId.length == 0)) {
      TeakLog(@"objectTypeId can not be nil or empty if objectInstanceId is present for trackEvent(), ignoring.");
      return;
   }

   [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
      NSDictionary* payload = @{
         @"action_type" : actionId,
         @"object_type" : objectTypeId,
         @"object_instance_id" : objectInstanceId
      };
      TeakRequest* request = [[TeakRequest alloc]
                              initWithSession:session
                              forEndpoint:@"/me/events"
                              withPayload:payload
                              callback:nil];
      [request send];
   }];
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

      TeakDebugLog(@"%@", self.appConfiguration);

      // Device Configuration
      self.deviceConfiguration = [[TeakDeviceConfiguration alloc] initWithAppConfiguration:self.appConfiguration];
      if (self.deviceConfiguration == nil) {
         TeakLog(@"DeviceConfiguration is nil.");
         return nil;
      }

      TeakDebugLog(@"%@", self.deviceConfiguration);

      // TODO: Print bug report info

      // TODO: RemoteConfiguration event listeners

      // Set up SDK Raven
      self.sdkRaven = [TeakRaven ravenForTeak:self];

      // Register default purchase deep link
      [TeakLink registerRoute:@"/teak_internal/store/:arg0" onObject:self name:@"" description:@"" selector:@selector(launchDefaultPurchaseFlowForSku:)];
   }
   return self;
}

- (void)dealloc {
   [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
   [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)fbAccessTokenChanged_4x:(NSNotification*)notification
{
   id newAccessToken = [notification.userInfo objectForKey:TeakFBSDKAccessTokenChangeNewKey];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
   self.fbAccessToken = [newAccessToken performSelector:sel_getUid("tokenString")];
#pragma clang diagnostic pop
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
}


// TODO: iOS 9 added this delegate method, deprecated the other one
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url options:(NSDictionary<NSString *,id>*)options {
   TeakDebugLog(@"%@", url);

   if (url != nil) {
      return [self handleDeepLink:url];
   }

   return NO;
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation {
   TeakDebugLog(@"%@", url);

   if (url != nil) {
      return [self handleDeepLink:url];
   }

   return NO;
}

- (BOOL)handleDeepLink:(nonnull NSURL*)url {
   // Attribution
   [TeakSession didLaunchFromDeepLink:url.absoluteString appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];

   // Check URL scheme to see if it matches the set we support
   for (NSString* scheme in self.appConfiguration.urlSchemes) {
      if ([scheme isEqualToString:url.scheme]) {
         NSString* matchString = [NSString stringWithFormat:@"/%@%@", url.host, url.path];
         return TeakLink_HandleDeepLink(matchString);
      }
   }

   return NO;
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
   // Facebook SDKs
   Class fb4xClass = NSClassFromString(@"FBSDKProfile");
   Class fb3xClass = NSClassFromString(@"FBSession");
   @try {
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
         if(fb4xClass != nil) TeakLog(@"Using Facebook SDK v4.x");
         else if(fb3xClass != nil) TeakLog(@"Using Facebook SDK v3.x");
         else TeakLog(@"Facebook SDK not detected");
      }
   } @catch (NSException* exception) {
      // I don't know
      TeakLog(@"Exception working with Facebook SDK: %@", exception);
   }

   // If the app was not running, we need to check these and invoke them afterwards
   if (launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
      [self application:application didReceiveRemoteNotification:launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]];
   } else if(launchOptions[UIApplicationLaunchOptionsURLKey]) {
      [self application:application openURL:launchOptions[UIApplicationLaunchOptionsURLKey] sourceApplication:launchOptions[UIApplicationLaunchOptionsSourceApplicationKey] annotation:launchOptions[UIApplicationLaunchOptionsAnnotationKey]];
   }

   // Set up listeners
   [[SKPaymentQueue defaultQueue] addTransactionObserver:self];

   // Call 'applicationDidBecomeActive:' to hit the code in there
   [self applicationDidBecomeActive:application];

   return NO;
}

- (void)applicationDidBecomeActive:(UIApplication*)application {
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

   [TeakSession applicationDidBecomeActive:application appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];
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
   TeakDebugLog(@"%@", userInfo);

   NSDictionary* aps = [userInfo objectForKey:@"aps"];
   NSString* teakNotifId = NSStringOrNilFor([aps objectForKey:@"teakNotifId"]);

   if (teakNotifId != nil) {
      TeakNotification* notif = [[TeakNotification alloc] initWithDictionary:aps];

      if (notif != nil) {
         if (application.applicationState == UIApplicationStateInactive || application.applicationState == UIApplicationStateBackground) {
            // App was opened via push notification
            TeakDebugLog(@"App Opened from Teak Notification %@", notif);

            [TeakSession didLaunchFromTeakNotification:teakNotifId
                                      appConfiguration:self.appConfiguration
                                   deviceConfiguration:self.deviceConfiguration];

            if (notif.teakRewardId != nil) {
               TeakReward* reward = [TeakReward rewardForRewardId:notif.teakRewardId];
               if (reward != nil) {
                  __weak TeakReward* weakReward = reward;
                  reward.onComplete = ^() {
                     NSDictionary* teakUserInfo = @{
                        @"teakReward" : weakReward.json == nil ? [NSNull null] : weakReward.json,
                        @"teakDeepLink" : notif.teakDeepLink == nil ? [NSNull null] : notif.teakDeepLink
                     };
                     [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                                         object:self
                                                                       userInfo:teakUserInfo];
                  };
               } else {
                  NSDictionary* teakUserInfo = @{
                     @"teakDeepLink" : notif.teakDeepLink == nil ? [NSNull null] : notif.teakDeepLink
                  };
                  [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                                      object:self
                                                                    userInfo:teakUserInfo];
               }
            } else {
               NSDictionary* teakUserInfo = @{
                  @"teakDeepLink" : notif.teakDeepLink == nil ? [NSNull null] : notif.teakDeepLink
               };
               [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                                   object:self
                                                                 userInfo:teakUserInfo];
            }

            // If there's a deep link, see if Teak handles it. Otherwise use openURL.
            if (notif.teakDeepLink != nil) {
               if (![self handleDeepLink:notif.teakDeepLink] && [application canOpenURL:notif.teakDeepLink]) {

                  // iOS 10+
                  if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
                     [application openURL:notif.teakDeepLink options:@{} completionHandler:^(BOOL success) {
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
            TeakDebugLog(@"Teak Notification received in foreground %@", notif);
         }
      }
   } else {
      TeakDebugLog(@"Non-Teak push notification, ignored.");
   }
}

- (void)transactionPurchased:(SKPaymentTransaction*)transaction {
   if (transaction == nil || transaction.payment == nil || transaction.payment.productIdentifier == nil) return;

   teak_try {
      teak_log_breadcrumb(@"Building date formatter");
      NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
      [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
      [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

      teak_log_breadcrumb(@"Getting info from App Store receipt");
      NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
      NSData* receipt = [NSData dataWithContentsOfURL:receiptURL];

      [TeakProductRequest productRequestForSku:transaction.payment.productIdentifier callback:^(NSDictionary* priceInfo, SKProductsResponse* unused) {
         teak_log_breadcrumb(@"Building payload");
         NSMutableDictionary* fullPayload = [NSMutableDictionary dictionaryWithDictionary:@{
            @"purchase_time" : [formatter stringFromDate:transaction.transactionDate],
            @"product_id" : transaction.payment.productIdentifier,
            @"purchase_token" : [receipt base64EncodedStringWithOptions:0]
         }];

         if (priceInfo != nil) {
            [fullPayload addEntriesFromDictionary:priceInfo];
         }

         [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
            TeakRequest* request = [[TeakRequest alloc]
                                    initWithSession:session
                                    forEndpoint:@"/me/purchase"
                                    withPayload:fullPayload
                                    callback:nil];
            [request send];
         }];
      }];
   }
   teak_catch_report
}

- (void)transactionFailed:(SKPaymentTransaction*)transaction {
   if (transaction == nil || transaction.payment == nil) return;

   teak_try {
      teak_log_breadcrumb(@"Determining status");
      NSString* errorString = @"unknown";
      switch (transaction.error.code) {
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

      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
         TeakRequest* request = [[TeakRequest alloc]
                                 initWithSession:session
                                 forEndpoint:@"/me/purchase"
                                 withPayload:payload
                                 callback:nil];
         [request send];
      }];
   }
   teak_catch_report
}

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions {
   for (SKPaymentTransaction* transaction in transactions) {
      switch (transaction.transactionState) {
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

- (void)launchDefaultPurchaseFlowForSku:(NSString*)sku {
   [TeakProductRequest productRequestForSku:sku callback:^(NSDictionary* unused, SKProductsResponse* response) {
      if(response.products.count > 0)
      {
         SKProduct* product = [response.products objectAtIndex:0];
         NSLocale* priceLocale = product.priceLocale;
         NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
         NSDecimalNumber* price = product.price;
         NSLog(@"Purchase info: %@ - %@ - %@", product.productIdentifier, currencyCode, price);

         SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
         payment.quantity = 1;
         [[SKPaymentQueue defaultQueue] addPayment:payment];
      }
   }];
}

@end

@implementation TeakProductRequest

+ (nonnull NSMutableArray*)activeProductRequests {
   static NSMutableArray* array = nil;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      array = [[NSMutableArray alloc] init];
   });
   return array;
}

+ (TeakProductRequest*)productRequestForSku:(NSString*)sku callback:(TeakProductRequestCallback)callback {
   TeakProductRequest* ret = [[TeakProductRequest alloc] init];
   ret.callback = callback;
   ret.productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObject:sku]];
   ret.productsRequest.delegate = ret;
   [ret.productsRequest start];
   [[TeakProductRequest activeProductRequests] addObject:ret];
   return ret;
}

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response {
   if(response != nil && response.products != nil && response.products.count > 0) {
      teak_try {
         teak_log_breadcrumb(@"Collecting product response info");
         SKProduct* product = [response.products objectAtIndex:0];
         NSLocale* priceLocale = product.priceLocale;
         NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
         NSDecimalNumber* price = product.price;

         self.callback(@{@"price_currency_code" : currencyCode, @"price_float" : price}, response);
      }
      teak_catch_report
   } else {
      self.callback(@{}, nil);
   }
   [[TeakProductRequest activeProductRequests] removeObject:self];
}

- (NSString*)description {
   return [NSString stringWithFormat:@"<%@: %p> products-request: %@", NSStringFromClass([self class]), self, self.productsRequest];
}

@end
