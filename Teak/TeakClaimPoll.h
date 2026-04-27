#import <Foundation/Foundation.h>

@class TeakAttributedLaunchData;

@interface TeakClaimPoll : NSObject

+ (NSTimeInterval)nextDelayAfter:(NSUInteger)attempt
                    initialDelay:(NSTimeInterval)initialDelay
                         ceiling:(NSTimeInterval)ceiling;

+ (BOOL)isTerminalStatus:(NSString*)status;

+ (NSDictionary*)buildResolvedUserInfoForReply:(NSDictionary*)reply
                                withLaunchData:(TeakAttributedLaunchData*)launchData;

+ (void)startPollForEventId:(NSString*)eventId
                 launchData:(TeakAttributedLaunchData*)launchData
               initialDelay:(NSTimeInterval)initialDelay
                    ceiling:(NSTimeInterval)ceiling;

+ (void)cancelAllPolls;

@end
