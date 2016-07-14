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
#import "TeakNotification.h"
#import "TeakRequest.h"
#import "TeakSession.h"

#define LOG_TAG "Teak:Reward"

@interface TeakReward ()

@property (atomic, readwrite)            BOOL completed;
@property (nonatomic, readwrite)         int rewardStatus;
@property (strong, nonatomic, readwrite) NSString* json;

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
@end

@interface TeakNotification ()

@property (strong, nonatomic, readwrite) NSString* teakNotifId;
@property (strong, nonatomic, readwrite) NSString* teakRewardId;
@property (strong, nonatomic, readwrite) NSURL* deepLink;
@property (strong, nonatomic, readwrite) NSDictionary* originalJson;
@property (atomic, readwrite)            BOOL completed;

@end

@implementation TeakNotification

- (TeakNotification*)initWithDictionary:(nonnull NSDictionary*)dictionary {
   self = [super init];
   if (self) {
      self.teakNotifId = NSStringOrNilFor([dictionary objectForKey:@"teakNotifId"]);
      self.teakRewardId = NSStringOrNilFor([dictionary objectForKey:@"teakRewardId"]);
      self.originalJson = dictionary;
      self.completed = YES;

      if ([dictionary objectForKey:@"deepLink"]) {
         @try {
            self.deepLink = [NSURL URLWithString:[dictionary objectForKey:@"deepLink"]];
         } @catch (NSException* exception) {
            self.deepLink = nil;
            TeakLog(@"Error parsing deep link '%@'. %@", [dictionary objectForKey:@"deepLink"], exception);
         }
      } else {
         self.deepLink = nil;
      }
   }
   return self;
}

- (NSString*)description {
   return [NSString stringWithFormat:@"<%@: %p> completed: %@; teak-notif-id: %@; teak-reward-id: %@; deep-link: %@; original-json: %@",
           NSStringFromClass([self class]),
           self,
           self.completed ? @"YES" : @"NO",
           self.teakNotifId,
           self.teakRewardId,
           self.deepLink,
           self.originalJson];
}

- (TeakReward*)consume {
   TeakReward* ret = [[TeakReward alloc] init];
   ret.completed = NO;
   ret.rewardStatus = kTeakRewardStatusUnknown;

   [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
      NSString* urlString = [NSString stringWithFormat:@"/%@/clicks", self.teakRewardId];
      TeakRequest* request = [[TeakRequest alloc]
                              initWithSession:session
                              forEndpoint:urlString
                              withPayload:@{@"clicking_user_id" : session.userId}
                              callback:^(NSURLResponse* response, NSDictionary* reply) {
                                 // TODO: Check response
                                 if(NO) {
                                    TeakLog(@"Error claiming Teak reward: %@", response);
                                 } else {
                                    NSDictionary* rewardResponse = [reply objectForKey:@"response"];
                                    ret.json = [rewardResponse objectForKey:@"reward"];

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

                                 // Ready
                                 ret.completed = YES;
                              }];
      [request send];
   }];

   return ret;
}

+ (TeakNotification*)scheduleNotificationForCreative:(NSString*)creativeId withMessage:(NSString*)message secondsFromNow:(uint64_t)delay {
   if (creativeId == nil || creativeId.length == 0) {
      TeakLog(@"creativeId can not be nil or empty.");
      return nil;
   }

   if (message == nil || message.length == 0) {
      TeakLog(@"message can not be nil or empty.");
      return nil;
   }

   TeakNotification* ret = [[TeakNotification alloc] init];
   ret.completed = NO;

   NSDictionary* payload = @{
      @"message" : message,
      @"identifier" : creativeId,
      @"offset" : [NSNumber numberWithUnsignedLongLong:delay]
   };

   [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
      TeakRequest* request = [[TeakRequest alloc]
                              initWithSession:session
                              forEndpoint:@"/me/local_notify"
                              withPayload:payload
                              callback:^(NSURLResponse* response, NSDictionary* reply) {
                                 // TODO: Check response
                                 if (NO) {
                                    TeakLog(@"Error scheduling notification %@", response);
                                 } else {
                                    NSString* status = [reply objectForKey:@"status"];
                                    if ([status isEqualToString:@"ok"]) {
                                       NSDictionary* event = [reply objectForKey:@"event"];
                                       ret.teakNotifId = [[event objectForKey:@"id"] stringValue];
                                    } else {
                                       ret.teakNotifId = nil;
                                    }
                                 }

                                 // Ready
                                 ret.completed = YES;
                              }];
      [request send];
   }];

   return ret;
}

+ (TeakNotification*)cancelScheduledNotification:(NSString*)scheduleId {
   if (scheduleId == nil || scheduleId.length == 0) {
      TeakLog(@"scheduleId can not be nil or empty.");
      return nil;
   }

   TeakNotification* ret = [[TeakNotification alloc] init];
   ret.completed = NO;

   [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
      TeakRequest* request = [[TeakRequest alloc]
                              initWithSession:session
                              forEndpoint:@"/me/cancel_local_notify"
                              withPayload:@{@"id" : scheduleId}
                              callback:^(NSURLResponse* response, NSDictionary* reply) {
                                 // TODO: Check response
                                 if (NO) {
                                    TeakLog(@"Error canceling notification %@", response);
                                 } else {
                                    NSString* status = [reply objectForKey:@"status"];
                                    if ([status isEqualToString:@"ok"]) {
                                       ret.teakNotifId = scheduleId;
                                    } else {
                                       ret.teakNotifId = nil;
                                    }
                                 }

                                 // Ready
                                 ret.completed = YES;
                              }];
      [request send];
   }];

   return ret;
}

@end
