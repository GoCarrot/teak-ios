#import <Foundation/Foundation.h>

@class TeakNotification;

@interface TeakLaunchDataOperation : NSInvocationOperation
+ (TeakLaunchDataOperation*)fromUniversalLink:(NSURL*)url;
+ (TeakLaunchDataOperation*)fromOpenUrl:(NSURL*)url;
+ (TeakLaunchDataOperation*)fromPushNotification:(TeakNotification*)teakNotification;
+ (TeakLaunchDataOperation*)fromLiveActivityTap:(NSString*)systemActivityId;
+ (TeakLaunchDataOperation*)fromUserActivity:(NSUserActivity*)userActivity;
+ (TeakLaunchDataOperation*)unattributed;

- (TeakLaunchDataOperation*)updateDeepLink:(NSURL*)updatedDeepLink withLaunchLink:(NSURL*)launchLink;
@end

@interface TeakLaunchData : NSObject
@property (copy, nonatomic, readonly) NSURL* launchUrl;

- (NSDictionary*)sessionAttribution;
- (NSDictionary*)to_h;
- (void)updateDeepLink:(NSURL*)updatedDeepLink;
@end

@interface TeakAttributedLaunchData : TeakLaunchData
@property (copy, nonatomic, readonly) NSString* scheduleName;
@property (copy, nonatomic, readonly) NSString* scheduleId;
@property (copy, nonatomic, readonly) NSString* creativeName;
@property (copy, nonatomic, readonly) NSString* creativeId;
@property (copy, nonatomic, readonly) NSString* channelName;
@property (copy, nonatomic, readonly) NSString* rewardId;
@property (copy, nonatomic, readonly) NSURL* deepLink;
@property (copy, nonatomic, readonly) NSString* optOutCategory;

- (NSDictionary*)sessionAttribution;
- (void)updateDeepLink:(NSURL*)updatedDeepLink;
@end

@interface TeakNotificationLaunchData : TeakAttributedLaunchData
@property (copy, nonatomic, readonly) NSString* sourceSendId;

- (NSDictionary*)sessionAttribution;
- (void)updateDeepLink:(NSURL*)updatedDeepLink;
@end

@interface TeakRewardlinkLaunchData : TeakAttributedLaunchData
@end

@interface TeakLiveActivityLaunchData : TeakAttributedLaunchData
@property (copy, nonatomic, readonly) NSString* systemActivityId;

- (NSDictionary*)sessionAttribution;
@end
