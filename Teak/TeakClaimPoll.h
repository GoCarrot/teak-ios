#import <Foundation/Foundation.h>

@class TeakAttributedLaunchData;
@class TeakSession;

/// Polling and resolve/ack delivery for server_jwt-mode claims.
///
/// Two surfaces drive entries into the same in-flight tracker:
///
/// * **Click-time path** — when a click response carries
///   `status: 'claim_pending'`, the SDK starts a poll loop against
///   `GET /claim_status?event_id=...` on an exponential backoff schedule.
///   Attribution comes from the host launch-data the click was minted with
///   (in-session optimization: SDK reads its own state instead of
///   round-tripping the persisted `session_attribution` blob).
/// * **Session-start sweep** — at user-identify time, the SDK pulls
///   `GET /claims?clicking_user_id=...`, the unacked-claims list for the
///   current user. Terminal entries fire resolved+ack immediately;
///   pending entries enroll into the same poll loop the click-time path
///   uses. Pending sweep entries do NOT re-fire `TeakOnRewardClaimPending`
///   — that is a point-in-time event, not a history-replay event. Per-claim
///   attribution is unpacked from the server's `session_attribution` blob.
///
/// On terminal status (from either surface) the loop:
///
/// 1. Fires `TeakOnRewardClaimResolved` carrying the wire reply merged with
///    the per-claim attribution context.
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
/// `reward`, `customer_response`, `customer_status_code`, `claim_source`,
/// `created_at`, `completed_at`, `acked_at`); attribution keys are
/// teakCamelCase (`teakRewardId`, `teakNotifId`, etc).
///
/// Two wire keys are stripped from the merge:
///
/// * `teak_reward_id` — the wire's authoritative-grant id. Resolved events
///   surface only the attribution id (`teakRewardId` from launch-data),
///   matching legacy `TeakOnReward` semantics. Host games that need the
///   server-authoritative grant id correlate by `event_id` against
///   `TeakOnRewardJwtIssued` / `TeakOnRewardClaimPending`.
/// * `session_attribution` — the raw eleven-key blob is unpacked into
///   discrete top-level attribution keys before this merge; keeping the raw
///   blob would just duplicate the unpacked surface.
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

/// Run the session-start sweep: pull the unacked-claims list for the
/// current user from `GET /claims` and dispatch each entry. Terminal
/// entries fire `TeakOnRewardClaimResolved` and ack immediately; pending
/// entries enroll into the click-time poll loop.
///
/// Idempotent across the click-time path: a sweep entry whose `event_id`
/// is already in the in-flight dictionary is a no-op (the click-time
/// poll, mid-request, or post-resolve ack-retry, owns delivery). Safe to
/// call on every UserIdentified transition — entries that were dropped
/// on Expired re-surface on the next launch via at-least-once delivery.
+ (void)startSweep;

@end
