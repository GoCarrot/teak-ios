#import "TeakClaimPoll.h"
#import "Teak+Internal.h"
#import "TeakHelpers.h"
#import "TeakLaunchData.h"
#import "TeakSession.h"

// Bounded /claim_ack retry budget. Counts the initial attempt, so 3 means
// "send once, retry up to two times." After exhaustion the claim is dropped
// from the in-flight dictionary; the session-start sweep on next launch
// will re-surface the claim.
static const NSUInteger kAckMaxAttempts = 3;

// Per-event-id state held in the in-flight dictionary. An entry exists from
// the first start-poll call through final ack (or ack-retry exhaustion).
// The originatingSession weak-ref is the source of truth for "is this poll
// still relevant?" — same TeakSession instance during the Expiring→Active
// flicker means the poll continues; a replaced session (logout/login,
// Expired+new) means the entry's reply will be dropped.
@interface TeakInflightClaim : NSObject
@property (nonatomic, weak) TeakSession* originatingSession;
@property (nonatomic, copy) NSString* eventId;
@property (nonatomic, strong) TeakAttributedLaunchData* launchData;
@property (nonatomic, strong, nullable) NSTimer* nextPollTimer;
@property (nonatomic, assign) NSUInteger pollAttempt;
@property (nonatomic, assign) NSTimeInterval initialDelay;
@property (nonatomic, assign) NSTimeInterval ceiling;
@property (nonatomic, assign) NSUInteger ackAttempt;
@end

@implementation TeakInflightClaim
@end

// In-flight click-time claims keyed by event_id. An entry exists for as long
// as the SDK is responsible for delivering a resolved event for that id —
// from start-poll through ack-success (or ack-retry exhaustion). Mutated
// only on the main thread.
static NSMutableDictionary<NSString*, TeakInflightClaim*>* sInflightClaims = nil;

@implementation TeakClaimPoll

+ (NSMutableDictionary*)inflightClaims {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    sInflightClaims = [[NSMutableDictionary alloc] init];
  });
  return sInflightClaims;
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

#pragma mark - Lifecycle

+ (void)startPollForEventId:(NSString*)eventId
                 launchData:(TeakAttributedLaunchData*)launchData
               initialDelay:(NSTimeInterval)initialDelay
                    ceiling:(NSTimeInterval)ceiling {
  if (eventId == nil || eventId.length == 0) {
    TeakLog_e(@"claim_poll.error", @"event_id must not be nil or empty");
    return;
  }

  TeakSession* originatingSession = [TeakSession currentSessionOrNil];

  dispatch_async(dispatch_get_main_queue(), ^{
    NSMutableDictionary* claims = [TeakClaimPoll inflightClaims];
    if (claims[eventId] != nil) {
      // SDK is already responsible for delivering this event_id. Re-entrant
      // start is a no-op — the existing claim continues with its own session
      // ref, timer, and ack-retry state.
      TeakLog_i(@"claim_poll.start.duplicate", @{@"event_id" : eventId});
      return;
    }

    TeakInflightClaim* claim = [[TeakInflightClaim alloc] init];
    claim.originatingSession = originatingSession;
    claim.eventId = eventId;
    claim.launchData = launchData;
    claim.pollAttempt = 0;
    claim.initialDelay = initialDelay;
    claim.ceiling = ceiling;
    claim.ackAttempt = 0;
    claims[eventId] = claim;

    [TeakClaimPoll scheduleNextPollForClaim:claim];
  });
}

+ (void)cancelAllPolls {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSMutableDictionary<NSString*, TeakInflightClaim*>* claims = [TeakClaimPoll inflightClaims];
    for (NSString* key in claims.allKeys) {
      [claims[key].nextPollTimer invalidate];
    }
    [claims removeAllObjects];
  });
}

#pragma mark - Internal — poll loop

+ (void)scheduleNextPollForClaim:(TeakInflightClaim*)claim {
  NSTimeInterval delay = [TeakClaimPoll nextDelayAfter:claim.pollAttempt
                                          initialDelay:claim.initialDelay
                                               ceiling:claim.ceiling];

  // Pass the eventId in the timer userInfo so the fired callback can look up
  // the (still-current) claim in the dictionary. The claim object itself
  // isn't passed on the timer to avoid keeping a stale snapshot if the
  // dictionary entry is replaced or removed.
  claim.nextPollTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                         target:self
                                                       selector:@selector(pollTimerFired:)
                                                       userInfo:@{@"event_id" : claim.eventId}
                                                        repeats:NO];
}

+ (void)pollTimerFired:(NSTimer*)timer {
  NSString* eventId = timer.userInfo[@"event_id"];
  TeakInflightClaim* claim = [TeakClaimPoll inflightClaims][eventId];
  if (claim == nil) {
    // Cancelled between schedule and fire. Nothing to do.
    TeakLog_i(@"claim_poll.timer.cancelled", @{@"event_id" : eventId});
    return;
  }

  if ([TeakClaimPoll claimSessionIsStale:claim]) {
    [TeakClaimPoll dropClaim:claim reason:@"session_stale"];
    return;
  }

  [TeakClaimPoll sendClaimStatusRequestForClaim:claim
                                     completion:^(NSDictionary* reply) {
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                         [TeakClaimPoll handleClaimStatusReply:reply forEventId:eventId];
                                       });
                                     }];
}

+ (void)handleClaimStatusReply:(NSDictionary*)reply forEventId:(NSString*)eventId {
  TeakInflightClaim* claim = [TeakClaimPoll inflightClaims][eventId];
  if (claim == nil) {
    // Cancelled while the request was in flight. Drop the reply.
    TeakLog_i(@"claim_poll.reply.cancelled", @{@"event_id" : eventId});
    return;
  }

  if ([TeakClaimPoll claimSessionIsStale:claim]) {
    [TeakClaimPoll dropClaim:claim reason:@"session_stale"];
    return;
  }

  NSString* status = reply[@"status"];
  if ([TeakClaimPoll isTerminalStatus:status]) {
    [TeakClaimPoll fireResolvedAndAckForClaim:claim reply:reply];
    return;
  }

  claim.pollAttempt += 1;
  [TeakClaimPoll scheduleNextPollForClaim:claim];
}

#pragma mark - Internal — resolve + ack

+ (void)fireResolvedAndAckForClaim:(TeakInflightClaim*)claim reply:(NSDictionary*)reply {
  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:reply
                                                          withLaunchData:claim.launchData];

  // Fire the resolved event first; ack second. Per cross-SDK contract: host
  // games observe the reward grant before the server marks it acked. Ack
  // failure is retriable and does not block resolved-event delivery.
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    [[NSNotificationCenter defaultCenter] postNotificationName:TeakOnRewardClaimResolved
                                                        object:session
                                                      userInfo:userInfo];
    TeakLog_i(@"claim_resolved.delivered", @{@"event_id" : claim.eventId});

    dispatch_async(dispatch_get_main_queue(), ^{
      [TeakClaimPoll attemptAckForEventId:claim.eventId session:session];
    });
  }];
}

+ (void)attemptAckForEventId:(NSString*)eventId session:(TeakSession*)session {
  TeakInflightClaim* claim = [TeakClaimPoll inflightClaims][eventId];
  if (claim == nil) {
    // Cancelled between resolve and ack. Drop.
    TeakLog_i(@"claim_ack.cancelled", @{@"event_id" : eventId});
    return;
  }

  claim.ackAttempt += 1;
  [TeakClaimPoll sendClaimAckRequestForEventId:eventId
                                       session:session
                                    completion:^(BOOL success) {
                                      dispatch_async(dispatch_get_main_queue(), ^{
                                        [TeakClaimPoll handleAckResult:success forEventId:eventId session:session];
                                      });
                                    }];
}

+ (void)handleAckResult:(BOOL)success forEventId:(NSString*)eventId session:(TeakSession*)session {
  TeakInflightClaim* claim = [TeakClaimPoll inflightClaims][eventId];
  if (claim == nil) {
    return;
  }

  if (success) {
    [[TeakClaimPoll inflightClaims] removeObjectForKey:eventId];
    return;
  }

  if (claim.ackAttempt >= kAckMaxAttempts) {
    // Budget exhausted on this session. Drop; the session-start sweep on
    // next launch will re-surface the claim.
    TeakLog_i(@"claim_ack.retry_exhausted", @{@"event_id" : eventId, @"attempts" : @(claim.ackAttempt)});
    [[TeakClaimPoll inflightClaims] removeObjectForKey:eventId];
    return;
  }

  // Backoff between ack retries uses the same shape as the poll backoff.
  NSTimeInterval delay = [TeakClaimPoll nextDelayAfter:claim.ackAttempt - 1
                                          initialDelay:claim.initialDelay
                                               ceiling:claim.ceiling];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                 dispatch_get_main_queue(),
                 ^{
                   [TeakClaimPoll attemptAckForEventId:eventId session:session];
                 });
}

#pragma mark - Internal — helpers

+ (BOOL)claimSessionIsStale:(TeakInflightClaim*)claim {
  TeakSession* originating = claim.originatingSession;
  if (originating == nil) return YES;
  TeakSession* current = [TeakSession currentSessionOrNil];
  return originating != current;
}

+ (void)dropClaim:(TeakInflightClaim*)claim reason:(NSString*)reason {
  TeakLog_i(@"claim_poll.dropped", @{@"event_id" : claim.eventId, @"reason" : reason});
  [claim.nextPollTimer invalidate];
  claim.nextPollTimer = nil;
  [[TeakClaimPoll inflightClaims] removeObjectForKey:claim.eventId];
}

#pragma mark - Wire calls

+ (void)sendClaimStatusRequestForClaim:(TeakInflightClaim*)claim
                            completion:(void (^)(NSDictionary* reply))completion {
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    NSString* hostname = [NSString stringWithFormat:@"rewards.%@", kTeakHostname];
    NSURLComponents* components = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"https://%@/claim_status", hostname]];
    components.queryItems = @[
      [NSURLQueryItem queryItemWithName:@"teak_app_id" value:session.appConfiguration.appId],
      [NSURLQueryItem queryItemWithName:@"clicking_user_id" value:session.userId],
      [NSURLQueryItem queryItemWithName:@"event_id" value:claim.eventId],
    ];

    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:components.URL];
    request.HTTPMethod = @"GET";

    TeakLog_i(@"claim_poll.request.send", @{@"event_id" : claim.eventId});

    NSURLSession* urlSession = [Teak URLSessionWithoutDelegate];
    NSURLSessionDataTask* task = [urlSession dataTaskWithRequest:request
                                               completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                                 NSDictionary* reply = @{};
                                                 if (error == nil && data != nil) {
                                                   id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                                                               options:0
                                                                                                 error:nil];
                                                   if ([parsed isKindOfClass:[NSDictionary class]]) {
                                                     reply = parsed;
                                                   }
                                                 } else if (error != nil) {
                                                   TeakLog_e(@"claim_poll.request.error", @{@"event_id" : claim.eventId, @"error" : error.localizedDescription});
                                                 }
                                                 completion(reply);
                                               }];
    [task resume];
  }];
}

+ (void)sendClaimAckRequestForEventId:(NSString*)eventId
                              session:(TeakSession*)session
                           completion:(void (^)(BOOL success))completion {
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
                                               BOOL ok = NO;
                                               if (error == nil) {
                                                 if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                                                   NSInteger code = ((NSHTTPURLResponse*)response).statusCode;
                                                   ok = (code >= 200 && code < 300);
                                                 } else {
                                                   ok = YES;
                                                 }
                                               } else {
                                                 TeakLog_e(@"claim_ack.request.error", @{@"event_id" : eventId, @"error" : error.localizedDescription});
                                               }
                                               if (ok) {
                                                 TeakLog_i(@"claim_ack.request.reply", @{@"event_id" : eventId});
                                               }
                                               completion(ok);
                                             }];
  [task resume];
}

@end
