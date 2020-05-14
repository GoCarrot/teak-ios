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
                                               forHostname:@"rewards.gocarrot.com"
                                              withEndpoint:urlString
                                               withPayload:@{@"clicking_user_id" : session.userId}
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

+ (void)checkAttributionForRewardAndDispatchEvents:(nonnull NSDictionary*)attribution {
  NSString* teakRewardId = attribution[@"teak_reward_id"];
  if (teakRewardId == nil) return;

  TeakReward* reward = [TeakReward rewardForRewardId:teakRewardId];
  if (reward == nil) return;

  NSString* teakCreativeName = attribution[@"teak_rewardlink_name"];
  if (teakCreativeName == nil) {
    teakCreativeName = attribution[@"teak_creative_name"];
  }

  __weak TeakReward* tempWeakReward = reward;
  reward.onComplete = ^() {
    __strong TeakReward* blockReward = tempWeakReward;
    if (blockReward.json != nil) {
      NSMutableDictionary* userInfo = [[NSMutableDictionary alloc] init];
#define ValueOrNSNull(x) (x == nil ? [NSNull null] : x)
      userInfo[@"teakNotifId"] = ValueOrNSNull(attribution[@"teak_notif_id"]);
      userInfo[@"teakRewardId"] = teakRewardId;
      userInfo[@"teakScheduleName"] = ValueOrNSNull(attribution[@"teak_schedule_name"]);
      userInfo[@"teakCreativeName"] = ValueOrNSNull(teakCreativeName);
      userInfo[@"teakChannelName"] = ValueOrNSNull(attribution[@"teak_channel_name"]);
      userInfo[@"incentivized"] = @YES;
      [userInfo addEntriesFromDictionary:blockReward.json];
#undef ValueOrNSNull
      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
        [[NSNotificationCenter defaultCenter] postNotificationName:TeakOnReward
                                                            object:session
                                                          userInfo:userInfo];
      }];
    }
  };
}

@end
