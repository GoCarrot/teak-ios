#import <Foundation/Foundation.h>

@class TeakReward;

@interface TeakNotification : NSObject
@property (strong, nonatomic, readonly) NSString* _Nullable teakNotifId;
@property (strong, nonatomic, readonly) NSString* _Nullable status;
@property (strong, nonatomic, readonly) NSString* _Nullable teakRewardId;
@property (strong, nonatomic, readonly) NSDictionary* _Nullable originalJson;
@property (strong, nonatomic, readonly) NSURL* _Nullable teakDeepLink;
@property (atomic, readonly) BOOL completed;

- (nullable TeakNotification*)initWithDictionary:(nonnull NSDictionary*)dictionary;

+ (nullable TeakNotification*)scheduleNotificationForCreative:(nonnull NSString*)creativeId withMessage:(nonnull NSString*)message secondsFromNow:(int64_t)delay;
+ (nullable TeakNotification*)scheduleNotificationForCreative:(nonnull NSString*)creativeId secondsFromNow:(int64_t)delay forUserIds:(nonnull NSArray*)userIds;
+ (nullable TeakNotification*)cancelScheduledNotification:(nonnull NSString*)scheduleId;
+ (nullable TeakNotification*)cancelAll;
@end
