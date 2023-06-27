#import <AdSupport/AdSupport.h>
#import <UserNotifications/UNUserNotificationCenter.h>

#import "Teak+Internal.h"
#import <Teak/Teak.h>

#import "TeakRequest.h"
#import "TeakSession.h"

#import "SKPaymentObserver.h"
#import "TeakCore.h"
#import "TeakIntegrationChecker.h"
#import "TeakLaunchData.h"
#import "TeakNotification.h"
#import "TeakReward.h"
#import "TeakVersion.h"

#import "FacebookAccessTokenEvent.h"
#import "LifecycleEvent.h"
#import "LogoutEvent.h"
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
NSString* const TeakLaunchedFromLink = @"TeakLaunchedFromLink";
NSString* const TeakPostLaunchSummary = @"TeakPostLaunchSummary";
NSString* const TeakUserData = @"TeakUserData";

NSString* const TeakOptOutIdfa = @"opt_out_idfa";
NSString* const TeakOptOutPushKey = @"opt_out_push_key";
NSString* const TeakOptOutFacebook = @"opt_out_facebook";

// FB SDK 3.x
NSString* const TeakFBSessionDidBecomeOpenActiveSessionNotification = @"com.facebook.sdk:FBSessionDidBecomeOpenActiveSessionNotification";

// Proilfe
NSString* const TeakFBSDKProfileDidChangeNotification = @"com.facebook.sdk.FBSDKProfile.FBSDKProfileDidChangeNotification";
NSString* const TeakFBSDKProfileChangeOldKey = @"FBSDKProfileOld";
NSString* const TeakFBSDKProfileChangeNewKey = @"FBSDKProfileNew";

// FB SDK 4.x, and greater
NSString* const TeakFBSDKAccessTokenDidChangeNotification = @"com.facebook.sdk.FBSDKAccessTokenData.FBSDKAccessTokenDidChangeNotification";
NSString* const TeakFBSDKAccessTokenDidChangeUserID = @"FBSDKAccessTokenDidChangeUserID";
NSString* const TeakFBSDKAccessTokenChangeNewKey = @"FBSDKAccessToken";
NSString* const TeakFBSDKAccessTokenChangeOldKey = @"FBSDKAccessTokenOld";

// AIR/Unity/etc SDK Version Extern
NSDictionary* TeakWrapperSDK = nil;
NSDictionary* TeakXcodeVersion = nil;

NSDictionary* TeakVersionDict = nil;

extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);
extern BOOL TeakLink_WillHandleDeepLink(NSURL* deepLink);

extern BOOL TeakSendHealthCheckIfNeededSynch(NSDictionary* userInfo);
extern NSURLSession* TeakURLSessionWithoutDelegate(void);

Teak* _teakSharedInstance;

@implementation Teak

+ (Teak*)sharedInstance {
  return _teakSharedInstance;
}

+ (NSURLSession*)URLSessionWithoutDelegate {
  return TeakURLSessionWithoutDelegate();
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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [self identifyUser:userIdentifier
      withOptOutList:@[]
            andEmail:nil];
#pragma clang diagnostic pop
}

- (void)identifyUser:(NSString*)userIdentifier withEmail:(nonnull NSString*)email {
  [self identifyUser:userIdentifier withOptOutList:@[] andEmail:email];
}

- (void)identifyUser:(NSString*)userIdentifier withOptOutList:(NSArray*)optOut {
  [self identifyUser:userIdentifier withOptOutList:optOut andEmail:nil];
}

- (void)identifyUser:(NSString*)userIdentifier withOptOutList:(NSArray*)optOut andEmail:(nullable NSString*)email {
  TeakUserConfiguration* userConfiguration = [[TeakUserConfiguration alloc] init];
  userConfiguration.email = email;
  userConfiguration.optOutFacebook = [optOut containsObject:TeakOptOutFacebook];
  userConfiguration.optOutIdfa = [optOut containsObject:TeakOptOutIdfa];
  userConfiguration.optOutPushKey = [optOut containsObject:TeakOptOutPushKey];

  [self identifyUser:userIdentifier withConfiguration:userConfiguration];
}

- (void)identifyUser:(nonnull NSString*)userIdentifier withConfiguration:(nonnull TeakUserConfiguration*)userConfiguration {
  TeakLog_t(@"[Teak identifyUser]", @{@"userIdentifier" : _(userIdentifier), @"userConfiguration" : [userConfiguration to_h]});

  [self processDeepLinks];

  if (userIdentifier == nil || userIdentifier.length == 0) {
    TeakLog_e(@"identify_user.error", @"User identifier can not be null or empty.");
    return;
  }

  TeakLog_i(@"identify_user", @{@"userIdentifier" : userIdentifier, @"userConfiguration" : [userConfiguration to_h]});

  [UserIdEvent userIdentified:[userIdentifier copy] withConfiguration:[userConfiguration copy]];
}

- (void)logout {
  TeakLog_t(@"[Teak logout]", @{});

  TeakLog_i(@"logout");

  [LogoutEvent logout];
}

- (void)trackEventWithActionId:(NSString*)actionId forObjectTypeId:(NSString*)objectTypeId andObjectInstanceId:(NSString*)objectInstanceId {
  [self incrementEventWithActionId:actionId forObjectTypeId:objectTypeId andObjectInstanceId:objectInstanceId count:1];
}

- (void)incrementEventWithActionId:(nonnull NSString*)actionId forObjectTypeId:(nullable NSString*)objectTypeId andObjectInstanceId:(nullable NSString*)objectInstanceId count:(int64_t)count {
  actionId = [[actionId copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  objectTypeId = [[objectTypeId copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  objectInstanceId = [[objectInstanceId copy] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

  TeakLog_t(@"[Teak incrementEventWithActionId]", @{@"actionId" : _(actionId), @"objectTypeId" : _(objectTypeId), @"objectInstanceId" : _(objectInstanceId), @"count" : [NSNumber numberWithLongLong:count]});

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
  TeakLog_t(@"[Teak notificationState]", @{});

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

- (BOOL)canOpenSettingsAppToThisAppsSettings {
  return YES;
}

- (BOOL)openSettingsAppToThisAppsSettings {
  TeakLog_t(@"[Teak openSettingsAppToThisAppsSettings]", @{});
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
#pragma clang diagnostic pop
}

- (BOOL)canOpenNotificationSettings {
  if (@available(iOS 15.4, *)) {
    return YES;
  } else {
    return NO;
  }
}

- (BOOL)openNotificationSettings {
  if (@available(iOS 15.4, *)) {
    // UIApplicationOpenNotificationSettingsURLString = @"app-settings:notifications"
    NSURL* url = [[NSURL alloc] initWithString:@"app-settings:notifications"];
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:nil];
    return YES;
  } else {
    return NO;
  }
}

- (void)setApplicationBadgeNumber:(int)count {
  TeakLog_t(@"[Teak setApplicationBadgeNumber]", @{@"count" : [NSNumber numberWithInt:count]});

  // If iOS 8+ then check first to see if we have permission to change badge, otherwise
  // just go ahead and change it.
  if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIUserNotificationSettings* notificationSettings = [[UIApplication sharedApplication] currentUserNotificationSettings];
    BOOL hasBadgeType = notificationSettings.types & UIUserNotificationTypeBadge;
    if (hasBadgeType) {
      [[UIApplication sharedApplication] setApplicationIconBadgeNumber:count];
    }
#pragma clang diagnostic pop
  } else {
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:count];
  }
}

- (void)setNumericAttribute:(double)value forKey:(NSString* _Nonnull)key {
  TeakLog_t(@"[Teak setNumericAttribute]", @{@"value" : [NSNumber numberWithDouble:value], @"key" : _(key)});

  double copiedValue = value;
  NSString* copiedKey = [key copy];
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* _Nonnull session) {
    [session.userProfile setNumericAttribute:copiedValue forKey:copiedKey];
  }];
}

- (void)setStringAttribute:(NSString* _Nonnull)value forKey:(NSString* _Nonnull)key {
  TeakLog_t(@"[Teak setStringAttribute]", @{@"value" : _(value), @"key" : _(key)});

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
    NSMutableDictionary* sdkDict = [NSMutableDictionary dictionaryWithDictionary:@{
      @"ios" : self.sdkVersion
    }];
    if (TeakWrapperSDK != nil) {
      [sdkDict addEntriesFromDictionary:TeakWrapperSDK];
    }
    TeakVersionDict = sdkDict;

    // Xcode versions
    NSMutableDictionary* xcodeDict = [NSMutableDictionary dictionaryWithDictionary:@{
      @"sdk" : [NSNumber numberWithInt:__apple_build_version__]
    }];
    if (TeakXcodeVersion != nil) {
      [xcodeDict addEntriesFromDictionary:TeakXcodeVersion];
    }

    [self.log useSdk:TeakVersionDict andXcode:xcodeDict];
    [self.log useAppConfiguration:self.configuration.appConfiguration];
    [self.log useDeviceConfiguration:self.configuration.deviceConfiguration];
    [self.log useDataCollectionConfiguration:self.configuration.dataCollectionConfiguration];

    // Set up SDK Raven
    self.sdkRaven = [TeakRaven ravenForTeak:self];

    // Operation queue
    self.operationQueue = [[NSOperationQueue alloc] init];

    // Teak integration checker happens after logs, raven and the global operation queue
    self.integrationChecker = [TeakIntegrationChecker checkIntegrationForTeak:self];

    // Teak Core
    // TODO: This should be factory based
    self.core = [[TeakCore alloc] init];

    // Payment observer
    // If TeakNoAutoTrackPurchase is set, do not create a payment observer
    if (![[[NSBundle mainBundle] objectForInfoDictionaryKey:@"TeakNoAutoTrackPurchase"] boolValue]) {
      self.paymentObserver = [[SKPaymentObserver alloc] init];
    }

    // Push State - Log it here, since sharedInstance has not yet been assigned at this point
    self.pushState = [[TeakPushState alloc] init];
    [self.log logEvent:@"push_state.init" level:@"INFO" eventData:[self.pushState to_h]];

    // Default wait for deep link operation
    self.waitForDeepLink = [[TeakWaitForDeepLink alloc] init];

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
  [self.waitForDeepLink addToQueue:self.operationQueue];
}

- (void)fbProfileChanged:(NSNotification*)notification {
  id tokenString = [FacebookAccessTokenEvent currentUserToken];
  if (tokenString != nil && tokenString != [NSNull null]) {
    [FacebookAccessTokenEvent accessTokenUpdated:tokenString];
  }
}

- (BOOL)handleDeepLinkPath:(NSString*)path {
  TeakLog_t(@"[Teak handleDeepLinkPath]", @{@"path" : _(path)});
  NSString* url = [NSString stringWithFormat:@"%@://%@", [TeakConfiguration configuration].appConfiguration.urlSchemes.allObjects[0], path];
  return [TeakLink handleDeepLink:[NSURL URLWithString:url]];
}

- (BOOL)handleOpenURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication {
  // I'm really not happy about this hack, but something is wrong with returning
  // YES from application:didFinishLaunchingWithOptions: and so we need to not
  // double-process a deep link if the app was not currently running
  if (self.skipTheNextOpenUrl || url == nil) {
    self.skipTheNextOpenUrl = NO;
    return NO;
  }

  // If the sourceApplication is our bundleIdentifier then we have gotten here
  // via an internal call to [UIApplication openURL:], and we should not
  // treat that as a launching from a new link. Teak links should never reach
  // here in that case, as they should be handled by Teak prior to any attempts
  // to call [UIApplication openURL:]
  if (sourceApplication && [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:sourceApplication]) {
    // Return NO to indicate that the link should be passed to the host application.
    return NO;
  }

  TeakLaunchDataOperation* launchData = [TeakLaunchDataOperation fromOpenUrl:url];
  [TeakSession didLaunchWithData:launchData];

  // Returns YES if it's a Teak link, in which case it will *not* be passed on to the host application.
  // Returns NO if it's not a Teak link, it will then be passed to the host application.
  return TeakLink_WillHandleDeepLink(url);
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url options:(NSDictionary<NSString*, id>*)options {
  TeakUnused(application);

  return [self handleOpenURL:url sourceApplication:options[UIApplicationOpenURLOptionsSourceApplicationKey]];
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation {
  return [self handleOpenURL:url sourceApplication:sourceApplication];
}

- (void)setupInternalDeepLinkRoutes {
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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                          [[UIApplication sharedApplication] openURL:[NSURL URLWithString:openUrlString]];
#pragma clang diagnostic pop
                        });
                      }];
                    }];

  // Open settings to this app's settings
  [TeakLink registerRoute:@"/teak_internal/app_settings"
                     name:@""
              description:@""
                    block:^(NSDictionary* _Nonnull parameters) {
                      BOOL includeProvisional = [parameters[@"include_provisional"] boolValue];
                      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
                        TeakNotificationState notificationState = [[Teak sharedInstance] notificationState];
                        if (notificationState == TeakNotificationStateDisabled ||
                            (includeProvisional && notificationState == TeakNotificationStateProvisional)) {
                          [[Teak sharedInstance] openSettingsAppToThisAppsSettings];
                        }
                      }];
                    }];
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  TeakLog_i(@"lifecycle", @{@"callback" : NSStringFromSelector(_cmd)});

  // Facebook SDKs, only if SDK5 behavior is not enabled
  if (!self.configuration.appConfiguration.sdk5Behaviors) {
    Class fbClass_4x_or_greater = NSClassFromString(@"FBSDKProfile");
    teak_try {
      if (fbClass_4x_or_greater != nil) {
        BOOL arg = YES;
        SEL enableUpdatesOnAccessTokenChange = NSSelectorFromString(@"enableUpdatesOnAccessTokenChange:");
        NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[fbClass_4x_or_greater methodSignatureForSelector:enableUpdatesOnAccessTokenChange]];
        [inv setSelector:enableUpdatesOnAccessTokenChange];
        [inv setTarget:fbClass_4x_or_greater];
        [inv setArgument:&arg atIndex:2];
        [inv invoke];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(fbProfileChanged:)
                                                     name:TeakFBSDKProfileDidChangeNotification
                                                   object:nil];
      }

      if (self.enableDebugOutput) {
        if (fbClass_4x_or_greater != nil) {
          TeakLog_i(@"facebook.sdk", @{@"version" : @"4.x or greater"});
        } else {
          TeakLog_i(@"facebook.sdk", @{@"version" : [NSNull null]});
        }
      }
    }
    teak_catch_report;
  }

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

  // If requested, do not automatically refresh the push token, instead user
  // must call [Teak refreshPushTokenIfAuthorized] themselves.
  if (!self.configuration.appConfiguration.doNotRefreshPushToken) {
    [self refreshPushTokenIfAuthorized];
  }

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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
  TeakUnused(notificationSettings);
  [application registerForRemoteNotifications];
}
#pragma clang diagnostic pop

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

- (void)refreshPushTokenIfAuthorized {
  // Check to see if the user has already enabled push notifications.
  //
  // If they've already enabled push, go ahead and register since it won't pop up a box.
  // This is to ensure that we always get didRegisterForRemoteNotificationsWithDeviceToken:
  // even if the app developer doesn't follow Apple's best practices.
  [self.pushState determineCurrentPushStateWithCompletionHandler:^(TeakState* pushState) {
    UIApplication* application = [UIApplication sharedApplication];

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
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
          UIUserNotificationSettings* settings = application.currentUserNotificationSettings;
          [application registerUserNotificationSettings:settings];
#pragma clang diagnostic pop
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
      [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge | UNAuthorizationOptionProvisional
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
}

// This MUST be called when we know that a user tapped on a notification.
- (void)didLaunchFromNotification:(TeakNotification*)notif inBackground:(BOOL)isInBackground {
  // This is a workaround for when we track that we launched through a
  // notification from didFinishLaunchingWithOptions and iOS subsequently calls
  // another one of our relevant delegate methods.
  //
  // In testing back to iOS 8.4.1 iOS _always_ calls one of our other delegate
  // methods after calling didFinishLaunchingWithOptions. This workaround may
  // have been necessary for iOS 7 or earlier, however we can no longer test
  // those cases. This workaround will remain until such time as we can drop
  // support for iOS < 10.
  if (self.skipTheNextDidReceiveNotificationResponse) {
    self.skipTheNextDidReceiveNotificationResponse = NO;
    return;
  }

  TeakLog_i(@"notification.opened", @{@"teakNotifId" : _(notif.teakNotifId)});

  TeakLaunchDataOperation* launchData = [TeakLaunchDataOperation fromPushNotification:notif];
  [TeakSession didLaunchWithData:launchData];
}

// This should be called when a notification was received with the app in the
// foreground.
- (void)didReceiveForegroundNotification:(TeakNotification*)notif {
  TeakLog_i(@"notification.foreground", @{@"teakNotifId" : _(notif.teakNotifId)});

  // Notify any listeners that a foreground notification has been received.
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    [[NSNotificationCenter defaultCenter] postNotificationName:TeakForegroundNotification
                                                        object:self
                                                      userInfo:notif.eventUserInfo];
  }];
}

- (TeakNotification*)teakNotificationFromUserInfo:(NSDictionary*)userInfo {
  NSDictionary* aps = userInfo[@"aps"];
  NSString* teakNotifId = NSStringOrNilFor(aps[@"teakNotifId"]);
  if (!teakNotifId) {
    TeakLog_i(@"notification.non_teak", userInfo);
    return nil;
  }

  return [[TeakNotification alloc] initWithDictionary:aps];
}

+ (BOOL)isTeakNotification:(UNNotification*)notification {
  NSDictionary* aps = notification.request.content.userInfo[@"aps"];
  return NSStringOrNilFor(aps[@"teakNotifId"]) != nil;
}

- (void)userNotificationCenter:(UNUserNotificationCenter*)center
       willPresentNotification:(UNNotification*)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  TeakUnused(center);

  TeakNotification* notif = [self teakNotificationFromUserInfo:notification.request.content.userInfo];
  if (notif) {
    // Always inform the host app that a foreground notification was received
    [self didReceiveForegroundNotification:notif];
  }

  // Optionally display the notification in the foreground if requested
  completionHandler(notif && notif.showInForeground ? UNNotificationPresentationOptionAlert : UNNotificationPresentationOptionNone);
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler {
  TeakSendHealthCheckIfNeededSynch(userInfo);
  if (handler != nil) {
    handler(UIBackgroundFetchResultNoData);
  }
}

- (void)deleteEmail {
  TeakLog_t(@"[Teak deleteEmail]", @{});
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* _Nonnull session) {
    [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
      TeakRequest* request = [TeakRequest requestWithSession:session
                                                 forEndpoint:@"/me/email"
                                                 withPayload:@{}
                                                      method:TeakRequest_DELETE
                                                    callback:nil];
      [request send];
    }];
  }];
}

+ (BOOL)willPresentNotification:(UNNotification*)notification
          withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  if ([Teak isTeakNotification:notification]) {
    [[Teak sharedInstance] userNotificationCenter:[UNUserNotificationCenter currentNotificationCenter]
                          willPresentNotification:notification
                            withCompletionHandler:completionHandler];
    return YES;
  }
  return NO;
}

- (nonnull TeakOperation*)setState:(nonnull NSString*)state forChannel:(nonnull NSString*)channel {
  TeakLog_t(@"[TeakNotification setState:forChannel]", @{@"state" : _(state), @"channel" : _(channel)});
  // If "PlatformPush" is requested , this is iOS; so it's MobilePush
  channel = [TeakChannelTypePlatformPush isEqualToString:channel] ? TeakChannelTypeMobilePush : channel;
  TeakOperation* op = [TeakOperation forEndpoint:@"/me/channel_state"
                                     withPayload:@{@"channel" : channel, @"state" : state}
                                     replyParser:^id _Nullable(NSDictionary* _Nonnull reply) {
                                       TeakOperationChannelStateResult* result = [[TeakOperationChannelStateResult alloc] init];
                                       result.error = ![@"ok" isEqualToString:reply[@"status"]];
                                       result.state = reply[@"state"];
                                       result.channel = reply[@"channel"];
                                       result.errors = reply[@"errors"];
                                       return result;
                                     }];
  [self.operationQueue addOperation:op];
  return op;
}

- (nonnull TeakOperation*)setState:(nonnull NSString*)state forChannel:(nonnull NSString*)channel andCategory:(nonnull NSString*)category {
  TeakLog_t(@"[TeakNotification setState:forChannel:andCategory]", @{@"state" : _(state), @"channel" : _(channel), @"category" : _(category)});
  // If "PlatformPush" is requested , this is iOS; so it's MobilePush
  channel = [TeakChannelTypePlatformPush isEqualToString:channel] ? TeakChannelTypeMobilePush : channel;
  TeakOperation* op = [TeakOperation forEndpoint:@"/me/category_state"
                                     withPayload:@{@"channel" : channel, @"state" : state, @"category" : category}
                                     replyParser:^id _Nullable(NSDictionary* _Nonnull reply) {
                                       TeakOperationCategoryStateResult* result = [[TeakOperationCategoryStateResult alloc] init];
                                       result.error = ![@"ok" isEqualToString:reply[@"status"]];
                                       result.state = reply[@"state"];
                                       result.channel = reply[@"channel"];
                                       result.category = reply[@"category"];
                                       result.errors = reply[@"errors"];
                                       return result;
                                     }];
  [self.operationQueue addOperation:op];
  return op;
}

// This method will be called whenever a taps on a notification
- (void)userNotificationCenter:(UNUserNotificationCenter*)center
    didReceiveNotificationResponse:(UNNotificationResponse*)response
             withCompletionHandler:(void (^)(void))completionHandler {
  TeakUnused(center);

  // If this is a Teak notification
  TeakNotification* notif = [self teakNotificationFromUserInfo:response.notification.request.content.userInfo];
  if (notif) {
    [self didLaunchFromNotification:notif inBackground:[UIApplication sharedApplication].applicationState != UIApplicationStateActive];

    // Integration check, if the service is not integrated, this will not be assigned
    if (response.notification.request.content.userInfo[@"teak_service_processed"] == nil) {
      TeakLog_e(@"notification.integration", @"TeakNotificationService extension is not integrated.");
    }
  }

  // Let the OS know we're done handling this.
  completionHandler();

  // TODO: HERE is where we report metric that a button was pressed
}

+ (BOOL)didReceiveNotificationResponse:(UNNotificationResponse*)response
                 withCompletionHandler:(void (^)(void))completionHandler {
  if ([Teak isTeakNotification:response.notification]) {
    [[Teak sharedInstance] userNotificationCenter:[UNUserNotificationCenter currentNotificationCenter]
                   didReceiveNotificationResponse:response
                            withCompletionHandler:completionHandler];
    return YES;
  }
  return NO;
}

// This method is only called by iOS on versions of iOS which do not provide the
// userNotificationCenter callbacks. Those versions of iOS do not support
// displaying notifications in the foreground, and thus this method does not
// need to handle the case where it is called after a user has tapped a
// foreground notification.
- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo {
  // Check for data-only push
  if (userInfo[@"aps"][@"content-available"] && userInfo[@"teakHealthCheck"]) {
    [self application:application didReceiveRemoteNotification:userInfo fetchCompletionHandler:nil];
    return;
  }

  TeakNotification* notif = [self teakNotificationFromUserInfo:userInfo];
  if (!notif) {
    return;
  }

  // Application state can be foreground, background, or inactive. Inactive
  // indicates that we are transitioning from the background to the foreground.
  // This method may be called when the notification sets content-available and
  // the app is background. However that situation does not indicate a launch
  // from the notification.
  if (application.applicationState == UIApplicationStateInactive) {
    [self didLaunchFromNotification:notif inBackground:true];
  } else if (application.applicationState == UIApplicationStateActive) {
    [self didReceiveForegroundNotification:notif];
  }
}

- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler {
  TeakUnused(application);
  TeakUnused(restorationHandler);

  if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
    TeakLaunchDataOperation* launchData = [TeakLaunchDataOperation fromUniversalLink:userActivity.webpageURL];
    [TeakSession didLaunchWithData:launchData];
  }

  return YES;
}

@end
