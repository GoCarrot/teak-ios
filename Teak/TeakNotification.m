#import "TeakNotification.h"
#import "Teak+Internal.h"
#import "TeakRequest.h"
#import "TeakSession.h"

@implementation TeakChannelCategory

- (nonnull NSDictionary*)json {
  return @{
    @"id" : ValueOrNSNull(self.id),
    @"name" : ValueOrNSNull(self.name),
    @"description" : ValueOrNSNull(self.categoryDescription)
  };
}

@end

@interface TeakNotification ()

@property (strong, nonatomic, readwrite) NSString* teakNotifId;
@property (strong, nonatomic, readwrite) NSString* status;
@property (strong, nonatomic, readwrite) NSString* teakRewardId;
@property (strong, nonatomic, readwrite) NSString* teakDeepLink;
@property (strong, nonatomic, readwrite) NSString* _Nullable teakScheduleName;
@property (strong, nonatomic, readwrite) NSString* _Nullable teakScheduleId;
@property (strong, nonatomic, readwrite) NSString* _Nullable teakCreativeName;
@property (strong, nonatomic, readwrite) NSString* _Nullable teakCreativeId;
@property (strong, nonatomic, readwrite) NSString* _Nullable teakChannelName;
@property (strong, nonatomic, readwrite) NSString* teakOptOutCategory;
@property (strong, nonatomic, readwrite) NSDictionary* originalJson;
@property (atomic, readwrite) BOOL showInForeground;
@property (atomic, readwrite) BOOL completed;

@end

NSArray* TeakNotificationAvailableCategories = nil;

@implementation TeakNotification

+ (nullable NSArray*)categories {
  return TeakNotificationAvailableCategories;
}

- (TeakNotification*)initWithDictionary:(nonnull NSDictionary*)dictionary {
  self = [super init];
  if (self) {
    self.teakNotifId = NSStringOrNilFor(dictionary[@"teakNotifId"]);
    self.teakRewardId = NSStringOrNilFor(dictionary[@"teakRewardIdStr"]);
    self.teakDeepLink = NSStringOrNilFor(dictionary[@"teakDeepLink"]);
    self.teakScheduleName = NSStringOrNilFor(dictionary[@"teakScheduleName"]);
    self.teakScheduleId = NSStringOrNilFor(dictionary[@"teakScheduleId"]);
    self.teakCreativeName = NSStringOrNilFor(dictionary[@"teakCreativeName"]);
    self.teakCreativeId = NSStringOrNilFor(dictionary[@"teakCreativeId"]);
    self.teakChannelName = NSStringOrNilFor(dictionary[@"teakChannelName"]);
    self.teakOptOutCategory = NSStringOrNilFor(dictionary[@"teakOptOutCategory"]) == nil ? @"teak" : NSStringOrNilFor(dictionary[@"teakOptOutCategory"]);
    self.originalJson = dictionary;
    self.showInForeground = TeakBoolFor(dictionary[@"teakShowInForeground"]);
    self.completed = YES;
    self.status = nil;
  }
  return self;
}

- (NSDictionary*)eventUserInfo {
  NSMutableDictionary* teakUserInfo = [[NSMutableDictionary alloc] init];
  teakUserInfo[@"teakNotifId"] = self.teakNotifId;
  teakUserInfo[@"teakRewardId"] = ValueOrNSNull(self.teakRewardId);
  teakUserInfo[@"teakScheduleName"] = ValueOrNSNull(self.teakScheduleName);
  teakUserInfo[@"teakScheduleId"] = ValueOrNSNull(self.teakScheduleId);
  teakUserInfo[@"teakCreativeName"] = ValueOrNSNull(self.teakCreativeName);
  teakUserInfo[@"teakCreativeId"] = ValueOrNSNull(self.teakCreativeId);
  teakUserInfo[@"teakChannelName"] = ValueOrNSNull(self.teakChannelName);
  teakUserInfo[@"teakDeepLink"] = ValueOrNSNull(self.teakDeepLink);
  teakUserInfo[@"teakOptOutCategory"] = ValueOrNSNull(self.teakOptOutCategory);

  return teakUserInfo;
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

+ (nullable TeakOperation*)scheduleNotificationForCreative:(nonnull NSString*)creativeId secondsFromNow:(int64_t)delay personalizationData:(nullable NSDictionary*)personalizationData {
  TeakLog_t(@"[TeakNotification scheduleNotificationForCreative]", @{@"creativeId" : _(creativeId), @"delay" : [NSNumber numberWithLongLong:delay]});

  TeakOperationNotificationResult* result = nil;

  if (creativeId == nil || creativeId.length == 0) {
    TeakLog_e(@"notification.schedule.error", @"creativeId cannot be null or empty");
    result = [[TeakOperationNotificationResult alloc] initWithStatus:@"error" andErrors:@{@"creativeId" : @[ @"creativeId cannot be null or empty" ]}];
  }

  if (delay > 2630000 /* one month in seconds */ || delay < 0) {
    TeakLog_e(@"notification.schedule.error", @"delayInSeconds can not be negative, or greater than one month");
    result = [[TeakOperationNotificationResult alloc] initWithStatus:@"error" andErrors:@{@"delayInSeconds" : @[ @"delayInSeconds can not be negative, or greater than one month (2630000)" ]}];
  }

  if(result) {
    TeakOperation* op = [TeakOperation withResult:result];
    [[Teak sharedInstance].operationQueue addOperation:op];
    return op;
  }

  TeakOperation* op = [TeakOperation forEndpoint:@"/me/local_notify"
                                     withPayload:@{
                                       @"identifier" : [creativeId copy],
                                       @"offset" : [NSNumber numberWithUnsignedLongLong:delay],
                                       @"personalization_data" : personalizationData == nil ? [NSNull null] : [personalizationData copy]
                                     }
                                     replyParser:^id _Nullable(NSDictionary* _Nonnull reply) {
                                       TeakOperationNotificationResult* result = [[TeakOperationNotificationResult alloc] initWithStatus:reply[@"status"] andErrors:reply[@"errors"]];

                                       if (!result.error) {
                                         NSDictionary* event = reply[@"event"];
                                         NSString* teakNotifId = [event[@"id"] stringValue];
                                         result.scheduleIds = @[ teakNotifId ];

                                         TeakLog_i(@"notification.scheduled", @{@"notification" : teakNotifId});
                                       } else {
                                         TeakLog_e(@"notification.schedule.error", @"Error scheduling notification.", @{@"response" : reply});
                                       }

                                       return result;
                                     }];
  [[Teak sharedInstance].operationQueue addOperation:op];
  return op;
}

+ (TeakNotification*)scheduleNotificationForCreative:(NSString*)creativeId withMessage:(NSString*)message secondsFromNow:(int64_t)delay {
  TeakLog_t(@"[TeakNotification scheduleNotificationForCreative]", @{@"creativeId" : _(creativeId), @"message" : _(message), @"delay" : [NSNumber numberWithLongLong:delay]});

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
                                                    method:TeakRequest_POST
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
  TeakLog_t(@"[TeakNotification scheduleNotificationForCreative]", @{@"creativeId" : _(creativeId), @"delay" : [NSNumber numberWithLongLong:delay]});

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
                                                    method:TeakRequest_POST
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
  TeakLog_t(@"[TeakNotification cancelScheduledNotification]", @{@"scheduleId" : _(scheduleId)});

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
                                                    method:TeakRequest_POST
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
  TeakLog_t(@"[TeakNotification cancelAll]", @{});

  TeakNotification* ret = [[TeakNotification alloc] init];
  ret.completed = NO;

  [TeakSession whenUserIdIsOrWasReadyRun:^(TeakSession* session) {
    TeakRequest* request = [TeakRequest requestWithSession:session
        forEndpoint:@"/me/cancel_all_local_notifications"
        withPayload:@{}
        method:TeakRequest_POST
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
