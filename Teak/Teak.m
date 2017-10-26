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

#import <StoreKit/StoreKit.h>

#import "Teak+Internal.h"
#import <Teak/Teak.h>

#import "TeakAppConfiguration.h"
#import "TeakDebugConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRequest.h"
#import "TeakSession.h"

#import "TeakNotification.h"
#import "TeakReward.h"
#import "TeakVersion.h"

#import "PushRegistrationEvent.h"

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

@interface Teak () <SKPaymentTransactionObserver>
- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions;
@end

typedef void (^TeakProductRequestCallback)(NSDictionary* priceInfo, SKProductsResponse* response);

@interface TeakProductRequest : NSObject <SKProductsRequestDelegate>
@property (copy, nonatomic) TeakProductRequestCallback callback;
@property (strong, nonatomic) SKProductsRequest* productsRequest;

+ (TeakProductRequest*)productRequestForSku:(NSString*)sku callback:(TeakProductRequestCallback)callback;

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response;
@end

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

  [self.sdkRaven setUserValue:userIdentifier forKey:@"id"];
  [TeakSession setUserId:userIdentifier];
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

    // Debug Configuration
    self.debugConfiguration = [[TeakDebugConfiguration alloc] init];
    self.enableDebugOutput = self.debugConfiguration.forceDebug;

    // App Configuration
    self.appConfiguration = [[TeakAppConfiguration alloc] initWithAppId:appId apiKey:appSecret];
    if (self.appConfiguration == nil) {
      [NSException raise:NSObjectNotAvailableException format:@"Teak App Configuration is nil."];
      return nil;
    }
    self.enableDebugOutput |= !self.appConfiguration.isProduction;

    // Add Unity/Air SDK version if applicable
    NSMutableDictionary* sdkDict = [NSMutableDictionary dictionaryWithDictionary:@{@"ios" : self.sdkVersion}];
    if (TeakWrapperSDK != nil) {
      [sdkDict addEntriesFromDictionary:TeakWrapperSDK];
    }
    TeakVersionDict = sdkDict;

    [self.log useSdk:TeakVersionDict];
    [self.log useAppConfiguration:self.appConfiguration];

    // Device Configuration
    self.deviceConfiguration = [[TeakDeviceConfiguration alloc] initWithAppConfiguration:self.appConfiguration];
    if (self.deviceConfiguration == nil) {
      [NSException raise:NSObjectNotAvailableException format:@"Teak Device Configuration is nil."];
      return nil;
    }
    [self.log useDeviceConfiguration:self.deviceConfiguration];

    // Set up SDK Raven
    self.sdkRaven = [TeakRaven ravenForTeak:self];

    // Operation queue
    self.operationQueue = [[NSOperationQueue alloc] init];

    // Register default purchase deep link
    [TeakLink registerRoute:@"/teak_internal/store/:sku"
                       name:@""
                description:@""
                      block:^(NSDictionary* _Nonnull parameters) {
                        [TeakProductRequest productRequestForSku:parameters[@"sku"]
                                                        callback:^(NSDictionary* unused, SKProductsResponse* response) {
                                                          if (response.products.count > 0) {
                                                            SKProduct* product = [response.products objectAtIndex:0];

                                                            SKMutablePayment* payment = [SKMutablePayment paymentWithProduct:product];
                                                            payment.quantity = 1;
                                                            [[SKPaymentQueue defaultQueue] addPayment:payment];
                                                          }
                                                        }];
                      }];
  }
  return self;
}

- (void)dealloc {
  [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)fbAccessTokenChanged_4x:(NSNotification*)notification {
  id newAccessToken = [notification.userInfo objectForKey:TeakFBSDKAccessTokenChangeNewKey];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  self.fbAccessToken = [newAccessToken performSelector:sel_getUid("tokenString")];
#pragma clang diagnostic pop
}

- (void)fbAccessTokenChanged_3x:(NSNotification*)notification {
  Class fbSession = NSClassFromString(@"FBSession");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  id activeSession = [fbSession performSelector:sel_getUid("activeSession")];
  id accessTokenData = [activeSession performSelector:sel_getUid("accessTokenData")];
  self.fbAccessToken = [accessTokenData performSelector:sel_getUid("accessToken")];
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
  [TeakSession didLaunchFromDeepLink:url.absoluteString appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];

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
  if (pushEnabled) {
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

  // Set up listeners
  [[SKPaymentQueue defaultQueue] addTransactionObserver:self];

  // Call 'applicationDidBecomeActive:' to hit the code in there
  [self applicationDidBecomeActive:application];

  return NO;
}

- (void)applicationDidBecomeActive:(UIApplication*)application {
  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});

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
  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});

  [TeakSession applicationWillResignActive:application appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];
}

- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
  [application registerForRemoteNotifications];
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
  NSDictionary* aps = [userInfo objectForKey:@"aps"];
  NSString* teakNotifId = NSStringOrNilFor([aps objectForKey:@"teakNotifId"]);

  if (teakNotifId != nil) {
    TeakNotification* notif = [[TeakNotification alloc] initWithDictionary:aps];

    if (notif != nil) {
      BOOL isInBackground = application.applicationState == UIApplicationStateInactive || application.applicationState == UIApplicationStateBackground;

      // TODO: Send notification_received metric

      if (isInBackground) {
        // App was opened via push notification
        TeakLog_i(@"notification.opened", @{@"teakNotifId" : _(teakNotifId)});

        [TeakSession didLaunchFromTeakNotification:teakNotifId
                                  appConfiguration:self.appConfiguration
                               deviceConfiguration:self.deviceConfiguration];

        NSMutableDictionary* teakUserInfo = [[NSMutableDictionary alloc] init];
        if (aps[@"teakRewardId"] != nil) [teakUserInfo setValue:aps[@"teakRewardId"] forKey:@"teakRewardId"];
        if (aps[@"teakScheduleName"] != nil) [teakUserInfo setValue:aps[@"teakScheduleName"] forKey:@"teakScheduleName"];
        if (aps[@"teakCreativeName"] != nil) [teakUserInfo setValue:aps[@"teakCreativeName"] forKey:@"teakCreativeName"];
        teakUserInfo[@"incentivized"] = aps[@"teakRewardId"] == nil ? @NO : @YES;

        if (notif.teakRewardId != nil) {
          TeakReward* reward = [TeakReward rewardForRewardId:notif.teakRewardId];
          if (reward != nil) {
            __weak TeakReward* weakReward = reward;
            reward.onComplete = ^() {
              __strong TeakReward* blockReward = weakReward;

              [teakUserInfo setValue:blockReward.json == nil ? [NSNull null] : blockReward.json forKey:@"teakReward"];
              [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                                  object:self
                                                                userInfo:teakUserInfo];

              if (blockReward.json != nil) {
                [teakUserInfo addEntriesFromDictionary:blockReward.json];
                [[NSNotificationCenter defaultCenter] postNotificationName:TeakOnReward
                                                                    object:self
                                                                  userInfo:teakUserInfo];
              }
            };
          } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                                object:self
                                                              userInfo:teakUserInfo];
          }
        } else {
          [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                              object:self
                                                            userInfo:teakUserInfo];
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
                                                              NSString* iOSPath = [reply objectForKey:@"iOSPath"];
                                                              if (iOSPath != nil) {
                                                                attributionUrl = [NSURL URLWithString:[NSString stringWithFormat:@"teak%@://%@", self.appConfiguration.appId, iOSPath]];
                                                              }
                                                            }
                                                          }

                                                          // Attribution
                                                          [TeakSession didLaunchFromDeepLink:attributionUrl.absoluteString appConfiguration:self.appConfiguration deviceConfiguration:self.deviceConfiguration];

                                                          TeakLink_HandleDeepLink(attributionUrl);
                                                        }];
    [task resume];
  }

  return YES;
}

- (void)transactionPurchased:(SKPaymentTransaction*)transaction {
  if (transaction == nil || transaction.payment == nil || transaction.payment.productIdentifier == nil) return;

  teak_try {
    teak_log_breadcrumb(@"Building date formatter");
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

    teak_log_breadcrumb(@"Getting info from App Store receipt");
    NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData* receipt = [NSData dataWithContentsOfURL:receiptURL];

    [TeakProductRequest productRequestForSku:transaction.payment.productIdentifier
                                    callback:^(NSDictionary* priceInfo, SKProductsResponse* unused) {
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
  teak_catch_report;
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
  teak_catch_report;
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
  if (response != nil && response.products != nil && response.products.count > 0) {
    teak_try {
      teak_log_breadcrumb(@"Collecting product response info");
      SKProduct* product = [response.products objectAtIndex:0];
      NSLocale* priceLocale = product.priceLocale;
      NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
      NSDecimalNumber* price = product.price;

      self.callback(@{@"price_currency_code" : _(currencyCode), @"price_float" : price}, response);
    }
    teak_catch_report;
  } else {
    self.callback(@{}, nil);
  }
  [[TeakProductRequest activeProductRequests] removeObject:self];
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> products-request: %@", NSStringFromClass([self class]), self, self.productsRequest];
}

@end
