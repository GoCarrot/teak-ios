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
#import "Teak+Internal.h"
#import "TeakRequest.h"
#import "TeakRequestThread.h"

@interface TeakReward ()

@property (atomic, readwrite)    BOOL completed;
@property (nonatomic, readwrite) int rewardStatus;
@property (nonatomic, readwrite) NSString* json;

@end

@implementation TeakReward
@end

@interface TeakNotification ()

@property (nonatomic, readwrite) NSString* teakNotifId;
@property (nonatomic, readwrite) NSString* teakRewardId;
@property (nonatomic, readwrite) NSURL* deepLink;
@property (nonatomic, readwrite) NSDictionary* originalJson;
@property (atomic, readwrite)    BOOL completed;

@end

@implementation TeakNotification

+ (NSMutableDictionary*)notifications
{
   static NSMutableDictionary* notificationDict = nil;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      notificationDict = [[NSMutableDictionary alloc] init];
   });
   return notificationDict;
}

+ (TeakNotification*)notificationFromDictionary:(NSDictionary*)dictionary
{
   TeakNotification* ret = [[TeakNotification alloc] init];
   id teakNotifIdRaw = [dictionary objectForKey:@"teakNotifId"];
   id teakRewardIdRaw = [dictionary objectForKey:@"teakRewardId"];
   ret.teakNotifId = [teakNotifIdRaw isKindOfClass:[NSString class]] ? teakNotifIdRaw : [teakNotifIdRaw stringValue];
   ret.teakRewardId = [teakRewardIdRaw isKindOfClass:[NSString class]] ? teakRewardIdRaw : [teakRewardIdRaw stringValue];
   ret.deepLink = [NSURL URLWithString:[dictionary objectForKey:@"deepLink"]];
   ret.originalJson = dictionary;
   ret.completed = YES;
   [[TeakNotification notifications] setValue:ret forKey:ret.teakNotifId];
   return ret;
}

+ (TeakNotification*)notificationFromTeakNotifId:(NSString*)teakNotifId
{
   return [[TeakNotification notifications] objectForKey:teakNotifId];
}

- (NSString*)description
{
   return [NSString stringWithFormat: @"%@", self.originalJson];
}

- (TeakReward*)consume
{
   TeakReward* ret = [[TeakReward alloc] init];
   ret.completed = NO;
   ret.rewardStatus = kTeakRewardStatusUnknown;

   NSString* urlString = [NSString stringWithFormat:@"/%@/clicks", self.teakRewardId];
   TeakRequest* request = [TeakRequest requestForService:TeakRequestServiceAuth
                                              atEndpoint:urlString
                                             usingMethod:TeakRequestTypePOST
                                             withPayload:@{@"clicking_user_id" : [Teak sharedInstance].userId}
                                                callback:
                           ^(TeakRequest* request, NSHTTPURLResponse* response, NSData* data, TeakRequestThread* requestThread) {
                              
                              NSError* error = nil;
                              NSDictionary* jsonReply = [NSJSONSerialization JSONObjectWithData:data
                                                                                        options:kNilOptions
                                                                                          error:&error];
                              if(error)
                              {
                                 NSLog(@"[Teak] Error claiming Teak reward: %@", error);
                              }
                              else
                              {
                                 NSDictionary* rewardResponse = [jsonReply objectForKey:@"response"];
                                 ret.json = [rewardResponse objectForKey:@"reward"];

                                 NSString* status = [rewardResponse objectForKey:@"status"];
                                 if([status isEqualToString:@"grant_reward"])
                                 {
                                    ret.rewardStatus = kTeakRewardStatusGrantReward;
                                 }
                                 else if([status isEqualToString:@"self_click"])
                                 {
                                    ret.rewardStatus = kTeakRewardStatusSelfClick;
                                 }
                                 else if([status isEqualToString:@"already_clicked"])
                                 {
                                    ret.rewardStatus = kTeakRewardStatusAlreadyClicked;
                                 }
                                 else if([status isEqualToString:@"too_many_clicks"])
                                 {
                                    ret.rewardStatus = kTeakRewardStatusTooManyClicks;
                                 }
                                 else if([status isEqualToString:@"exceed_max_clicks_for_day"])
                                 {
                                    ret.rewardStatus = kTeakRewardStatusExceedMaxClicksForDay;
                                 }
                                 else if([status isEqualToString:@"expired"])
                                 {
                                    ret.rewardStatus = kTeakRewardStatusExpired;
                                 }
                                 else if([status isEqualToString:@"invalid_post"])
                                 {
                                    ret.rewardStatus = kTeakRewardStatusInvalidPost;
                                 }
                              }

                              // Remove from set of notifications to be claimed (eventually server-inbox)
                              [[TeakNotification notifications] removeObjectForKey:self.teakNotifId];

                              // Ready
                              ret.completed = YES;
                           }];
   [[Teak sharedInstance].requestThread processRequest:request onHost:@"rewards.gocarrot.com"];

   return ret;
}

+ (TeakNotification*)scheduleNotificationForCreative:(NSString*)creativeId withMessage:(NSString*)message secondsFromNow:(uint64_t)delay
{
   TeakNotification* ret = [[TeakNotification alloc] init];
   ret.completed = NO;

   NSDictionary* payload = @{
      @"message" : message,
      @"identifier" : creativeId,
      @"offset" : [NSNumber numberWithUnsignedLongLong:delay]
   };
   TeakRequest* request = [TeakRequest requestForService:TeakRequestServicePost
                                              atEndpoint:@"/me/local_notify"
                                             usingMethod:TeakRequestTypePOST
                                             withPayload:payload
                                                callback:
                           ^(TeakRequest* request, NSHTTPURLResponse* response, NSData* data, TeakRequestThread* requestThread) {

                              NSError* error = nil;
                              NSDictionary* jsonReply = [NSJSONSerialization JSONObjectWithData:data
                                                                                        options:kNilOptions
                                                                                          error:&error];
                              if(error)
                              {
                                 NSLog(@"[Teak] Error scheduling notification %@", error);
                              }
                              else
                              {
                                 NSString* status = [jsonReply objectForKey:@"status"];
                                 if([status isEqualToString:@"ok"])
                                 {
                                    NSDictionary* event = [jsonReply objectForKey:@"event"];
                                    ret.teakNotifId = [[event objectForKey:@"id"] stringValue];
                                 }
                                 else
                                 {
                                    ret.teakNotifId = nil;
                                 }
                              }

                              // Ready
                              ret.completed = YES;
                           }];
   [[Teak sharedInstance].requestThread processRequest:request onHost:@"gocarrot.com"];

   return ret;
}

+ (TeakNotification*)cancelScheduledNotification:(NSString*)scheduleId
{
   TeakNotification* ret = [[TeakNotification alloc] init];
   ret.completed = NO;

   TeakRequest* request = [TeakRequest requestForService:TeakRequestServicePost
                                              atEndpoint:@"/me/cancel_local_notify"
                                             usingMethod:TeakRequestTypePOST
                                             withPayload:@{@"id" : scheduleId}
                                                callback:
                           ^(TeakRequest* request, NSHTTPURLResponse* response, NSData* data, TeakRequestThread* requestThread) {

                              NSError* error = nil;
                              NSDictionary* jsonReply = [NSJSONSerialization JSONObjectWithData:data
                                                                                        options:kNilOptions
                                                                                          error:&error];
                              if(error)
                              {
                                 NSLog(@"[Teak] Error canceling notification %@", error);
                              }
                              else
                              {
                                 NSString* status = [jsonReply objectForKey:@"status"];
                                 if([status isEqualToString:@"ok"])
                                 {
                                    ret.teakNotifId = scheduleId;
                                 }
                                 else
                                 {
                                    ret.teakNotifId = nil;
                                 }
                              }

                              // Ready
                              ret.completed = YES;
                           }];
   [[Teak sharedInstance].requestThread processRequest:request onHost:@"gocarrot.com"];

   return ret;
}

@end
