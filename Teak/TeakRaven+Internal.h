#pragma once

#import "TeakRaven.h"

@interface TeakRaven ()
@property (strong, nonatomic) NSURL* endpoint;
@property (strong, nonatomic) NSString* appId;
@property (strong, nonatomic) NSString* sentryKey;
@property (strong, nonatomic) NSString* sentrySecret;
@property (strong, nonatomic) NSMutableDictionary* payloadTemplate;

// Published as an immutable snapshot on every UserIdentified event (see handleEvent:) instead of
// mutated in place, so a concurrent reader (report construction, possibly on a signal handler's
// thread) always gets a fully-formed dict via an atomic getter rather than racing a mutation.
// copy freezes each new snapshot at assignment. The getter isn't strictly async-signal-safe
// (objc_getProperty takes a striped lock under the hood), but it's no worse than the rest of
// this best-effort crash reporter, and it can't self-deadlock the way a mutex or GCD queue
// could if a crash landed mid-mutation on the same thread that's reporting it.
@property (atomic, copy) NSDictionary* userContext;
@property (nonatomic) BOOL isSdkRaven;

@property (strong, nonatomic) NSArray* runLoopModes;
@property (nonatomic) NSUncaughtExceptionHandler* hException;
@property (nonatomic) void* hSIGABRT;
@property (nonatomic) void* hSIGILL;
@property (nonatomic) void* hSIGSEGV;
@property (nonatomic) void* hSIGFPE;
@property (nonatomic) void* hSIGBUS;
@property (nonatomic) void* hSIGPIPE;

- (void)reportUncaughtException:(nonnull NSException*)exception;
- (void)reportSignal:(nonnull NSString*)name;
- (void)pumpRunLoops;
@end

@interface TeakRavenReport : NSObject
@property (strong, nonatomic) NSDate* timestamp;
@property (strong, nonatomic) TeakRaven* raven;
@property (strong, nonatomic) NSMutableDictionary* payload;

- (id)initForRaven:(nonnull TeakRaven*)raven message:(nonnull NSString*)message additions:(NSDictionary*)additions;
- (id)initForRaven:(nonnull TeakRaven*)raven level:(nonnull NSString*)level message:(nonnull NSString*)message additions:(NSDictionary*)additions;

- (void)send;
@end
