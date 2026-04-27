#import "TeakClaimPoll.h"

@implementation TeakClaimPoll

+ (NSTimeInterval)nextDelayAfter:(NSUInteger)attempt
                    initialDelay:(NSTimeInterval)initialDelay
                         ceiling:(NSTimeInterval)ceiling {
  return 0.0;
}

+ (BOOL)isTerminalStatus:(NSString*)status {
  return NO;
}

+ (NSDictionary*)buildResolvedUserInfoForReply:(NSDictionary*)reply
                                withLaunchData:(TeakAttributedLaunchData*)launchData {
  return nil;
}

+ (void)startPollForEventId:(NSString*)eventId
                 launchData:(TeakAttributedLaunchData*)launchData
               initialDelay:(NSTimeInterval)initialDelay
                    ceiling:(NSTimeInterval)ceiling {
}

+ (void)cancelAllPolls {
}

@end
