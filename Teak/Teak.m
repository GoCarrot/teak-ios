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

#import "TeakMPInt.h"

#ifndef __IPHONE_12_0
#define __IPHONE_12_0 120000
#endif

NSString* const TeakNotificationAppLaunch = @"TeakNotificationAppLaunch";
NSString* const TeakOnReward = @"TeakOnReward";
NSString* const TeakForegroundNotification = @"TeakForegroundNotification";
NSString* const TeakAdditionalData = @"TeakAdditionalData";

NSString* const TeakOptOutIdfa = @"opt_out_idfa";
NSString* const TeakOptOutPushKey = @"opt_out_push_key";
NSString* const TeakOptOutFacebook = @"opt_out_facebook";

NSString* const TeakHostname = @"gocarrot.com";

// FB SDK 3.x
NSString* const TeakFBSessionDidBecomeOpenActiveSessionNotification = @"com.facebook.sdk:FBSessionDidBecomeOpenActiveSessionNotification";

// FB SDK 4.x, 5.x
NSString* const TeakFBSDKAccessTokenDidChangeNotification = @"com.facebook.sdk.FBSDKAccessTokenData.FBSDKAccessTokenDidChangeNotification";
NSString* const TeakFBSDKAccessTokenDidChangeUserID = @"FBSDKAccessTokenDidChangeUserID";
NSString* const TeakFBSDKAccessTokenChangeNewKey = @"FBSDKAccessToken";
NSString* const TeakFBSDKAccessTokenChangeOldKey = @"FBSDKAccessTokenOld";

// AIR/Unity/etc SDK Version Extern
NSDictionary* TeakWrapperSDK = nil;

NSDictionary* TeakVersionDict = nil;

extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);

Teak* _teakSharedInstance;

@implementation Teak

+ (Teak*)sharedInstance {
  return _teakSharedInstance;
}

+ (NSURLSession*)URLSessionWithoutDelegate {
  static NSURLSession* session = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURLSessionConfiguration* sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.URLCache = nil;
    sessionConfiguration.URLCredentialStorage = nil;
    sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    sessionConfiguration.HTTPAdditionalHeaders = @{
      @"X-Teak-DeviceType" : @"API",
      @"X-Teak-Supports-Templates" : @"TRUE"
    };
    session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
  });
  return session;
}

+ (dispatch_queue_t _Nonnull)operationQueue {
  static dispatch_queue_t operationQueue = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    operationQueue = dispatch_queue_create("io.teak.sdk.operationQueue", DISPATCH_QUEUE_SERIAL);
  });
  return operationQueue;
}

+ (void)initForApplicationId:(NSString*)appId withClass:(Class)appDelegateClass andApiKey:(NSString*)apiKey {
  Teak_Plant(appDelegateClass, [appId copy], [apiKey copy]);
}

- (void)identifyUser:(NSString*)userIdentifier {
  [self identifyUser:userIdentifier withOptOutList:@[] andEmail:nil];
}

- (void)identifyUser:(NSString*)userIdentifier withEmail:(nonnull NSString*)email {
  [self identifyUser:userIdentifier withOptOutList:@[] andEmail:email];
}

- (void)identifyUser:(NSString*)userIdentifier withOptOutList:(NSArray*)optOut {
  [self identifyUser:userIdentifier withOptOutList:optOut andEmail:nil];
}

- (void)identifyUser:(NSString*)userIdentifier withOptOutList:(NSArray*)optOut andEmail:(nullable NSString*)email {
  [self processDeepLinks];

  if (userIdentifier == nil || userIdentifier.length == 0) {
    TeakLog_e(@"identify_user.error", @"User identifier can not be null or empty.");
    return;
  }

  if (optOut == nil) optOut = @[];

  TeakLog_i(@"identify_user", @{@"userId" : userIdentifier, @"optOut" : optOut});

  [UserIdEvent userIdentified:[userIdentifier copy] withOptOutList:[optOut copy] andEmail:[email copy]];
}

- (void)trackEventWithActionId:(NSString*)actionId forObjectTypeId:(NSString*)objectTypeId andObjectInstanceId:(NSString*)objectInstanceId {
  [self incrementEventWithActionId:actionId forObjectTypeId:objectTypeId andObjectInstanceId:objectInstanceId count:1];
}

- (void)incrementEventWithActionId:(nonnull NSString*)actionId forObjectTypeId:(nullable NSString*)objectTypeId andObjectInstanceId:(nullable NSString*)objectInstanceId count:(int64_t)count {
  actionId = [[actionId copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  objectTypeId = [[objectTypeId copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  objectInstanceId = [[objectInstanceId copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

  if (actionId == nil || actionId.length == 0) {
    TeakLog_e(@"track_event.error", @"actionId can not be null or empty, ignoring.");
    return;
  }

  if ((objectInstanceId != nil && objectInstanceId.length > 0) &&
      (objectTypeId == nil || objectTypeId.length == 0)) {
    TeakLog_e(@"track_event.error", @"objectTypeId can not be null or empty if objectInstanceId is present, ignoring.");
    return;
  }

  NSNumber* countAsNumber = [NSNumber numberWithUnsignedLongLong:count];
  TeakLog_i(@"track_event", @{@"actionId" : _(actionId), @"objectTypeId" : _(objectTypeId), @"objectInstanceId" : _(objectInstanceId), @"count" : countAsNumber});

  NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{@"action_type" : actionId}];
  if (objectTypeId != nil && objectTypeId.length > 0) {
    payload[@"object_type"] = objectTypeId;
  }
  if (objectInstanceId != nil && objectInstanceId.length > 0) {
    payload[@"object_instance_id"] = objectInstanceId;
  }
  payload[@"duration"] = countAsNumber;
  payload[@"count"] = @1;

  mp_int mpSumOfSquares, mpCount;
  mp_init(&mpSumOfSquares);
  mp_init(&mpCount);
  mp_set_long_long(&mpCount, count);
  mp_sqr(&mpCount, &mpSumOfSquares);
  mp_clear(&mpCount);

  payload[@"sum_of_squares"] = [TeakMPInt MPIntTakingOwnershipOf:&mpSumOfSquares];

  [TrackEventEvent trackedEventWithPayload:payload];
}

- (TeakNotificationState)notificationState {
  NSInvocationOperation* op = [self.pushState currentPushState];
  [op waitUntilFinished];

  if (op.result == [TeakPushState Denied])
    return TeakNotificationStateDisabled;
  else if (op.result == [TeakPushState Authorized])
    return TeakNotificationStateEnabled;
  else if (op.result == [TeakPushState Provisional])
    return TeakNotificationStateProvisional;
  else if (op.result == [TeakPushState NotDetermined])
    return TeakNotificationStateNotDetermined;

  return TeakNotificationStateUnknown;
}

- (BOOL)openSettingsAppToThisAppsSettings {
  return [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
}

- (void)setApplicationBadgeNumber:(int)count {
  // If iOS 8+ then check first to see if we have permission to change badge, otherwise
  // just go ahead and change it.
  if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
    UIUserNotificationSettings* notificationSettings = [[UIApplication sharedApplication] currentUserNotificationSettings];
    BOOL hasBadgeType = notificationSettings.types & UIUserNotificationTypeBadge;
    if (hasBadgeType) {
      [[UIApplication sharedApplication] setApplicationIconBadgeNumber:count];
    }
  } else {
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:count];
  }
}

- (void)setNumericAttribute:(double)value forKey:(NSString* _Nonnull)key {
  double copiedValue = value;
  NSString* copiedKey = [key copy];
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* _Nonnull session) {
    [session.userProfile setNumericAttribute:copiedValue forKey:copiedKey];
  }];
}

- (void)setStringAttribute:(NSString* _Nonnull)value forKey:(NSString* _Nonnull)key {
  NSString* copiedValue = [value copy];
  NSString* copiedKey = [key copy];
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* _Nonnull session) {
    [session.userProfile setStringAttribute:copiedValue forKey:copiedKey];
  }];
}

- (NSString*)getConfiguration:(NSString*)configuration {
  NSDictionary* configurationDict;
  if ([@"appConfiguration" isEqualToString:configuration]) {
    configurationDict = [[TeakConfiguration configuration].appConfiguration to_h];
  } else if ([@"deviceConfiguration" isEqualToString:configuration]) {
    configurationDict = [[TeakConfiguration configuration].deviceConfiguration to_h];
  }
  if (configurationDict == nil) return nil;

  NSError* error = nil;
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:configurationDict options:0 error:&error];
  if (error != nil) {
    return nil;
  }

  return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString*)getDeviceConfiguration {
  return [self getConfiguration:@"deviceConfiguration"];
}

- (NSString*)getAppConfiguration {
  return [self getConfiguration:@"appConfiguration"];
}

- (void)reportTestException {
  teak_try {
    @throw([NSException exceptionWithName:@"ReportTestException" reason:[NSString stringWithFormat:@"Version: %@", self.sdkVersion] userInfo:nil]);
  }
  teak_catch_report;
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
    self.log = [[TeakLog alloc] initForTeak:self withAppId:appId];

    [TeakConfiguration configureForAppId:appId andSecret:appSecret];
    self.configuration = [TeakConfiguration configuration];

    self.enableDebugOutput = self.configuration.debugConfiguration.logLocal;
    self.enableDebugOutput |= !self.configuration.appConfiguration.isProduction;

    self.enableRemoteLogging = self.configuration.debugConfiguration.logRemote;
    self.enableRemoteLogging |= !self.configuration.appConfiguration.isProduction;

    // Add Unity/Air SDK version if applicable
    NSMutableDictionary* sdkDict = [NSMutableDictionary dictionaryWithDictionary:@{@"ios" : self.sdkVersion}];
    if (TeakWrapperSDK != nil) {
      [sdkDict addEntriesFromDictionary:TeakWrapperSDK];
    }
    TeakVersionDict = sdkDict;

    [self.log useSdk:TeakVersionDict];
    [self.log useAppConfiguration:self.configuration.appConfiguration];
    [self.log useDeviceConfiguration:self.configuration.deviceConfiguration];
    [self.log useDataCollectionConfiguration:self.configuration.dataCollectionConfiguration];

    // Set up SDK Raven
    self.sdkRaven = [TeakRaven ravenForTeak:self];

    // Operation queue
    self.operationQueue = [[NSOperationQueue alloc] init];

    // Teak Core
    // TODO: This should be factory based
    self.core = [[TeakCore alloc] init];

    // Payment observer
    self.paymentObserver = [[SKPaymentObserver alloc] init];

    // Push State - Log it here, since sharedInstance has not yet been assigned at this point
    self.pushState = [[TeakPushState alloc] init];
    [self.log logEvent:@"push_state.init" level:@"INFO" eventData:[self.pushState to_h]];

    // Default wait for deep link operation
    self.waitForDeepLinkOperation = [NSBlockOperation blockOperationWithBlock:^{}];

    // Set up internal deep link routes
    [self setupInternalDeepLinkRoutes];

    self.skipTheNextOpenUrl = NO;
    self.skipTheNextDidReceiveNotificationResponse = NO;
    self.doNotResetBadgeCount = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"TeakDoNotResetBadgeCount"] boolValue];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)processDeepLinks {
  @synchronized(self.waitForDeepLinkOperation) {
    if (!self.waitForDeepLinkOperation.isFinished) {
      [self.operationQueue addOperation:self.waitForDeepLinkOperation];
    }
  }
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
  TeakUnused(notification);
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
  TeakUnused(application);
  TeakUnused(options);

  // I'm really not happy about this hack, but something is wrong with returning
  // YES from application:didFinishLaunchingWithOptions: and so we need to not
  // double-process a deep link if the app was not currently running
  if (self.skipTheNextOpenUrl || url == nil) {
    self.skipTheNextOpenUrl = NO;
    return NO;
  }

  [TeakSession didLaunchFromDeepLink:url.absoluteString];
  return YES;
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation {
  TeakUnused(sourceApplication);
  TeakUnused(annotation);
  return [self application:application openURL:url options:@{}];
}

- (void)setupInternalDeepLinkRoutes {
  // Register default purchase deep link
  [TeakLink registerRoute:@"/teak_internal/store/:sku"
                     name:@""
              description:@""
                    block:^(NSDictionary* _Nonnull parameters) {
                      [ProductRequest productRequestForSku:parameters[@"sku"]
                                                  callback:^(NSDictionary* unused, SKProductsResponse* response) {
                                                    if (response != nil && response.products != nil && response.products.count > 0) {
                                                      SKProduct* product = [response.products objectAtIndex:0];

                                                      SKMutablePayment* payment = [SKMutablePayment paymentWithProduct:product];
                                                      payment.quantity = 1;
                                                      [[SKPaymentQueue defaultQueue] addPayment:payment];
                                                    }
                                                  }];
                    }];

  // Register callback for Teak companion app
  [TeakLink registerRoute:@"/teak_internal/companion"
                     name:@""
              description:@""
                    block:^(NSDictionary* _Nonnull parameters) {
                      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
                        NSDictionary* responseDict = @{
                          @"user_id" : session.userId,
                          @"device_id" : session.deviceConfiguration.deviceId
                        };
                        NSError* error = nil;
                        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:responseDict options:0 error:&error];

                        NSString* valueString;
                        NSString* keyString;
                        if (error) {
                          TeakLog_e(@"companion.error", @{@"dictionary" : responseDict, @"error" : error});
                          keyString = @"error";
                          valueString = URLEscapedString([error description]);
                        } else {
                          keyString = @"response";
                          valueString = URLEscapedString([[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
                        }

                        NSString* openUrlString = [NSString stringWithFormat:@"teak:///callback?%@=%@", keyString, valueString];
                        dispatch_async(dispatch_get_main_queue(), ^{
                          [[UIApplication sharedApplication] openURL:[NSURL URLWithString:openUrlString]];
                        });
                      }];
                    }];

  // Open settings to this app's settings
  [TeakLink registerRoute:@"/teak_internal/app_settings"
                     name:@""
              description:@""
                    block:^(NSDictionary* _Nonnull parameters) {
                      [[Teak sharedInstance] openSettingsAppToThisAppsSettings];
                    }];
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});

  // Facebook SDKs
  Class fbClass_4x5x = NSClassFromString(@"FBSDKProfile");
  Class fbClass_3x = NSClassFromString(@"FBSession");
  teak_try {
    if (fbClass_4x5x != nil) {
      BOOL arg = YES;
      SEL enableUpdatesOnAccessTokenChange = NSSelectorFromString(@"enableUpdatesOnAccessTokenChange:");
      NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[fbClass_4x5x methodSignatureForSelector:enableUpdatesOnAccessTokenChange]];
      [inv setSelector:enableUpdatesOnAccessTokenChange];
      [inv setTarget:fbClass_4x5x];
      [inv setArgument:&arg atIndex:2];
      [inv invoke];

      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(fbAccessTokenChanged_4x:)
                                                   name:TeakFBSDKAccessTokenDidChangeNotification
                                                 object:nil];
    } else if (fbClass_3x != nil) {
      // accessTokenData
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(fbAccessTokenChanged_3x:)
                                                   name:TeakFBSessionDidBecomeOpenActiveSessionNotification
                                                 object:nil];
    }

    if (self.enableDebugOutput) {
      if (fbClass_3x != nil) {
        TeakLog_i(@"facebook.sdk", @{@"version" : @"4.x or 5.x"});
      } else if (fbClass_3x != nil) {
        TeakLog_i(@"facebook.sdk", @{@"version" : @"3.x"});
      } else {
        TeakLog_i(@"facebook.sdk", @{@"version" : [NSNull null]});
      }
    }
  }
  teak_catch_report;

  // Register push notification categories
  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    [center setNotificationCategories:[[NSSet alloc] init]]; // This is intentional empty set
  }

  // If the app was not running, we need to check these and invoke them afterwards
  if (launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
    self.skipTheNextDidReceiveNotificationResponse = NO;
    [self application:application didReceiveRemoteNotification:launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]];
    self.skipTheNextDidReceiveNotificationResponse = YES; // Be sure to assign 'YES' *after* the call
  } else if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
    self.skipTheNextOpenUrl = [self application:application
                                        openURL:launchOptions[UIApplicationLaunchOptionsURLKey]
                              sourceApplication:launchOptions[UIApplicationLaunchOptionsSourceApplicationKey]
                                     annotation:launchOptions[UIApplicationLaunchOptionsAnnotationKey]];
  }

  // Check to see if the user has already enabled push notifications.
  //
  // If they've already enabled push, go ahead and register since it won't pop up a box.
  // This is to ensure that we always get didRegisterForRemoteNotificationsWithDeviceToken:
  // even if the app developer doesn't follow Apple's best practices.
  [self.pushState determineCurrentPushStateWithCompletionHandler:^(TeakState* pushState) {
    if (pushState == [TeakPushState Authorized]) {
      if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
        UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge
                              completionHandler:^(BOOL granted, NSError* _Nullable error) {
                                if (granted) {
                                  dispatch_async(dispatch_get_main_queue(), ^{
                                    [application registerForRemoteNotifications];
                                  });
                                }
                              }];
      } else {
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
    } else if (pushState == [TeakPushState Provisional] && iOS12OrGreater()) {

      // Ignore the warning about using @available. It will cause compile issues on Adobe AIR.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
      UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
      [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge | TeakUNAuthorizationOptionProvisional
                            completionHandler:^(BOOL granted, NSError* _Nullable error) {
                              if (granted) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                  [application registerForRemoteNotifications];
                                });
                              }
                            }];
#pragma clang diagnostic pop
    }
  }];

  // Lifecycle event
  [LifecycleEvent applicationFinishedLaunching];

  return self.skipTheNextOpenUrl;
}

- (void)applicationDidBecomeActive:(UIApplication*)application {
  TeakUnused(application);
  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});

  // Zero-out the badge count
  if (!self.doNotResetBadgeCount) {
    [self setApplicationBadgeNumber:0];
  }

  // Lifecycle Event
  [LifecycleEvent applicationActivate];
}

- (void)applicationWillResignActive:(UIApplication*)application {
  TeakUnused(application);

  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});
  self.skipTheNextOpenUrl = NO;
  self.skipTheNextDidReceiveNotificationResponse = NO;

  [LifecycleEvent applicationDeactivate];
}

- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
  TeakUnused(notificationSettings);
  [application registerForRemoteNotifications];
}

- (void)userNotificationCenter:(UNUserNotificationCenter*)center
       willPresentNotification:(UNNotification*)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  TeakUnused(center);
  TeakUnused(notification);

  // When notification is delivered with app in the foreground, mute it like default behavior
  completionHandler(UNNotificationPresentationOptionNone);

  // However, still send it along to the handler
  [self application:[UIApplication sharedApplication] didReceiveRemoteNotification:notification.request.content.userInfo];
}

- (void)userNotificationCenter:(UNUserNotificationCenter*)center
    didReceiveNotificationResponse:(UNNotificationResponse*)response
             withCompletionHandler:(void (^)(void))completionHandler {
  TeakUnused(center);

  // Call application:didReceiveRemoteNotification: since that is not called in the UNNotificationCenter
  // code path.
  [self application:[UIApplication sharedApplication] didReceiveRemoteNotification:response.notification.request.content.userInfo];

  // Completion handler
  completionHandler();

  // TODO: HERE is where we report metric that a button was pressed
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
  TeakUnused(application);

  if (deviceToken == nil) {
    TeakLog_e(@"notification.registration.error", @"Got nil deviceToken. Push is disabled.");
    return;
  }

  NSString* deviceTokenString = TeakHexStringFromData(deviceToken);
  if (deviceTokenString != nil) {
    TeakLog_i(@"notification.registration.success", @{@"token" : deviceTokenString});
    [PushRegistrationEvent registeredWithToken:deviceTokenString];
  } else {
    TeakLog_e(@"notification.registration.error", @"Got nil deviceTokenString. Push is disabled.");
  }
}

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
  TeakUnused(application);

  if (error != nil) {
    TeakLog_e(@"notification.registration.error", @"Failed to register for push notifications.", @{@"error" : _([error localizedDescription])});
  } else {
    TeakLog_e(@"notification.registration.error", @"Failed to register for push notifications.", @{@"error" : @"unknown"});
  }
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo {
  // Check to see if this should be skipped
  if (self.skipTheNextDidReceiveNotificationResponse) {
    self.skipTheNextDidReceiveNotificationResponse = NO;
    return;
  }

  NSDictionary* aps = userInfo[@"aps"];
  NSString* teakNotifId = NSStringOrNilFor(aps[@"teakNotifId"]);

  if (teakNotifId != nil) {
    TeakNotification* notif = [[TeakNotification alloc] initWithDictionary:aps];

    if (notif != nil) {
      BOOL isInBackground = application.applicationState == UIApplicationStateInactive || application.applicationState == UIApplicationStateBackground;

      NSMutableDictionary* teakUserInfo = [[NSMutableDictionary alloc] init];
      teakUserInfo[@"teakNotifId"] = teakNotifId;
#define ValueOrNSNull(x) (x == nil ? [NSNull null] : x)
      teakUserInfo[@"teakRewardId"] = ValueOrNSNull(notif.teakRewardId);
      teakUserInfo[@"teakScheduleName"] = ValueOrNSNull(notif.teakScheduleName);
      teakUserInfo[@"teakCreativeName"] = ValueOrNSNull(notif.teakCreativeName);
#undef ValueOrNSNull
      teakUserInfo[@"incentivized"] = notif.teakRewardId == nil ? @NO : @YES;

      if (isInBackground) {
        // App was opened via push notification
        TeakLog_i(@"notification.opened", @{@"teakNotifId" : _(teakNotifId)});

        [TeakSession didLaunchFromTeakNotification:notif];

        [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
          [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                              object:self
                                                            userInfo:teakUserInfo];
        }];
      } else {
        // Push notification received while app was in foreground
        TeakLog_i(@"notification.foreground", @{@"teakNotifId" : _(teakNotifId)});

        [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
          [[NSNotificationCenter defaultCenter] postNotificationName:TeakForegroundNotification
                                                              object:self
                                                            userInfo:teakUserInfo];
        }];
      }
    }
  } else {
    TeakLog_i(@"notification.non_teak", userInfo);
  }
}

- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler {
  TeakUnused(application);
  TeakUnused(restorationHandler);

  if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {

    // Make sure the URL we fetch is https
    NSURLComponents* components = [NSURLComponents componentsWithURL:userActivity.webpageURL
                                             resolvingAgainstBaseURL:YES];
    components.scheme = @"https";
    NSURL* fetchUrl = components.URL;

    TeakLog_i(@"deep_link.request.send", [fetchUrl absoluteString]);
    // Fetch the data for the short link
    NSURLSession* session = [Teak URLSessionWithoutDelegate];
    NSURLSessionDataTask* task =
        [session dataTaskWithURL:fetchUrl
               completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
                 NSString* attributionUrlAsString = [userActivity.webpageURL absoluteString];

                 if (error == nil) {
                   TeakLog_i(@"deep_link.request.reply", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

                   NSDictionary* reply = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                   if (error == nil) {
                     NSString* iOSPath = reply[@"iOSPath"];
                     if (iOSPath != nil) {
                       attributionUrlAsString = [NSString stringWithFormat:@"teak%@://%@", self.configuration.appConfiguration.appId, iOSPath];
                       TeakLog_i(@"deep_link.request.resolve", attributionUrlAsString);
                     }
                   }
                 }

                 // Attribution
                 [TeakSession didLaunchFromDeepLink:attributionUrlAsString];
               }];
    [task resume];
  }

  return YES;
}

@end
