#import "TeakReward.h"
#import "Teak+Internal.h"
#import "TeakLaunchData.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import "TeakHelpers.h"

@interface TeakReward ()

@property (atomic, readwrite) BOOL completed;
@property (nonatomic, readwrite) int rewardStatus;
@property (strong, nonatomic, readwrite) NSDictionary* json;

@end

@implementation TeakReward

+ (TeakRewardStatus)rewardStatusForString:(NSString*)status {
  if ([status isEqualToString:@"grant_reward"]) {
    return kTeakRewardStatusGrantReward;
  } else if ([status isEqualToString:@"self_click"]) {
    return kTeakRewardStatusSelfClick;
  } else if ([status isEqualToString:@"already_clicked"]) {
    return kTeakRewardStatusAlreadyClicked;
  } else if ([status isEqualToString:@"too_many_clicks"]) {
    return kTeakRewardStatusTooManyClicks;
  } else if ([status isEqualToString:@"exceed_max_clicks_for_day"]) {
    return kTeakRewardStatusExceedMaxClicksForDay;
  } else if ([status isEqualToString:@"expired"]) {
    return kTeakRewardStatusExpired;
  } else if ([status isEqualToString:@"invalid_post"]) {
    return kTeakRewardStatusInvalidPost;
  } else if ([status isEqualToString:@"player_ineligible"]) {
    return kTeakRewardStatusPlayerIneligible;
  } else if ([status isEqualToString:@"no_reward_available"]) {
    return kTeakRewardStatusNoRewardAvailable;
  } else if ([status isEqualToString:@"claim_mode_unsupported"]) {
    return kTeakRewardStatusClaimModeUnsupported;
  }
  return kTeakRewardStatusUnknown;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> completed: %@; reward-status: %d; json: %@",
                                    NSStringFromClass([self class]),
                                    self,
                                    self.completed ? @"YES" : @"NO",
                                    self.rewardStatus,
                                    self.json];
}

+ (TeakReward*)rewardForRewardId:(NSString*)teakRewardId {
  return [TeakReward rewardForRewardId:teakRewardId withLaunchData:nil];
}

+ (NSString*)sessionAttributionStringFromLaunchData:(TeakAttributedLaunchData*)launchData {
  if (launchData == nil) return nil;

  NSDictionary* wireShape = [launchData to_h];
  NSError* error = nil;
  NSData* data = [NSJSONSerialization dataWithJSONObject:wireShape
                                                 options:0
                                                   error:&error];
  if (error != nil || data == nil) {
    TeakLog_e(@"reward.session_attribution.encode_error", error);
    return nil;
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (TeakReward*)rewardForRewardId:(NSString*)teakRewardId withLaunchData:(TeakAttributedLaunchData*)launchData {
  if (teakRewardId == nil || teakRewardId.length == 0) {
    TeakLog_e(@"reward.error", @"teakRewardId must not be nil or empty");
    return nil;
  }

  TeakReward* ret = [[TeakReward alloc] init];
  ret.completed = NO;
  ret.rewardStatus = kTeakRewardStatusUnknown;

  NSString* sessionAttribution = [TeakReward sessionAttributionStringFromLaunchData:launchData];

  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    NSString* urlString = [NSString stringWithFormat:@"/%@/clicks", teakRewardId];

    NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
      @"clicking_user_id" : session.userId,
      @"claim_mode" : session.appConfiguration.claimMode,
    }];
    if (sessionAttribution != nil) {
      payload[@"session_attribution"] = sessionAttribution;
    }

    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forHostname:[NSString stringWithFormat:@"rewards.%@", kTeakHostname]
                                              withEndpoint:urlString
                                               withPayload:payload
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

                                                    ret.rewardStatus = [TeakReward rewardStatusForString:rewardResponse[@"status"]];

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
