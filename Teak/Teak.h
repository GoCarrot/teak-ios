#include <Foundation/Foundation.h>

/**
 * Use this named notification to listen for when your app gets launched from a Teak notification.
 * 	[[NSNotificationCenter defaultCenter] addObserver:self
 * 	                                        selector:@selector(handleTeakNotification:)
 * 	                                             name:TeakNotificationAppLaunch
 * 	                                           object:nil];
 */
extern NSString* _Nonnull const TeakNotificationAppLaunch;

/**
 * Use this named notification to listen for when a reward claim is attempted.
 * 	[[NSNotificationCenter defaultCenter] addObserver:self
 * 	                                         selector:@selector(handleTeakReward:)
 * 	                                             name:TeakOnReward
 * 	                                           object:nil];
 */
extern NSString* _Nonnull const TeakOnReward;

/**
 * Use this named notification to listen for when your app receives a Teak notification while in the foreground.
 * 	[[NSNotificationCenter defaultCenter] addObserver:self
 * 	                                         selector:@selector(handleTeakForegroundNotification:)
 * 	                                             name:TeakForegroundNotification
 * 	                                           object:nil];
 */
extern NSString* _Nonnull const TeakForegroundNotification;

/**
 * Use this named notification to listen for the information about your app's Teak configuration.
 *   [[NSNotificationCenter defaultCenter] addObserver:self
 *                                            selector:@selector(handleTeakConfiguration:)
 *                                                name:TeakConfiguration
 *                                              object:nil];
 */
extern NSString* _Nonnull const TeakConfigurationData;

/**
 * Use this named notification to listen for when your app receives additional data for the current user.
 * 	[[NSNotificationCenter defaultCenter] addObserver:self
 * 	                                         selector:@selector(handleTeakAdditionalData:)
 * 	                                             name:TeakAdditionalData
 * 	                                           object:nil];
 */
extern NSString* _Nonnull const TeakAdditionalData;

/**
* Use this named notification to listen for when your app is launched from a link created by the Teak dashboard.
* 	[[NSNotificationCenter defaultCenter] addObserver:self
* 	                                         selector:@selector(handleTeakLaunchedFromLink:)
* 	                                             name:TeakLaunchedFromLink
* 	                                           object:nil];
*/
extern NSString* _Nonnull const TeakLaunchedFromLink;

/**
 * Use this named notification to listen for the information about the launch of your app.
 * 	[[NSNotificationCenter defaultCenter] addObserver:self
 * 	                                         selector:@selector(handleTeakPostLaunchSummary:)
 * 	                                             name:TeakPostLaunchSummary
 * 	                                           object:nil];
 */
extern NSString* _Nonnull const TeakPostLaunchSummary;

/**
 * Use this named notification to listen for the information about the identified user.
 *   [[NSNotificationCenter defaultCenter] addObserver:self
 *                                            selector:@selector(handleTeakUserData:)
 *                                                name:TeakUserData
 *                                              object:nil];
 */
extern NSString* _Nonnull const TeakUserData;

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
 * Values for Teak Marketing Channel States
 */
extern NSString* _Nonnull const TeakChannelStateOptOut;
extern NSString* _Nonnull const TeakChannelStateAvailable;
extern NSString* _Nonnull const TeakChannelStateOptIn;
extern NSString* _Nonnull const TeakChannelStateAbsent;
extern NSString* _Nonnull const TeakChannelStateUnknown;

extern NSString* _Nonnull const TeakChannelTypeMobilePush;
extern NSString* _Nonnull const TeakChannelTypeDesktopPush;
extern NSString* _Nonnull const TeakChannelTypePlatformPush;
extern NSString* _Nonnull const TeakChannelTypeEmail;
extern NSString* _Nonnull const TeakChannelTypeSms;
extern NSString* _Nonnull const TeakChannelTypeUnknown;

/**
 * Callback used for Log Listeners
 */
typedef void (^TeakLogListener)(NSString* _Nonnull event,
                                NSString* _Nonnull level,
                                NSDictionary* _Nullable eventData);

#ifdef __OBJC__

#import <UserNotifications/UserNotifications.h>

#import <Teak/TeakLink.h>
#import <Teak/TeakNotification.h>
#import <Teak/TeakOperation.h>
#import <Teak/TeakUserConfiguration.h>
#import <Teak/TeakReward.h>
#import <Teak/TeakSceneHooks.h>
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
 * 	  @autoreleasepool {
 * 	    // Add this line here.
 * 	    [Teak initForApplicationId:@"your_app_id"
 * 	                     withClass:[YourAppDelegate class]
 * 	                     andApiKey:@"your_api_key"];
 *
 * 	    return UIApplicationMain(argc, argv, nil,
 * 	        NSStringFromClass([YourAppDelegate class]));
 * 	  }
 * 	}
 *
 *
 * This functionality is also accessable from the C API:
 *
 * 	extern void Teak_Plant(Class appDelegateClass,
 * 	                       NSString* appId,
 * 	                       NSString* appSecret);
 *
 * @param appId            Teak Application Id
 * @param appDelegateClass Class of your application delegate, ex: [YourAppDelegate class].
 * @param apiKey           Your Teak API key.
 */
+ (void)initForApplicationId:(nonnull NSString*)appId withClass:(nonnull Class)appDelegateClass andApiKey:(nonnull NSString*)apiKey;

/**
 * Set up Teak in a single function call in SwiftUI projects
 *
 * This function *must* be called from no other place than main.swift
 * before app's main() is called. Ex:
 *
 *  import Teak
 *
 *  Teak.initSwiftUI(forApplicationId: "your_app_id", andApiKey: "your_api_key")
 *  YourApp.main()
 *
 * Be sure to remove the @main attribute from your app.
 *
 * @param appId            Teak Application Id
 * @param apiKey           Your Teak API key.
 */
+ (void)initSwiftUIForApplicationId:(nonnull NSString*)appId andApiKey:(nonnull NSString*)apiKey;

/**
 * Request push notification permissions using the OS permissions dialog
 *
 * @param callback The callback will be executed after the player has granted or denied push
 *                 notifications. The first parameter indicates if permissions were granted or
 *                 not, the second indicates any OS errors which occured in the process.
 */
+ (void)requestNotificationPermissions:(nullable void (^)(BOOL, NSError* _Nullable))callback;

/**
 * Tell Teak how to identify the current player, with additional data.
 *
 * This will also begin tracking and reporting of a session, and track a daily active user.
 *
 * @note This should be how you identify the user in your back-end.
 *
 * @param playerId              The string Teak should use to identify the current user.
 * @param playerConfiguration   Additional configuration for the current user.
 */
+ (void)login:(nonnull NSString*)playerId withConfiguration:(nonnull TeakUserConfiguration*)playerConfiguration;

/**
 * Register a deep link route that notifications, emails, or Universal Links can route to.
 *
 * @param route The route for this deep link.
 * @param name The name of this deep link, used in the Teak dashboard.
 * @param description A description for what this deep link does, used in the Teak dashboard.
 * @param block A block execute when this deep link is invoked via a notification, email or web link.
 */
+ (void)registerDeepLinkRoute:(nonnull NSString*)route name:(nonnull NSString*)name description:(nonnull NSString*)description block:(nonnull TeakLinkBlock)block;

/**
 * Track a numeric player profile attribute.
 *
 * @param key   The name of the numeric attribute.
 * @param value The numeric value to assign.
 */
+ (void)setNumberProperty:(NSString* _Nonnull)key value:(double)value;

/**
 * Track a string player profile attribute.
 *
 * @param key   The name of the string attribute.
 * @param value The string value to assign.
 */
+ (void)setStringProperty:(NSString* _Nonnull)key value:(NSString* _Nonnull)value;

/**
 * Teak singleton.
 */
+ (nullable Teak*)sharedInstance;

/**
 * Tell Teak how to identify the current user.
 *
 * This will also begin tracking and reporting of a session, and track a daily active user.
 *
 * @note This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *
 * 	extern void TeakIdentifyUser(const char* userId,
 * 	                             const char* userConfigurationJson);
 *
 * @param userId           The string Teak should use to identify the current user.
 */
- (void)identifyUser:(nonnull NSString*)userId;

/**
 * Tell Teak how to identify the current user.
 *
 * This will also begin tracking and reporting of a session, and track a daily active user.
 *
 * @note This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *
 * 	extern void TeakIdentifyUser(const char* userId,
 * 	                             const char* userConfigurationJson);
 *
 * @deprecated Use identifyUser:withConfiguration: instead
 *
 * @param userId           The string Teak should use to identify the current user.
 * @param email            The email address for the current user.
 */
- (void)identifyUser:(nonnull NSString*)userId withEmail:(nonnull NSString*)email __deprecated_msg("Use identifyUser:withConfiguration: instead");

/**
 * Tell Teak how to identify the current user, with data collection opt-out.
 *
 * This will also begin tracking and reporting of a session, and track a daily active user.
 *
 * @note This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *
 * 	extern void TeakIdentifyUser(const char* userId,
 * 	                             const char* userConfigurationJson);
 *
 * @deprecated Use identifyUser:withConfiguration: instead
 *
 * @param userId           The string Teak should use to identify the current user.
 * @param optOut           A list containing zero or more of: TeakOptOutIdfa, TeakOptOutPushKey, TeakOptOutFacebook
 */
- (void)identifyUser:(nonnull NSString*)userId withOptOutList:(nonnull NSArray*)optOut __deprecated_msg("Use identifyUser:withConfiguration: instead");

/**
 * Tell Teak how to identify the current user, with data collection opt-out.
 *
 * This will also begin tracking and reporting of a session, and track a daily active user.
 *
 * @note This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *
 * 	extern void TeakIdentifyUser(const char* userId,
 * 	                             const char* userConfigurationJson);
 *
 * @deprecated Use identifyUser:withConfiguration: instead
 *
 * @param userId           The string Teak should use to identify the current user.
 * @param optOut           A list containing zero or more of: TeakOptOutIdfa, TeakOptOutPushKey, TeakOptOutFacebook
 * @param email            The email address for the current user.
 */
- (void)identifyUser:(nonnull NSString*)userId withOptOutList:(nonnull NSArray*)optOut andEmail:(nullable NSString*)email __deprecated_msg("Use identifyUser:withConfiguration: instead");

/**
 * Tell Teak how to identify the current user, with data collection opt-out.
 *
 * This will also begin tracking and reporting of a session, and track a daily active user.
 *
 * @note This should be how you identify the user in your back-end.
 *
 * This functionality is also accessable from the C API:
 *
 * 	extern void TeakIdentifyUser(const char* userId,
 * 	                             const char* userConfigurationJson);
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
 * This is used in conjunction with the ``TeakDoNotRefreshPushToken`` Plist configuration flag.
 * If ``TeakDoNotRefreshPushToken`` is false, or not present, you do not need to call this method.
 */
- (void)refreshPushTokenIfAuthorized;

/**
 * Delete any email address associated with the current user.
 */
- (void)deleteEmail;

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
 * Can Settings.app be opened to the settings for this application.
 *
 * @note This is YES for all versions of iOS.
 *
 * @return                YES if Settings.app can be opened to the settings for this application.
 */
- (BOOL)canOpenSettingsAppToThisAppsSettings;

/**
 * Open Settings.app to the settings for this application.
 *
 * @return                YES if Settings.app was opened.
 */
- (BOOL)openSettingsAppToThisAppsSettings;

/**
 * Open can Settings.app be opened to the notification settings for this application.
 *
 * @return                YES if Settings.app can be opened to the notification settings for this application.
 */
- (BOOL)canOpenNotificationSettings;

/**
 * Open Settings.app to the notification settings for this application.
 *
 * @note This is only available on iOS 15.4 and greater, it will return NO on incompatible versions of iOS.
 *
 * @return                YES if Settings.app was opened.
 */
- (BOOL)openNotificationSettings;

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
 *
 * 	extern void TeakSetNumericAttribute(const char* cstr_key,
 * 	                                    double value);
 *
 * @param key   The name of the numeric attribute.
 * @param value The numeric value to assign.
 */
- (void)setNumericAttribute:(double)value forKey:(NSString* _Nonnull)key;

/**
 * Track a string player profile attribute.
 *
 * This functionality is also accessable from the C API:
 *
 * 	extern void TeakSetStringAttribute(const char* cstr_key,
 * 	                                   const char* cstr_value);
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
 * Get the current set of channel opt out categories. This will be null if
 * TeakConfigurationData has not yet posted.
 *
 * This functionality is also accessible from the C API:
 *   extern NSArray* TeakGetChannelCategories();
 *
 * @return NSArray<TeakChannelCategory*> if TeakConfigurationData has posted, otherwise nil.
 */
- (NSArray* _Nullable)channelCategories;

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
 *
 * 	/foo/bar?fizz=buzz
 *
 *
 * It should not contain a host, or a scheme.
 *
 * @note This function will only execute deep links that have been defined through Teak.
 * It has no visibility into any other SDKs or custom code.
 *
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

/**
 * Assign the opt-out state to a Teak Marketing Channel.
 *
 * @note You may only assign the values ``TeakChannelStateOptOut`` or ``TeakChannelStateAvailable`` to channels.
 *
 * @param state     The state to assign to the channel.
 * @param channel The channel for which the opt-out state is being assigned.
 * @return A TeakOperation which contains the status and result of the call.
 */
- (nonnull TeakOperation*)setState:(nonnull NSString*)state forChannel:(nonnull NSString*)channel;

/**
 * Assign the opt-out state to a Teak Marketing Category pair.
 *
 * @note You may only assign the values ``TeakChannelStateOptOut`` or ``TeakChannelStateAvailable`` to categories.
 *
 * @param state       The state to assign to the channel.
 * @param channel   The channel for which the opt-out state is being assigned.
 * @param category The category
 * @return A TeakOperation which contains the status and result of the call.
 */
- (nonnull TeakOperation*)setState:(nonnull NSString*)state forChannel:(nonnull NSString*)channel andCategory:(nonnull NSString*)category;

@end

#endif /* __OBJC__ */
