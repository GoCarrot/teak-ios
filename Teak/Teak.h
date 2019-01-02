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

#ifdef __OBJC__

#import <Teak/TeakLink.h>
#import <Teak/TeakNotification.h>
#import <Teak/TeakNotificationServiceCore.h>
#import <Teak/TeakNotificationViewControllerCore.h>
#import <UIKit/UIKit.h>

@interface Teak : NSObject

/**
 * Is debug logging enabled.
 *
 * Disabled by default in production, enabled otherwise.
 */
@property (nonatomic, readonly) BOOL enableDebugOutput;

/**
 * Teak SDK Version.
 */
@property (strong, nonatomic, readonly) NSString* _Nonnull sdkVersion;

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
 * @param userId           The string Teak should use to identify the current user.
 */
- (void)identifyUser:(nonnull NSString*)userId;

/**
 * Tell Teak how to identify the current user, with data collection opt-out.
 *
 * This should be how you identify the user in your back-end.
 *
 * @param userId           The string Teak should use to identify the current user.
 * @param optOut           A list containing zero or more of: TeakOptOutIdfa, TeakOptOutPushKey, TeakOptOutFacebook
 */
- (void)identifyUser:(nonnull NSString*)userId withOptOutList:(nonnull NSArray*)optOut;

/**
 * Track an arbitrary event in Teak.
 *
 * @param actionId         The identifier for the action, e.g. 'complete'.
 * @param objectTypeId     The type of object that is being posted, e.g. 'quest'.
 * @param objectInstanceId The specific instance of the object, e.g. 'gather-quest-1'
 */
- (void)trackEventWithActionId:(nonnull NSString*)actionId forObjectTypeId:(nullable NSString*)objectTypeId andObjectInstanceId:(nullable NSString*)objectInstanceId;

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
 * @param attributeName  The name of the numeric attribute.
 * @param attributeValue The numeric value to assign.
 */
- (void)setNumericAttribute:(double)value forKey:(NSString* _Nonnull)key;

/**
 * Track a string player profile attribute.
 *
 * @param attributeName  The name of the string attribute.
 * @param attributeValue The string value to assign.
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
@end

#endif /* __OBJC__ */
