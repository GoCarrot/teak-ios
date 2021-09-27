#import <Foundation/Foundation.h>

@class TeakNotification;

@interface TeakLaunchDataOperation : NSInvocationOperation
+ (TeakLaunchDataOperation*)fromUniversalLink:(NSURL*)url;
+ (TeakLaunchDataOperation*)fromOpenUrl:(NSURL*)url;
+ (TeakLaunchDataOperation*)fromPushNotification:(TeakNotification*)teakNotification;
+ (TeakLaunchDataOperation*)unattributed;
@end

@interface TeakLaunchData : NSObject
@property (copy, nonatomic, readonly) NSURL* launchUrl;

- (void)updateDeepLink:(NSURL*)url;
- (NSDictionary*)sessionAttribution;
- (NSDictionary*)to_h;
@end

@interface TeakAttributedLaunchData : TeakLaunchData
@property (copy, nonatomic, readonly) NSString* scheduleName;
@property (copy, nonatomic, readonly) NSString* scheduleId;
@property (copy, nonatomic, readonly) NSString* creativeName;
@property (copy, nonatomic, readonly) NSString* creativeId;
@property (copy, nonatomic, readonly) NSString* channelName;
@property (copy, nonatomic, readonly) NSString* rewardId;

- (NSDictionary*)sessionAttribution;
@end

@interface TeakNotificationLaunchData : TeakAttributedLaunchData
@property (copy, nonatomic, readonly) NSString* sourceSendId;

- (NSDictionary*)sessionAttribution;
@end

@interface TeakRewardlinkLaunchData : TeakAttributedLaunchData
@property (copy, nonatomic, readonly) NSURL* shortLink;
@end
