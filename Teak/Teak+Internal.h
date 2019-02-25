#import <Teak/Teak.h>
#import <UserNotifications/UserNotifications.h>

#import "TeakConfiguration.h"
#import "TeakLog.h"
#import "TeakPushState.h"
#import "TeakRaven.h"

@class TeakCore;
@class SKPaymentObserver;

#define kBlackholeUnregisterForRemoteNotifications @"TeakBlackholeUnregisterForRemoteNotifications"

extern NSDictionary* _Nonnull TeakNotificationCategories;

@interface Teak () <UNUserNotificationCenterDelegate>
@property (nonatomic, readwrite) BOOL enableDebugOutput;
@property (nonatomic) BOOL enableRemoteLogging;

@property (strong, nonatomic, readwrite) NSString* _Nonnull sdkVersion;

@property (strong, nonatomic) TeakRaven* _Nonnull sdkRaven;

@property (strong, nonatomic) NSOperationQueue* _Nonnull operationQueue;
@property (strong, nonatomic) NSOperation* _Nullable waitForDeepLinkOperation;

@property (strong, nonatomic) TeakConfiguration* _Nonnull configuration;
@property (strong, nonatomic) TeakLog* _Nonnull log;
@property (strong, nonatomic) TeakCore* _Nonnull core;
@property (strong, nonatomic) SKPaymentObserver* _Nonnull paymentObserver;
@property (strong, nonatomic) TeakPushState* _Nonnull pushState;

@property (nonatomic) BOOL skipTheNextOpenUrl;
@property (nonatomic) BOOL skipTheNextDidReceiveNotificationResponse;

// Static initialization time or main()
- (id _Nullable)initWithApplicationId:(NSString* _Nonnull)appId andSecret:(NSString* _Nonnull)appSecret;

+ (NSURLSession* _Nonnull)sharedURLSession;
+ (dispatch_queue_t _Nonnull)operationQueue;

- (void)reportTestException;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
// App launch
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

// Post-launch lifecycle
- (void)applicationDidBecomeActive:(UIApplication*)application;
- (void)applicationWillResignActive:(UIApplication*)application;

// Deep Linking
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation;
- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler;

// Push notification
- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings;
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error;
- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;
#pragma clang diagnostic pop

@end
