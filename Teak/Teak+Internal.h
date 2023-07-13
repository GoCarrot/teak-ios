#import <Teak/Teak.h>
#import <UserNotifications/UserNotifications.h>

#import "TeakConfiguration.h"
#import "TeakIntegrationChecker.h"
#import "TeakLog.h"
#import "TeakPushState.h"
#import "TeakRaven.h"
#import "TeakWaitForDeepLink.h"

@class TeakCore;
@class SKPaymentObserver;

#define kBlackholeUnregisterForRemoteNotifications @"TeakBlackholeUnregisterForRemoteNotifications"

extern NSDictionary* _Nonnull TeakNotificationCategories;

@interface Teak () <UNUserNotificationCenterDelegate>
@property (nonatomic, readwrite) BOOL enableDebugOutput;
@property (nonatomic, readwrite) BOOL enableRemoteLogging;

@property (strong, nonatomic, readwrite) NSString* _Nonnull sdkVersion;

@property (strong, nonatomic) TeakRaven* _Nonnull sdkRaven;
@property (strong, nonatomic) TeakIntegrationChecker* _Nonnull integrationChecker;

@property (strong, nonatomic) NSOperationQueue* _Nonnull operationQueue;
@property (strong, nonatomic) TeakWaitForDeepLink* _Nonnull waitForDeepLink;

@property (strong, nonatomic) TeakConfiguration* _Nonnull configuration;
@property (strong, nonatomic) TeakLog* _Nonnull log;
@property (strong, nonatomic) TeakCore* _Nonnull core;
@property (strong, nonatomic) SKPaymentObserver* _Nullable paymentObserver;
@property (strong, nonatomic) TeakPushState* _Nonnull pushState;

@property (nonatomic) BOOL skipTheNextOpenUrl;
@property (nonatomic) BOOL skipTheNextDidReceiveNotificationResponse;
@property (nonatomic) BOOL doNotResetBadgeCount;

// Static initialization time or main()
- (id _Nullable)initWithApplicationId:(NSString* _Nonnull)appId andSecret:(NSString* _Nonnull)appSecret;

+ (NSURLSession* _Nonnull)URLSessionWithoutDelegate;
+ (dispatch_queue_t _Nonnull)operationQueue;

- (void)reportTestException;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
// App launch
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

// Post-launch lifecycle
- (void)applicationDidBecomeActive:(UIApplication*)application;
- (void)applicationWillResignActive:(UIApplication*)application;

// Deep Linking
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation;
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url options:(NSDictionary<NSString*, id>*)options;
- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler;

// Push notification
- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings;
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error;
- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;
- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler;
#pragma clang diagnostic pop

@end
