#import "TeakClaimPoll.h"
#import "Teak+Internal.h"
#import "TeakHelpers.h"
#import "TeakLaunchData.h"
#import "TeakSession.h"

// In-flight polls are keyed by event_id. The dictionary is mutated only on
// the main thread (NSTimer fires on its scheduling run loop, and we schedule
// on the main run loop).
static NSMutableDictionary<NSString*, NSTimer*>* sActivePolls = nil;

@implementation TeakClaimPoll

+ (NSMutableDictionary*)activePolls {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    sActivePolls = [[NSMutableDictionary alloc] init];
  });
  return sActivePolls;
}

#pragma mark - Pure helpers

+ (NSTimeInterval)nextDelayAfter:(NSUInteger)attempt
                    initialDelay:(NSTimeInterval)initialDelay
                         ceiling:(NSTimeInterval)ceiling {
  NSTimeInterval delay = initialDelay * pow(2.0, (double)attempt);
  if (delay > ceiling) return ceiling;
  return delay;
}

+ (BOOL)isTerminalStatus:(NSString*)status {
  if (![status isKindOfClass:[NSString class]]) return NO;
  return [status isEqualToString:@"completed"] || [status isEqualToString:@"failed"];
}

+ (NSDictionary*)buildResolvedUserInfoForReply:(NSDictionary*)reply
                                withLaunchData:(TeakAttributedLaunchData*)launchData {
  NSMutableDictionary* userInfo = [[NSMutableDictionary alloc] init];
  if (launchData != nil) {
    [userInfo addEntriesFromDictionary:[launchData to_h]];
  }
  if ([reply isKindOfClass:[NSDictionary class]]) {
    [userInfo addEntriesFromDictionary:reply];
  }
  return userInfo;
}

#pragma mark - Production poll loop

+ (void)startPollForEventId:(NSString*)eventId
                 launchData:(TeakAttributedLaunchData*)launchData
               initialDelay:(NSTimeInterval)initialDelay
                    ceiling:(NSTimeInterval)ceiling {
  if (eventId == nil || eventId.length == 0) {
    TeakLog_e(@"claim_poll.error", @"event_id must not be nil or empty");
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    NSMutableDictionary* polls = [TeakClaimPoll activePolls];
    if (polls[eventId] != nil) {
      // A poll is already in flight for this event id — don't start a second.
      return;
    }

    [TeakClaimPoll scheduleNextPollForEventId:eventId
                                    launchData:launchData
                                       attempt:0
                                  initialDelay:initialDelay
                                       ceiling:ceiling];
  });
}

+ (void)cancelAllPolls {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSMutableDictionary* polls = [TeakClaimPoll activePolls];
    for (NSString* key in polls.allKeys) {
      [polls[key] invalidate];
    }
    [polls removeAllObjects];
  });
}

+ (void)scheduleNextPollForEventId:(NSString*)eventId
                        launchData:(TeakAttributedLaunchData*)launchData
                           attempt:(NSUInteger)attempt
                      initialDelay:(NSTimeInterval)initialDelay
                           ceiling:(NSTimeInterval)ceiling {
  NSTimeInterval delay = [TeakClaimPoll nextDelayAfter:attempt
                                          initialDelay:initialDelay
                                               ceiling:ceiling];

  NSDictionary* userInfo = @{
    @"event_id" : eventId,
    @"attempt" : @(attempt),
    @"initial_delay" : @(initialDelay),
    @"ceiling" : @(ceiling),
    @"launch_data" : launchData != nil ? (id)launchData : (id)[NSNull null],
  };

  NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                    target:self
                                                  selector:@selector(pollTimerFired:)
                                                  userInfo:userInfo
                                                   repeats:NO];
  [TeakClaimPoll activePolls][eventId] = timer;
}

+ (void)pollTimerFired:(NSTimer*)timer {
  NSDictionary* userInfo = timer.userInfo;
  NSString* eventId = userInfo[@"event_id"];
  NSUInteger attempt = [userInfo[@"attempt"] unsignedIntegerValue];
  NSTimeInterval initialDelay = [userInfo[@"initial_delay"] doubleValue];
  NSTimeInterval ceiling = [userInfo[@"ceiling"] doubleValue];
  id launchDataValue = userInfo[@"launch_data"];
  TeakAttributedLaunchData* launchData = (launchDataValue == [NSNull null]) ? nil : launchDataValue;

  // Clear the timer slot before we send the request — the next attempt will
  // re-key when it schedules.
  [[TeakClaimPoll activePolls] removeObjectForKey:eventId];

  [TeakClaimPoll sendClaimStatusRequestForEventId:eventId
                                       completion:^(NSDictionary* reply) {
                                         NSString* status = reply[@"status"];
                                         if ([TeakClaimPoll isTerminalStatus:status]) {
                                           [TeakClaimPoll fireResolvedAndAck:reply
                                                                      eventId:eventId
                                                                   launchData:launchData];
                                           return;
                                         }

                                         dispatch_async(dispatch_get_main_queue(), ^{
                                           [TeakClaimPoll scheduleNextPollForEventId:eventId
                                                                           launchData:launchData
                                                                              attempt:attempt + 1
                                                                         initialDelay:initialDelay
                                                                              ceiling:ceiling];
                                         });
                                       }];
}

+ (void)fireResolvedAndAck:(NSDictionary*)reply
                   eventId:(NSString*)eventId
                launchData:(TeakAttributedLaunchData*)launchData {
  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:reply
                                                          withLaunchData:launchData];

  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    [[NSNotificationCenter defaultCenter] postNotificationName:TeakOnRewardClaimResolved
                                                        object:session
                                                      userInfo:userInfo];
    [TeakClaimPoll sendClaimAckRequestForEventId:eventId session:session];
  }];
}

#pragma mark - Wire calls

+ (void)sendClaimStatusRequestForEventId:(NSString*)eventId
                              completion:(void (^)(NSDictionary* reply))completion {
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    NSString* hostname = [NSString stringWithFormat:@"rewards.%@", kTeakHostname];
    NSURLComponents* components = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"https://%@/claim_status", hostname]];
    components.queryItems = @[
      [NSURLQueryItem queryItemWithName:@"teak_app_id" value:session.appConfiguration.appId],
      [NSURLQueryItem queryItemWithName:@"clicking_user_id" value:session.userId],
      [NSURLQueryItem queryItemWithName:@"event_id" value:eventId],
    ];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:components.URL];
    request.HTTPMethod = @"GET";

    TeakLog_i(@"claim_poll.request.send", @{@"event_id" : eventId});

    NSURLSession* urlSession = [Teak URLSessionWithoutDelegate];
    NSURLSessionDataTask* task = [urlSession dataTaskWithRequest:request
                                               completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                                 NSDictionary* reply = @{};
                                                 if (error == nil && data != nil) {
                                                   NSError* parseError = nil;
                                                   id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                                                               options:0
                                                                                                 error:&parseError];
                                                   if ([parsed isKindOfClass:[NSDictionary class]]) {
                                                     reply = parsed;
                                                   }
                                                 } else if (error != nil) {
                                                   TeakLog_e(@"claim_poll.request.error", @{@"event_id" : eventId, @"error" : error.localizedDescription});
                                                 }
                                                 completion(reply);
                                               }];
    [task resume];
  }];
}

+ (void)sendClaimAckRequestForEventId:(NSString*)eventId session:(TeakSession*)session {
  NSString* hostname = [NSString stringWithFormat:@"rewards.%@", kTeakHostname];
  NSURLComponents* components = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"https://%@/claim_ack", hostname]];

  NSDictionary* payload = @{
    @"teak_app_id" : session.appConfiguration.appId,
    @"clicking_user_id" : session.userId,
    @"event_id" : eventId,
  };

  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:components.URL];
  request.HTTPMethod = @"POST";
  request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

  TeakLog_i(@"claim_ack.request.send", @{@"event_id" : eventId});

  NSURLSession* urlSession = [Teak URLSessionWithoutDelegate];
  NSURLSessionDataTask* task = [urlSession dataTaskWithRequest:request
                                             completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                               if (error != nil) {
                                                 TeakLog_e(@"claim_ack.request.error", @{@"event_id" : eventId, @"error" : error.localizedDescription});
                                               } else {
                                                 TeakLog_i(@"claim_ack.request.reply", @{@"event_id" : eventId});
                                               }
                                             }];
  [task resume];
}

@end
