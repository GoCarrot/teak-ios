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

#define LOG_TAG "Teak:Notification"

@interface TeakNotification ()

@property (strong, nonatomic, readwrite) NSString* teakNotifId;
@property (strong, nonatomic, readwrite) NSString* teakRewardId;
@property (strong, nonatomic, readwrite) NSURL* teakDeepLink;
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

      if ([dictionary objectForKey:@"teakDeepLink"]) {
         @try {
            self.teakDeepLink = [NSURL URLWithString:[dictionary objectForKey:@"teakDeepLink"]];
         } @catch (NSException* exception) {
            self.teakDeepLink = nil;
            TeakLog(@"Error parsing deep link '%@'. %@", [dictionary objectForKey:@"teakDeepLink"], exception);
         }
      } else {
         self.teakDeepLink = nil;
      }
   }
   return self;
}

- (NSString*)description {
   return [NSString stringWithFormat:@"<%@: %p> completed: %@; teak-notif-id: %@; teak-reward-id: %@; teak-deep-link: %@; original-json: %@",
           NSStringFromClass([self class]),
           self,
           self.completed ? @"YES" : @"NO",
           self.teakNotifId,
           self.teakRewardId,
           self.teakDeepLink,
           self.originalJson];
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

   NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
      @"message" : message,
      @"identifier" : creativeId,
      @"offset" : [NSNumber numberWithUnsignedLongLong:delay]
   }];

   [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
      TeakRequest* request = [[TeakRequest alloc]
                              initWithSession:session
                              forEndpoint:@"/me/local_notify"
                              withPayload:payload
                              callback:^(NSURLResponse* response, NSDictionary* reply) {
                                 NSString* status = [reply objectForKey:@"status"];
                                 if ([status isEqualToString:@"ok"]) {
                                    NSDictionary* event = [reply objectForKey:@"event"];
                                    ret.teakNotifId = [[event objectForKey:@"id"] stringValue];
                                    TeakLog(@"Scheduled notification with id %@", ret.teakNotifId);
                                 } else {
                                    TeakLog(@"Error scheduling notification %@", reply);
                                    ret.teakNotifId = nil;
                                 }
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
                                 ret.completed = YES;
                              }];
      [request send];
   }];

   return ret;
}

@end
