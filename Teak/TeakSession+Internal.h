#pragma once

#import <stdatomic.h>

#import "TeakSession.h"

@interface TeakSession ()
// currentState/previousState are atomic: these state-machine fields are read in the
// currentSessionMutex lock domain (the class methods) but written under @synchronized(self)
// in -setState:. previousState is additionally written lock-free in the -sendUserIdentifier
// request callback, so that read is otherwise wholly unsynchronized. atomic accessors
// prevent a torn read across those boundaries.
@property (strong, atomic, readwrite) TeakState* currentState;
@property (strong, atomic) TeakState* previousState;
@property (strong, nonatomic) NSDate* startDate;
@property (strong, nonatomic) NSDate* endDate;
// countryCode/userProfile/serverSessionId are reassigned in the identify-reply request callback
// (in TeakSession.m) while read cross-thread by the heartbeat queue and the duration-report background block.
// atomic accessors hand those readers a retained snapshot so a concurrent reassignment can't free
// the value out from under them (nonatomic strong reassignment releases the prior object mid-read).
@property (strong, atomic) NSString* countryCode;
@property (strong, nonatomic) dispatch_queue_t heartbeatQueue;
@property (strong, nonatomic) dispatch_source_t heartbeat;
// Same cross-thread reassignment race as countryCode above.
@property (strong, atomic) TeakLaunchDataOperation* launchDataOperation;
@property (nonatomic) BOOL launchAttributionProcessed;
// facebookAccessToken is reassigned lock-free in -handleEvent: (arbitrary thread, e.g. the
// Facebook SDK's own callback) while sendUserIdentifier reads it under @synchronized(self) — that
// lock doesn't cover the writer, so it's the same hazard as countryCode above.
@property (strong, atomic) NSString* facebookAccessToken;

@property (strong, nonatomic, readwrite) NSString* userId;
@property (strong, nonatomic, readwrite) NSString* facebookId;
@property (strong, nonatomic, readwrite) NSString* sessionId;
@property (strong, nonatomic, readwrite) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic, readwrite) TeakDeviceConfiguration* deviceConfiguration;
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;

// Same cross-thread reassignment race as countryCode above.
@property (strong, atomic, readwrite) TeakChannelStatus* _Nonnull emailStatus;
@property (strong, atomic, readwrite) TeakChannelStatus* _Nonnull pushStatus;
@property (strong, atomic, readwrite) TeakChannelStatus* _Nonnull smsStatus;

// Same cross-thread reassignment race as countryCode above.
@property (strong, atomic, readwrite) NSDictionary* additionalData;

// Same cross-thread reassignment race as countryCode above.
@property (strong, atomic, readwrite) TeakUserProfile* userProfile;

@property (nonatomic) BOOL userIdentificationSent;
// reportDurationBlock is created and stored under @synchronized(self) in the currentState
// handler, but its background-queue body reads it lock-free to check for cancellation while
// resetReportDurationBlock cancels and frees it under the lock. atomic accessors keep that
// lock-free read from retaining a pointer the setter is releasing out from under it.
@property (strong, atomic) dispatch_block_t reportDurationBlock;
// reportDurationSent/sessionVectorClock are C11 atomics, not ObjC `atomic` properties: the
// duration-report background block writes both lock-free (see the block body in TeakSession.m), while
// sessionVectorClock is also incremented from the currentState observer's @synchronized(self).
// A plain assignment (identify-reply reset-to-0, init) is already a safe atomic store on this
// type. sessionVectorClock's `++` is a compound read-modify-write that neither a plain store nor
// an ObjC `atomic` property qualifier makes safe on its own — every increment site goes through
// -incrementSessionVectorClock/-markReportDurationSentAndIncrementSessionVectorClock (TeakSession.m), which
// use atomic_fetch_add. reportDurationSent never participates in a read-modify-write of its own
// prior value, so plain atomic load/store fully covers it.
@property (nonatomic) atomic_bool reportDurationSent;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundUpdateTask;
// Same cross-thread reassignment race as countryCode above.
@property (strong, atomic) NSString* serverSessionId;
@property (nonatomic) atomic_int sessionVectorClock;

// Set once, under deviceConfigurationObserverMutex, when this session's observers on the shared
// deviceConfiguration are removed, so the removal happens exactly once whether it comes from session
// replacement or -dealloc. See -detachDeviceConfigurationObservers.
@property (nonatomic) BOOL deviceConfigurationObserversDetached;

// Defined in TeakSession.m; declared here so the race tests can drive them directly.
- (void)detachDeviceConfigurationObservers;
+ (void)logoutReusingCurrentSession:(BOOL)reuseSession;
- (int)incrementSessionVectorClock;
- (int)markReportDurationSentAndIncrementSessionVectorClock;
// The macro-generated currentState KVO handler (see KeyValueObserverFor in TeakSession.m).
- (void)_TeakSession_currentState_ChangedFrom:(id)oldValue to:(id)newValue;
@end
