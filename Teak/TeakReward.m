/* Teak -- Copyright (C) 2016 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
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
                                                  callback:^(NSURLResponse* response, NSDictionary* reply) {
                                                    // TODO: Check response
                                                    if (/* DISABLES CODE */ (NO)) {
                                                      TeakLog_e(@"reward.claim_error", @{@"error" : response});
                                                    } else {
                                                      NSMutableDictionary* rewardResponse = [NSMutableDictionary dictionaryWithDictionary:reply[@"response"]];
                                                      [rewardResponse setValue:teakRewardId forKey:@"teakRewardId"];
                                                      if ([rewardResponse objectForKey:@"reward"] != nil &&
                                                          [[rewardResponse objectForKey:@"reward"] isKindOfClass:[NSString class]]) {
                                                        NSString* rewardString = [rewardResponse objectForKey:@"reward"];
                                                        NSData* rewardStringData = [rewardString dataUsingEncoding:NSUTF8StringEncoding];
                                                        NSError* error = nil;
                                                        NSDictionary* parsedReward = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:rewardStringData
                                                                                                                                    options:kNilOptions
                                                                                                                                      error:&error];
                                                        if (error == nil) {
                                                          rewardResponse[@"reward"] = parsedReward;
                                                        }
                                                      }
                                                      ret.json = rewardResponse;

                                                      NSString* status = [rewardResponse objectForKey:@"status"];
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
