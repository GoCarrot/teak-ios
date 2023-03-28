#import <Foundation/Foundation.h>

@class TeakReward;

/**
 * The structure used to represent the results of a TeakNotification operation.
 */
@interface TeakNotification : NSObject

/**
 * The identifier for the scheduled notification.
 *
 * Also accessable via:
 *
 * 	const char* TeakNotificationGetTeakNotifId(TeakNotification* notif)
 */
@property (strong, nonatomic, readonly) NSString* _Nullable teakNotifId;

/**
 * The status of the notification operation.
 *
 * This will contain the server response, or the error which prevented the operation from being sent to the server.
 *
 * Errors:
 *
 * - error.parameter.creativeId - creativeId cannot be null or empty
 * - error.parameter.delayInSeconds - delayInSeconds can not be negative, or greater than one month
 * - error.parameter.userIds - userIds can not be null or empty
 *
 * Also accessable via:
 *
 * 	const char* TeakNotificationGetStatus(TeakNotification* notif)
 */
@property (strong, nonatomic, readonly) NSString* _Nullable status;

/**
 * The identifier for the TeakReward attached to the notification, or nil.
 */
@property (strong, nonatomic, readonly) NSString* _Nullable teakRewardId;

/**
 * The name of the schedule, from the Teak dashboard, or nil.
 */
@property (strong, nonatomic, readonly) NSString* _Nullable teakScheduleName;

/**
 * The id of the schedule, from the Teak dashboard, or nil.
 */
@property (strong, nonatomic, readonly) NSString* _Nullable teakScheduleId;

/**
 * The name of the creative, from the Teak dashboard, or nil.
 */
@property (strong, nonatomic, readonly) NSString* _Nullable teakCreativeName;

/**
 * The id of the creative, from the Teak dashboard, or nil.
 */
@property (strong, nonatomic, readonly) NSString* _Nullable teakCreativeId;

/**
 * The channel name, from the Teak dashboard, or nil.
 */
@property (strong, nonatomic, readonly) NSString* _Nullable teakChannelName;

/**
 * The original JSON blob, as an NSDictionary, used to create this structure, or nil.
 */
@property (strong, nonatomic, readonly) NSDictionary* _Nullable originalJson;

/**
 * The deep link associated with this notification, or nil.
 */
@property (strong, nonatomic, readonly) NSString* _Nullable teakDeepLink;

/**
 * YES if this notification will be shown when the game is in the foreground.
 */
@property (atomic, readonly) BOOL showInForeground;

/**
 * YES if the notification operation has completed.
 *
 * Also accessable via:
 *
 * 	BOOL TeakNotificationIsCompleted(TeakNotification* notif)
 */
@property (atomic, readonly) BOOL completed;

/**
 * Schedule a notification for this user at a time in the future.
 *
 * @param creativeId The identifier of the notification in the Teak dashboard (will create if not found).
 * @param message    The default message to send, may be over-ridden in the dashboard.
 * @param delay      The delay in seconds from now to send the notification.
 */
+ (nullable TeakNotification*)scheduleNotificationForCreative:(nonnull NSString*)creativeId withMessage:(nonnull NSString*)message secondsFromNow:(int64_t)delay;

/**
 * Schedules a push notification, to be delivered to other users, for some time in the future.
 *
 * @param creativeId The identifier of the notification in the Teak dashboard, this must already exist.
 * @param delay      The delay in seconds from now to send the notification.
 * @param userIds    A list of game-assigned user ids to deliver the notification to.
 */
+ (nullable TeakNotification*)scheduleNotificationForCreative:(nonnull NSString*)creativeId secondsFromNow:(int64_t)delay forUserIds:(nonnull NSArray*)userIds;

/**
 * Cancel a previously scheduled push notification.
 *
 * @param scheduleId The schedule id of the notification to cancel.
 */
+ (nullable TeakNotification*)cancelScheduledNotification:(nonnull NSString*)scheduleId;

/**
 * Cancel all scheduled notifications.
 */
+ (nullable TeakNotification*)cancelAll;

/// @cond hide_from_doxygen
- (nullable TeakNotification*)initWithDictionary:(nonnull NSDictionary*)dictionary;
- (nonnull NSDictionary*)eventUserInfo;
/// @endcond
@end
