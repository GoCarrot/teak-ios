#import "TeakNotification.h"
#import "Teak+Internal.h"
#import "TeakRequest.h"
#import "TeakSession.h"

@interface TeakNotification ()

@property (strong, nonatomic, readwrite) NSString* teakNotifId;
@property (strong, nonatomic, readwrite) NSString* status;
@property (strong, nonatomic, readwrite) NSString* teakRewardId;
@property (strong, nonatomic, readwrite) NSURL* teakDeepLink;
@property (strong, nonatomic, readwrite) NSDictionary* originalJson;
@property (atomic, readwrite) BOOL completed;

@end

@implementation TeakNotification

- (TeakNotification*)initWithDictionary:(nonnull NSDictionary*)dictionary {
  self = [super init];
  if (self) {
    self.teakNotifId = NSStringOrNilFor([dictionary objectForKey:@"teakNotifId"]);
    self.teakRewardId = NSStringOrNilFor([dictionary objectForKey:@"teakRewardIdStr"]);
    self.originalJson = dictionary;
    self.completed = YES;
    self.status = nil;

    if ([dictionary objectForKey:@"teakDeepLink"]) {
      self.teakDeepLink = nil;
      teak_try {
        self.teakDeepLink = [NSURL URLWithString:[dictionary objectForKey:@"teakDeepLink"]];
      }
      teak_catch_report;
    } else {
      self.teakDeepLink = nil;
    }
  }
  return self;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> completed: %@;%@ teak-notif-id: %@; teak-reward-id: %@; teak-deep-link: %@; original-json: %@",
                                    NSStringFromClass([self class]),
                                    self,
                                    self.completed ? @"YES" : @"NO",
                                    self.status == nil ? @"" : [NSString stringWithFormat:@" status: %@;", self.status],
                                    self.teakNotifId,
                                    self.teakRewardId,
                                    self.teakDeepLink,
                                    self.originalJson];
}

+ (TeakNotification*)scheduleNotificationForCreative:(NSString*)creativeId withMessage:(NSString*)message secondsFromNow:(int64_t)delay {
  if (creativeId == nil || creativeId.length == 0) {
    TeakLog_e(@"notification.schedule.error", @"creativeId cannot be null or empty");

    TeakNotification* ret = [[TeakNotification alloc] init];
    ret.completed = YES;
    ret.status = @"error.parameter.creativeId";
    return ret;
  }

  if (message == nil || message.length == 0) {
    TeakLog_e(@"notification.schedule.error", @"defaultMessage cannot be null or empty");

    TeakNotification* ret = [[TeakNotification alloc] init];
    ret.completed = YES;
    ret.status = @"error.parameter.defaultMessage";
    return ret;
  }

  if (delay > 2630000 /* one month in seconds */ || delay < 0) {
    TeakLog_e(@"notification.schedule.error", @"delayInSeconds can not be negative, or greater than one month");

    TeakNotification* ret = [[TeakNotification alloc] init];
    ret.completed = YES;
    ret.status = @"error.parameter.delayInSeconds";
    return ret;
  }

  TeakNotification* ret = [[TeakNotification alloc] init];
  ret.completed = NO;

  NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
    @"message" : [message copy],
    @"identifier" : [creativeId copy],
    @"offset" : [NSNumber numberWithUnsignedLongLong:delay]
  }];

  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forEndpoint:@"/me/local_notify"
                                               withPayload:payload
                                                  callback:^(NSDictionary* reply) {
                                                    ret.status = reply[@"status"];
                                                    if ([ret.status isEqualToString:@"ok"]) {
                                                      NSDictionary* event = reply[@"event"];
                                                      ret.teakNotifId = [event[@"id"] stringValue];
                                                      TeakLog_i(@"notification.scheduled", @{@"notification" : ret.teakNotifId});
                                                    } else {
                                                      TeakLog_e(@"notification.schedule.error", @"Error scheduling notification.", @{@"response" : reply});
                                                      ret.teakNotifId = nil;
                                                    }
                                                    ret.completed = YES;
                                                  }];
    [request send];
  }];

  return ret;
}

+ (nullable TeakNotification*)scheduleNotificationForCreative:(nonnull NSString*)creativeId secondsFromNow:(int64_t)delay forUserIds:(nonnull NSArray*)userIds {
  if (creativeId == nil || creativeId.length == 0) {
    TeakLog_e(@"notification.schedule.error", @"creativeId cannot be null or empty");

    TeakNotification* ret = [[TeakNotification alloc] init];
    ret.completed = YES;
    ret.status = @"error.parameter.creativeId";
    return ret;
  }

  if (delay > 2630000 /* one month in seconds */ || delay < 0) {
    TeakLog_e(@"notification.schedule.error", @"delayInSeconds can not be negative, or greater than one month");

    TeakNotification* ret = [[TeakNotification alloc] init];
    ret.completed = YES;
    ret.status = @"error.parameter.delayInSeconds";
    return ret;
  }

  if (userIds == nil || userIds.count < 1) {
    TeakLog_e(@"notification.schedule.error", @"userIds can not be null or empty");

    TeakNotification* ret = [[TeakNotification alloc] init];
    ret.completed = YES;
    ret.status = @"error.parameter.userIds";
    return ret;
  }
  TeakNotification* ret = [[TeakNotification alloc] init];
  ret.completed = NO;

  NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
    @"user_ids" : [userIds copy],
    @"identifier" : [creativeId copy],
    @"offset" : [NSNumber numberWithUnsignedLongLong:delay]
  }];

  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forEndpoint:@"/me/long_distance_notify"
                                               withPayload:payload
                                                  callback:^(NSDictionary* reply) {
                                                    ret.status = reply[@"status"];
                                                    if ([ret.status isEqualToString:@"ok"]) {
                                                      NSError* error = nil;
                                                      NSData* jsonData = [NSJSONSerialization dataWithJSONObject:reply[@"ids"] options:0 error:&error];
                                                      if (error) {
                                                        TeakLog_e(@"notification.cancel_all.error.json", @{@"value" : reply[@"ids"], @"error" : error});
                                                        ret.teakNotifId = @"[]";
                                                      } else {
                                                        ret.teakNotifId = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                                                      }

                                                      TeakLog_i(@"notification.scheduled", @{@"notification" : ret.teakNotifId});
                                                    } else {
                                                      TeakLog_e(@"notification.schedule.error", @"Error scheduling notification.", @{@"response" : reply});
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
    TeakLog_e(@"notification.cancel.error", @"scheduleId cannot be null or empty");

    TeakNotification* ret = [[TeakNotification alloc] init];
    ret.completed = YES;
    ret.status = @"error.parameter.scheduleId";
    return ret;
  }

  TeakNotification* ret = [[TeakNotification alloc] init];
  ret.completed = NO;

  NSString* scheduleIdCopy = [scheduleId copy];
  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequest* request = [TeakRequest requestWithSession:session
                                               forEndpoint:@"/me/cancel_local_notify"
                                               withPayload:@{@"id" : scheduleIdCopy}
                                                  callback:^(NSDictionary* reply) {
                                                    ret.status = reply[@"status"];
                                                    if ([ret.status isEqualToString:@"ok"]) {
                                                      TeakLog_i(@"notification.cancel", @"Canceled notification.", @{@"notification" : scheduleIdCopy});
                                                      ret.teakNotifId = scheduleIdCopy;
                                                    } else {
                                                      TeakLog_e(@"notification.cancel.error", @"Error canceling notification.", @{@"response" : reply});
                                                    }
                                                    ret.completed = YES;
                                                  }];
    [request send];
  }];

  return ret;
}

+ (TeakNotification*)cancelAll {
  TeakNotification* ret = [[TeakNotification alloc] init];
  ret.completed = NO;

  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequest* request = [TeakRequest requestWithSession:session
        forEndpoint:@"/me/cancel_all_local_notifications"
        withPayload:@{}
        callback:^(NSDictionary* reply) {
          ret.status = reply[@"status"];

          if ([ret.status isEqualToString:@"ok"]) {
            NSError* error = nil;
            NSData* jsonData = [NSJSONSerialization dataWithJSONObject:reply[@"canceled"] options:0 error:&error];
            if (error) {
              TeakLog_e(@"notification.cancel_all.error.json", @{@"value" : reply[@"canceled"], @"error" : error});
              ret.teakNotifId = @"[]";
            } else {
              ret.teakNotifId = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }

            TeakLog_i(@"notification.cancel_all", @"Canceled all notifications.", @{@"canceled" : ret.teakNotifId});
          } else {
            TeakLog_e(@"notification.cancel_all.error", @"Error canceling all notifications.", @{@"response" : reply});
          }

          ret.completed = YES;
        }];
    [request send];
  }];

  return ret;
}

@end
