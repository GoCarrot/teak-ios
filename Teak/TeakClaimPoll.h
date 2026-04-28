#import <Foundation/Foundation.h>

@class TeakAttributedLaunchData;
@class TeakSession;

/// Click-time polling for server_jwt-mode claims.
///
/// When a click response carries `status: 'claim_pending'`, the SDK starts a
/// poll loop against `GET /claim_status?event_id=...` on an exponential
/// backoff schedule until the server returns a terminal status (completed or
/// failed). On terminal status, the loop:
///
/// 1. Fires `TeakOnRewardClaimResolved` carrying the polled reply merged with
///    launch-data attribution context (in-session optimization: the SDK reads
///    its own launch-data state instead of round-tripping the server-stored
///    `session_attribution` blob).
/// 2. POSTs `POST /claim_ack` so the server can mark the claim as
///    acknowledged and skip it on the next session-start sweep. Ack failure
///    is retried on the same session up to a small bounded budget; if all
///    retries exhaust, the claim is dropped and the session-start sweep on
///    next launch re-surfaces it.
///
/// All timing happens on `[NSRunLoop mainRunLoop]` via NSTimer.
///
/// Each in-flight claim holds a weak reference to the TeakSession that
/// started it. The Expiring state is a may-resume transition (the user
/// briefly opens Notification Center, App Switcher, etc.) and is *not* a
/// reason to cancel — polling continues across the flicker because the
/// session pointer is unchanged. Only the truly-terminal Expired transition
/// cancels in-flight claims. If the originating session is replaced
/// mid-poll (logout/login), in-flight replies see a session mismatch on the
/// weak ref and drop themselves.
@interface TeakClaimPoll : NSObject

/// Computes the delay for the next poll attempt. `attempt` is the
/// zero-indexed attempt count: `nextDelayAfter:0` is the initial delay,
/// `nextDelayAfter:1` is the second poll's delay, etc. The schedule is
/// `min(initialDelay * 2^attempt, ceiling)`.
+ (NSTimeInterval)nextDelayAfter:(NSUInteger)attempt
                    initialDelay:(NSTimeInterval)initialDelay
                         ceiling:(NSTimeInterval)ceiling;

/// Returns YES if a `/claim_status` reply's `status` field indicates a
/// terminal (no-further-polling-needed) state. The two terminal states are
/// `completed` and `failed`; everything else (including unknown / nil /
/// empty) keeps the poll running.
+ (BOOL)isTerminalStatus:(NSString*)status;

/// Builds the userInfo dictionary for the `TeakOnRewardClaimResolved`
/// notification. Merges the `/claim_status` reply with the launch-data
/// `to_h` attribution fields. When `launchData` is nil, returns the reply
/// alone — defensive against an unusual mid-session teardown.
///
/// Key convention: wire reply keys are snake_case (`event_id`, `status`,
/// `reward`, `customer_response`, `customer_status_code`, `teak_reward_id`),
/// attribution keys are teakCamelCase (`teakRewardId`, `teakNotifId`, etc).
/// They never alias the same logical id at the dict-key level — both
/// `teakRewardId` (the reward this launch was attributed to, from the URL or
/// notification payload) and `teak_reward_id` (the reward the server
/// authoritatively granted on this specific click) can coexist on the
/// resolved-event userInfo and are distinct fields.
+ (NSDictionary*)buildResolvedUserInfoForReply:(NSDictionary*)reply
                                withLaunchData:(TeakAttributedLaunchData*)launchData;

/// Begin polling `/claim_status` for the given event id. The poll uses
/// `initialDelay` for the first attempt and doubles up to `ceiling` for each
/// subsequent attempt. Dedupe is "the SDK is responsible for delivering this
/// event_id exactly once": if an in-flight claim already exists for the same
/// eventId — whether scheduled, mid-request, or post-resolve awaiting ack —
/// a second start is a no-op.
+ (void)startPollForEventId:(NSString*)eventId
                 launchData:(TeakAttributedLaunchData*)launchData
               initialDelay:(NSTimeInterval)initialDelay
                    ceiling:(NSTimeInterval)ceiling;

/// Cancel all in-flight claims. Called from the Expired session transition.
/// Pending timers are invalidated and the in-flight dictionary is cleared;
/// any /claim_status or /claim_ack reply that arrives after cancel sees an
/// empty dictionary and drops silently. Cross-session resolutions are
/// picked up by the session-start sweep on next launch.
+ (void)cancelAllPolls;

@end
