#import "TeakReward.h"
#import "Teak+Internal.h"
#import "TeakRequest.h"
#import "TeakSession.h"

@interface TeakReward ()

@property (atomic, readwrite) BOOL completed;
@property (nonatomic, readwrite) int rewardStatus;
@property (strong, nonatomic, readwrite) NSDictionary* json;

@end

@implementation TeakReward
- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> completed: %@; reward-status: %d; json: %@",
                                    NSStringFromClass([self class]),
                                    self,
                                    self.completed ? @"YES" : @"NO",
                                    self.rewardStatus,
                                    self.json];
}

+ (TeakReward*)rewardForRewardId:(NSString*)teakRewardId {
  if (teakRewardId == nil || teakRewardId.length == 0) {
    TeakLog_e(@"reward.error", @"teakRewardId must not be nil or empty");
    return nil;
  }

  TeakReward* ret = [[TeakReward alloc] init];
  ret.completed = NO;
  ret.rewardStatus = kTeakRewardStatusUnknown;

  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    NSString* urlString = [NSString stringWithFormat:@"/%@/clicks", teakRewardId];
    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forHostname:[NSString stringWithFormat:@"rewards.%@", kTeakHostname]
                                              withEndpoint:urlString
                                               withPayload:@{@"clicking_user_id" : session.userId}
                                                    method:TeakRequest_POST
                                                  callback:^(NSDictionary* reply) {
                                                    NSMutableDictionary* rewardResponse = [NSMutableDictionary dictionaryWithDictionary:reply[@"response"]];
                                                    rewardResponse[@"teakRewardId"] = teakRewardId;
                                                    if (rewardResponse[@"reward"] != nil &&
                                                        [rewardResponse[@"reward"] isKindOfClass:[NSString class]]) {
                                                      NSString* rewardString = rewardResponse[@"reward"];
                                                      NSData* rewardStringData = [rewardString dataUsingEncoding:NSUTF8StringEncoding];
                                                      NSError* error = nil;
                                                      NSDictionary* parsedReward = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:rewardStringData
                                                                                                                                  options:kNilOptions
                                                                                                                                    error:&error];
                                                      if (error == nil) {
                                                        rewardResponse[@"reward"] = parsedReward;
                                                      } else {
                                                        TeakLog_e(@"reward.response.error", error);
                                                      }
                                                    }

                                                    // Assign an internal error to "status" so that the JSON sent
                                                    // to an OnReward event always contains 'status'
                                                    if (rewardResponse[@"status"] == nil) {
                                                      rewardResponse[@"status"] = @"internal_error";
                                                    }
                                                    ret.json = rewardResponse;

                                                    NSString* status = rewardResponse[@"status"];
                                                    if ([status isEqualToString:@"grant_reward"]) {
                                                      ret.rewardStatus = kTeakRewardStatusGrantReward;
                                                    } else if ([status isEqualToString:@"self_click"]) {
                                                      ret.rewardStatus = kTeakRewardStatusSelfClick;
                                                    } else if ([status isEqualToString:@"already_clicked"]) {
                                                      ret.rewardStatus = kTeakRewardStatusAlreadyClicked;
                                                    } else if ([status isEqualToString:@"too_many_clicks"]) {
                                                      ret.rewardStatus = kTeakRewardStatusTooManyClicks;
                                                    } else if ([status isEqualToString:@"exceed_max_clicks_for_day"]) {
                                                      ret.rewardStatus = kTeakRewardStatusExceedMaxClicksForDay;
                                                    } else if ([status isEqualToString:@"expired"]) {
                                                      ret.rewardStatus = kTeakRewardStatusExpired;
                                                    } else if ([status isEqualToString:@"invalid_post"]) {
                                                      ret.rewardStatus = kTeakRewardStatusInvalidPost;
                                                    }

                                                    ret.completed = YES;

                                                    if (ret.onComplete != nil) {
                                                      ret.onComplete();
                                                    }
                                                  }];
    [request send];
  }];

  return ret;
}

@end
