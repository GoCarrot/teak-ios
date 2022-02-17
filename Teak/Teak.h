#include <Foundation/Foundation.h>

/**
 * Use this named notification to listen for when your app gets launched from a Teak notification.
 * [[NSNotificationCenter defaultCenter] addObserver:self
 *                                          selector:@selector(handleTeakNotification:)
 *                                               name:TeakNotificationAppLaunch
 *                                             object:nil];
 */
extern NSString* _Nonnull const TeakNotificationAppLaunch;

/**
 * Use this named notification to listen for when a reward claim is attempted.
 * [[NSNotificationCenter defaultCenter] addObserver:self
 *                                          selector:@selector(handleTeakReward:)
 *                                               name:TeakOnReward
 *                                             object:nil];
 */
extern NSString* _Nonnull const TeakOnReward;

/**
 * Use this named notification to listen for when your app receives a Teak notification while in the foreground.
 * [[NSNotificationCenter defaultCenter] addObserver:self
 *                                          selector:@selector(handleTeakForegroundNotification:)
 *                                               name:TeakForegroundNotification
 *                                             object:nil];
 */
extern NSString* _Nonnull const TeakForegroundNotification;

/**
 * Use this named notification to listen for when your app receives additional data for the current user.
 * [[NSNotificationCenter defaultCenter] addObserver:self
 *                                          selector:@selector(handleTeakAdditionalData:)
 *                                               name:TeakAdditionalData
 *                                             object:nil];
 */
extern NSString* _Nonnull const TeakAdditionalData;

/**
* Use this named notification to listen for when your app is launched from a link created by the Teak dashboard.
* [[NSNotificationCenter defaultCenter] addObserver:self
*                                          selector:@selector(handleTeakLaunchedFromLink:)
*                                               name:TeakLaunchedFromLink
*                                             object:nil];
*/
extern NSString* _Nonnull const TeakLaunchedFromLink;

/**
 * Use this named notification to listen for the information about the launch of your app.
 * [[NSNotificationCenter defaultCenter] addObserver:self
 *                                selector:@selector(handleTeakPostLAunchSummary:)
 *                                 name:TeakPostLaunchSummary
 *                                 object:nil];
 */
extern NSString* _Nonnull const TeakPostLaunchSummary;

/**
 * Value provided to identifyUser:withOptOutList: to opt out of collecting an IDFA for this specific user.
 *
 * If you prevent Teak from collecting the Identifier For Advertisers (IDFA),
 * Teak will no longer be able to add this user to Facebook Ad Audiences.
 */
extern NSString* _Nonnull const TeakOptOutIdfa;

/**
 * Value provided to identifyUser:withOptOutList: to opt out of collecting a Push Key for this specific user.
 *
 * If you prevent Teak from collecting the Push Key, Teak will no longer be able
 * to send Local Notifications or Push Notifications for this user.
 */
extern NSString* _Nonnull const TeakOptOutPushKey;

/**
 * Value provided to identifyUser:withOptOutList: to opt out of collecting a Facebook Access Token for this specific user.
 *
 * If you prevent Teak from collecting the Facebook Access Token,
 * Teak will no longer be able to correlate this user across multiple devices.
 */
extern NSString* _Nonnull const TeakOptOutFacebook;

/**
 * Value returned from notificationState
 */
typedef enum TeakNotificationState : int {
  TeakNotificationStateUnknown = -1,      ///< An unknown error prevented getting the state.
  TeakNotificationStateEnabled = 0,       ///< Notifications are enabled.
  TeakNotificationStateDisabled = 1,      ///< Notifications are disabled.
  TeakNotificationStateProvisional = 2,   ///< Provisional authorization (see Teak docs on iOS 12 provisional notifications)
  TeakNotificationStateNotDetermined = 3, ///< The user has not yet been asked to authorize notifications.
} TeakNotificationState;

/**
 * Callback used for Log Listeners
 */
typedef void (^TeakLogListener)(NSString* _Nonnull event,
                                NSString* _Nonnull level,
                                NSDictionary* _Nullable eventData);

#ifdef __OBJC__

#import <Teak/TeakLink.h>
#import <Teak/TeakNotification.h>
#import <Teak/TeakNotificationServiceCore.h>
#import <Teak/TeakNotificationViewControllerCore.h>
#import <Teak/TeakUserConfiguration.h>
#import <UIKit/UIKit.h>

/**
 * TODO!
 */
@interface Teak : NSObject

/**
 * Teak SDK Version.
 */
@property (strong, nonatomic, readonly) NSString* _Nonnull sdkVersion;

/**
 * Is debug logging enabled.
 *
 * Disabled by default in production, enabled otherwise.
 */
@property (nonatomic, readonly) BOOL enableDebugOutput;

/**
 * Is remote logging enabled.
 *
 * Disabled except under development conditions, or very specific circumstances in production.
 */
@property (nonatomic, readonly) BOOL enableRemoteLogging;

/**
 * The active log listener
 */
@property (copy, nonatomic) TeakLogListener _Nullable logListener;

/**
 * Set up Teak in a single function call.
 *
 * This function *must* be called from no other place than main() in your application's
 * 'main.m' or 'main.mm' file before UIApplicationMain() is called. Ex:
 *
 * 	int main(int argc, char *argv[])
 * 	{
 * 		@autoreleasepool {
 * 			// Add this line here.
 * 			[Teak initForApplicationId:@"your_app_id" withClass:[YourAppDelegate class] andApiKey:@"your_api_key"];
 *
 * 			return UIApplicationMain(argc, argv, nil, NSStringFromClass([YourAppDelegate class]));
 * 		}
 * 	}
 *
 * This functionality is also accessable from the C API:
 *    extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);
 *
 * @param appId            Teak Application Id
 * @param appDelegateClass Class of your application delegate, ex: [YourAppDelegate class].
 * @param apiKey           Your Teak API key.
 */
+ (void)initForApplicationId:(nonnull NSString*)appId withClass:(nonnull Class)appDelegateClass andApiKey:(nonnull NSString*)apiKey;

/**
 * Teak singleton.
 */
+ (nullable Teak*)sharedInstance;

/**
 * Tell Teak how to identify the current user.
 *
 * This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *    extern void TeakIdentifyUser(const char* userId, const char* userConfigurationJson);
 *
 * @param userId           The string Teak should use to identify the current user.
 */
- (void)identifyUser:(nonnull NSString*)userId;

/**
 * Tell Teak how to identify the current user.
 *
 * This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *    extern void TeakIdentifyUser(const char* userId, const char* userConfigurationJson);
 *
 * @param userId           The string Teak should use to identify the current user.
 * @param email            The email address for the current user.
 */
- (void)identifyUser:(nonnull NSString*)userId withEmail:(nonnull NSString*)email __deprecated_msg("Use identifyUser:withConfiguration: instead");

/**
 * Tell Teak how to identify the current user, with data collection opt-out.
 *
 * This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *    extern void TeakIdentifyUser(const char* userId, const char* userConfigurationJson);
 *
 * @param userId           The string Teak should use to identify the current user.
 * @param optOut           A list containing zero or more of: TeakOptOutIdfa, TeakOptOutPushKey, TeakOptOutFacebook
 */
- (void)identifyUser:(nonnull NSString*)userId withOptOutList:(nonnull NSArray*)optOut __deprecated_msg("Use identifyUser:withConfiguration: instead");

/**__deprecated_msg("Use identifyUser:withConfiguration: instead")
 * Tell Teak how to identify the current user, with data collection opt-out.
 *
 * This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *    extern void TeakIdentifyUser(const char* userId, const char* userConfigurationJson);
 *
 * @param userId           The string Teak should use to identify the current user.
 * @param optOut           A list containing zero or more of: TeakOptOutIdfa, TeakOptOutPushKey, TeakOptOutFacebook
 * @param email            The email address for the current user.
 */
- (void)identifyUser:(nonnull NSString*)userId withOptOutList:(nonnull NSArray*)optOut andEmail:(nullable NSString*)email __deprecated_msg("Use identifyUser:withConfiguration: instead");

/**
 * Tell Teak how to identify the current user, with data collection opt-out.
 *
 * This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *    extern void TeakIdentifyUser(const char* userId, const char* userConfigurationJson);
 *
 * @param userIdentifier              The string Teak should use to identify the current user.
 * @param userConfiguration       Additional configuration for the current user.
 */
- (void)identifyUser:(nonnull NSString*)userIdentifier withConfiguration:(nonnull TeakUserConfiguration*)userConfiguration;

/**
 * Logout the current user
 */
- (void)logout;

/**
  * If the user has authorized push notifications, manually refresh the push token.
 *
 * This is used in conjunction with the 'TeakDoNotRefreshPushToken' Plist configuration flag.
 * If 'TeakDoNotRefreshPushToken' is false, or not present, you do not need to call this method.
 */
- (void)refreshPushTokenIfAuthorized;

/**
 * Track an arbitrary event in Teak.
 *
 * @param actionId         The identifier for the action, e.g. 'complete'.
 * @param objectTypeId     The type of object that is being posted, e.g. 'quest'.
 * @param objectInstanceId The specific instance of the object, e.g. 'gather-quest-1'
 */
- (void)trackEventWithActionId:(nonnull NSString*)actionId forObjectTypeId:(nullable NSString*)objectTypeId andObjectInstanceId:(nullable NSString*)objectInstanceId;

/**
 * Increment an arbitrary event in Teak.
 *
 * @param actionId         The identifier for the action, e.g. 'complete'.
 * @param objectTypeId     The type of object that is being posted, e.g. 'quest'.
 * @param objectInstanceId The specific instance of the object, e.g. 'gather-quest-1'
 * @param count            The amount by which to increment.
 */
- (void)incrementEventWithActionId:(nonnull NSString*)actionId forObjectTypeId:(nullable NSString*)objectTypeId andObjectInstanceId:(nullable NSString*)objectInstanceId count:(int64_t)count;

/**
 * Push notification authorization state.
 *
 * If they have disabled push notifications, you can prompt them to re-enable
 * and use openSettingsAppToThisAppsSettings to open the Settings app.
 *
 * @return                Notification state, see: TeakNotificationState
 */
- (TeakNotificationState)notificationState;

/**
 * Open Settings.app to the settings for this application.
 *
 * @return                YES if Settings.app was opened.
 */
- (BOOL)openSettingsAppToThisAppsSettings;

/**
 * Set the badge number on the icon of the application.
 *
 * @param count           The number that should be displayed on the icon.
 */
- (void)setApplicationBadgeNumber:(int)count;

/**
 * Track a numeric player profile attribute.
 *
 * This functionality is also accessable from the C API:
 *    extern void TeakSetNumericAttribute(const char* cstr_key, double value);
 *
 * @param key   The name of the numeric attribute.
 * @param value The numeric value to assign.
 */
- (void)setNumericAttribute:(double)value forKey:(NSString* _Nonnull)key;

/**
 * Track a string player profile attribute.
 *
 * This functionality is also accessable from the C API:
 *    extern void TeakSetStringAttribute(const char* cstr_key, const char* cstr_value);
 *
 * @param key   The name of the string attribute.
 * @param value The string value to assign.
 */
- (void)setStringAttribute:(NSString* _Nonnull)value forKey:(NSString* _Nonnull)key;

/**
 * Get Teak's configuration data about the current device.
 *
 * @return JSON string containing device info, or null if it's not ready
 */
- (NSString* _Nullable)getDeviceConfiguration;

/**
 * Get Teak's configuration data about the current app.
 *
 * @return JSON string containing device info, or null if it's not ready
 */
- (NSString* _Nullable)getAppConfiguration;

/**
 * Process deep links.
 *
 * Deep links will be processed the sooner of:
 * - The user has been identified
 * - This method is called
 */
- (void)processDeepLinks;

/**
 * Manually pass Teak a deep link path to handle.
 *
 * This path should be prefixed with a forward slash, and can contain query parameters, e.g.
 *     /foo/bar?fizz=buzz
 * It should not contain a host, or a scheme.
 *
 * This function will only execute deep links that have been defined through Teak.
 * It has no visibility into any other SDKs or custom code.
 * @param path The deep link path to process.
 * @return true if the deep link was found and handled.
 */
- (BOOL)handleDeepLinkPath:(nonnull NSString*)path;

/**
 * Returns true if the notification was sent by Teak.
 */
+ (BOOL)isTeakNotification:(nonnull UNNotification*)notification;

/**
 * If you are setting your own UNNotificationCenter delegate, then you need to call this method from your handler.
 *
 * If this method returns true, do not call the completion handler yourself.
 */
+ (BOOL)didReceiveNotificationResponse:(nonnull UNNotificationResponse*)response
                 withCompletionHandler:(nonnull void (^)(void))completionHandler;

/**
 * If you are setting your own UNNotificationCenter delegate, then you need to call this method from your handler.
 *
 * If this method returns true, do not call the completion handler yourself.
 */
+ (BOOL)willPresentNotification:(nonnull UNNotification*)notification
          withCompletionHandler:(nonnull void (^)(UNNotificationPresentationOptions))completionHandler;
@end

#endif /* __OBJC__ */
