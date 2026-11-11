#pragma once

#import "TeakDeviceConfiguration.h"

@interface TeakDeviceConfiguration ()
@property (strong, nonatomic, readwrite) NSString* deviceId;
@property (strong, nonatomic, readwrite) NSString* deviceModel;
// pushToken/liveActivityPushToStartToken are reassigned from handleEvent on the event-processing
// queue; advertisingIdentifier is reassigned from getAdvertisingInformation (init, the LifecycleActivate
// event queue, and a main-queue retry); notificationDisplayEnabled is reassigned from the pushState
// operation queue's completion block. All four are read cross-thread by TeakSession's operation queue
// while building the identify payload. atomic accessors hand those readers a retained snapshot so a
// concurrent reassignment can't free the value out from under them.
@property (strong, atomic, readwrite) NSString* pushToken;
@property (strong, atomic, readwrite) NSString* liveActivityPushToStartToken;
@property (strong, nonatomic, readwrite) NSString* platformString;
@property (strong, atomic, readwrite) NSString* advertisingIdentifier;
@property (strong, atomic, readwrite) NSString* notificationDisplayEnabled;
@property (nonatomic, readwrite) BOOL limitAdTracking;
@property (nonatomic, readwrite) unsigned long long phyiscalMemoryInBytes;
@property (nonatomic, readwrite) NSUInteger numberOfCores;
@property (nonatomic, readwrite) NSDictionary* displayMetrics;

@property (strong, nonatomic) NSUserDefaults* userDefaults;
@property (nonatomic) NSUInteger rerunGetAdvertisingInformation;
@end
