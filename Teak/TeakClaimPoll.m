#import "TeakClaimPoll.h"
#import "Teak+Internal.h"
#import "TeakHelpers.h"
#import "TeakLaunchData.h"
#import "TeakRemoteConfiguration.h"
#import "TeakSession.h"

// Bounded /claim_ack retry budget. Counts the initial attempt, so 3 means
// "send once, retry up to two times." After exhaustion the claim is dropped
// from the in-flight dictionary; the session-start sweep on next launch
// will re-surface the claim.
static const NSUInteger kAckMaxAttempts = 3;

// Per-event-id state held in the in-flight dictionary. An entry exists from
// the first start-poll (or sweep-enroll) call through final ack (or ack-retry
// exhaustion). The originatingSession weak-ref is the source of truth for
// "is this poll still relevant?" — same TeakSession instance during the
// Expiring→Active flicker means the poll continues; a replaced session
// (logout/login, Expired+new) means the entry's reply will be dropped.
//
// `attribution` is the eleven-key flat bag (TeakLaunchData.to_h shape) used
// to populate context on the resolved-event userInfo. The click-time path
// flattens its launch-data once at start; the session-start sweep unpacks
// the server's per-claim `session_attribution` blob into the same shape.
// Storing the dict (rather than a TeakAttributedLaunchData) decouples the
// in-flight tracker from the launch-data class hierarchy and lets both
// surfaces share the same fire/ack machinery.
@interface TeakInflightClaim : NSObject
@property (nonatomic, weak) TeakSession* originatingSession;
@property (nonatomic, copy) NSString* eventId;
@property (nonatomic, copy, nullable) NSDictionary* attribution;
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
  return [TeakClaimPoll buildResolvedUserInfoForReply:reply
                                       withAttribution:[launchData to_h]];
}

+ (NSDictionary*)buildResolvedUserInfoForReply:(NSDictionary*)reply
                               withAttribution:(NSDictionary*)attribution {
  NSMutableDictionary* userInfo = [[NSMutableDictionary alloc] init];
  if (attribution != nil) {
    [userInfo addEntriesFromDictionary:attribution];
  }
  if (reply != nil) {
    [userInfo addEntriesFromDictionary:[TeakClaimPoll normalizeWireReplyForResolvedEvent:reply]];
  }
  return userInfo;
}

// Normalize a /claim_status or /claims wire reply into the host-game-facing
// userInfo shape. Strip:
//
// * `session_attribution` — already unpacked into top-level teakCamelCase
//   attribution keys before this merge; the raw blob would just duplicate
//   that on the userInfo.
// * `created_at`, `completed_at` — server bookkeeping, not part of the
//   documented public surface.
// * `teak_reward_id` — the wire's authoritative-grant id. Resolved events
//   surface only the attribution id (`teakRewardId` from launch-data),
//   matching the legacy `TeakOnReward` semantics: id is provenance, the
//   `reward` blob carries the grant content. Host games that need to detect
//   a proxy-reward substitution read the `reward` blob, not a second id.
+ (NSDictionary*)normalizeWireReplyForResolvedEvent:(NSDictionary*)reply {
  static NSSet* stripKeys = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    stripKeys = [NSSet setWithObjects:@"session_attribution", @"created_at", @"completed_at", @"teak_reward_id", nil];
  });

  NSMutableDictionary* normalized = [NSMutableDictionary dictionaryWithCapacity:reply.count];
  for (NSString* key in reply) {
    if ([stripKeys containsObject:key]) continue;
    normalized[key] = reply[key];
  }
  return normalized;
}

#pragma mark - Lifecycle

+ (void)startPollForEventId:(NSString*)eventId
                 launchData:(TeakAttributedLaunchData*)launchData
               initialDelay:(NSTimeInterval)initialDelay
                    ceiling:(NSTimeInterval)ceiling {
  // Click-time path: flatten the launch-data to its eleven-key wire shape
  // once at start so all subsequent reads route through the same dict the
  // session-start sweep uses.
  [TeakClaimPoll startPollForEventId:eventId
                       withAttribution:[launchData to_h]
                          initialDelay:initialDelay
                               ceiling:ceiling];
}

+ (void)startPollForEventId:(NSString*)eventId
              withAttribution:(NSDictionary*)attribution
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
    claim.attribution = attribution;
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
  // Entry-point log paired with claim_resolved.delivered below: a trace can
  // distinguish "we observed terminal status and queued the event" from "we
  // actually delivered to the host game." If userId-ready never fires
  // (e.g. login never completes), the queued delivery doesn't run and the
  // delivered log is silent — but this received log proves the SDK saw
  // the resolution.
  TeakLog_i(@"claim_resolved.received", @{@"event_id" : claim.eventId});

  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:reply
                                                          withAttribution:claim.attribution];

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

#pragma mark - Session-start sweep

+ (void)startSweep {
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    [TeakClaimPoll sendClaimsListRequestForSession:session
                                         completion:^(NSArray* claims) {
                                           dispatch_async(dispatch_get_main_queue(), ^{
                                             [TeakClaimPoll dispatchSweptClaims:claims session:session];
                                           });
                                         }];
  }];
}

+ (void)dispatchSweptClaims:(NSArray*)claims session:(TeakSession*)session {
  if (![claims isKindOfClass:[NSArray class]]) {
    TeakLog_i(@"claim_sweep.empty", @{});
    return;
  }

  NSMutableDictionary<NSString*, TeakInflightClaim*>* inflight = [TeakClaimPoll inflightClaims];

  // Live sessions read the server-overridable poll cadence; the no-session
  // fallback (e.g., test paths) reads the same defaults from the class
  // method so no literal seconds live in this file.
  TeakRemoteConfiguration* remoteConfig = session.remoteConfiguration;
  NSTimeInterval initialDelay = remoteConfig != nil ? remoteConfig.claimPollInitialDelay : [TeakRemoteConfiguration defaultClaimPollInitialDelay];
  NSTimeInterval ceiling = remoteConfig != nil ? remoteConfig.claimPollCeiling : [TeakRemoteConfiguration defaultClaimPollCeiling];

  for (id rawEntry in claims) {
    if (![rawEntry isKindOfClass:[NSDictionary class]]) {
      TeakLog_i(@"claim_sweep.entry.skipped", @{@"reason" : @"not_a_dict"});
      continue;
    }
    NSDictionary* entry = (NSDictionary*)rawEntry;

    NSString* eventId = entry[@"event_id"];
    if (![eventId isKindOfClass:[NSString class]] || eventId.length == 0) {
      TeakLog_i(@"claim_sweep.entry.skipped", @{@"reason" : @"missing_event_id"});
      continue;
    }

    if (inflight[eventId] != nil) {
      // The click-time path (or an earlier sweep entry in the same response)
      // owns delivery for this event_id. Sweep is a no-op.
      TeakLog_i(@"claim_sweep.entry.duplicate", @{@"event_id" : eventId});
      continue;
    }

    NSDictionary* attribution = [TeakClaimPoll unpackSessionAttribution:entry[@"session_attribution"]];

    TeakInflightClaim* claim = [[TeakInflightClaim alloc] init];
    claim.originatingSession = session;
    claim.eventId = eventId;
    claim.attribution = attribution;
    claim.pollAttempt = 0;
    claim.initialDelay = initialDelay;
    claim.ceiling = ceiling;
    claim.ackAttempt = 0;
    inflight[eventId] = claim;

    NSString* status = entry[@"status"];
    if ([TeakClaimPoll isTerminalStatus:status]) {
      TeakLog_i(@"claim_sweep.entry.terminal", @{@"event_id" : eventId, @"status" : status});
      [TeakClaimPoll fireResolvedAndAckForClaim:claim reply:entry];
    } else {
      // Pending (or unknown / forward-compat) — enroll into the poll loop
      // without firing TeakOnRewardClaimPending. Per cross-SDK contract:
      // Pending is a point-in-time event, not a history-replay event.
      TeakLog_i(@"claim_sweep.entry.pending", @{@"event_id" : eventId});
      [TeakClaimPoll scheduleNextPollForClaim:claim];
    }
  }
}

+ (NSDictionary*)unpackSessionAttribution:(id)raw {
  if ([raw isKindOfClass:[NSDictionary class]]) {
    return (NSDictionary*)raw;
  }
  if ([raw isKindOfClass:[NSString class]]) {
    NSData* data = [(NSString*)raw dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([parsed isKindOfClass:[NSDictionary class]]) {
      return (NSDictionary*)parsed;
    }
  }
  return nil;
}

+ (void)sendClaimsListRequestForSession:(TeakSession*)session
                              completion:(void (^)(NSArray* claims))completion {
  NSString* hostname = [NSString stringWithFormat:@"rewards.%@", kTeakHostname];
  NSURLComponents* components = [NSURLComponents componentsWithString:[NSString stringWithFormat:@"https://%@/claims", hostname]];
  components.queryItems = @[
    [NSURLQueryItem queryItemWithName:@"teak_app_id" value:session.appConfiguration.appId],
    [NSURLQueryItem queryItemWithName:@"clicking_user_id" value:session.userId],
  ];

  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:components.URL];
  request.HTTPMethod = @"GET";

  TeakLog_i(@"claim_sweep.request.send", @{@"clicking_user_id" : session.userId});

  NSURLSession* urlSession = [Teak URLSessionWithoutDelegate];
  NSURLSessionDataTask* task = [urlSession dataTaskWithRequest:request
                                             completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                               NSArray* claims = @[];
                                               if (error == nil && data != nil) {
                                                 id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                                                             options:0
                                                                                               error:nil];
                                                 if ([parsed isKindOfClass:[NSDictionary class]]) {
                                                   id list = ((NSDictionary*)parsed)[@"claims"];
                                                   if ([list isKindOfClass:[NSArray class]]) {
                                                     claims = list;
                                                   }
                                                 }
                                                 TeakLog_i(@"claim_sweep.request.reply", @{@"count" : @(claims.count)});
                                               } else if (error != nil) {
                                                 TeakLog_e(@"claim_sweep.request.error", @{@"error" : error.localizedDescription});
                                               }
                                               completion(claims);
                                             }];
  [task resume];
}

@end
