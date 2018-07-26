/* Teak -- Copyright (C) 2018 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "TeakPushState.h"
#import "TeakLog.h"
#import <UserNotifications/UNNotificationSettings.h>
#import <UserNotifications/UNUserNotificationCenter.h>

#ifndef __IPHONE_12_0
#define __IPHONE_12_0 120000
#endif

#define kStateChainPreferencesKey @"TeakPushStateChain"

@interface TeakPushStateChainEntry : NSObject
@property (strong, nonatomic) TeakState* state;
@property (strong, nonatomic) NSDate* date;
@property (nonatomic) BOOL canShowOnLockscreen;
@property (nonatomic) BOOL canShowBadge;
@property (nonatomic) BOOL canShowInNotificationCenter;

- (NSDictionary*)to_h;
@end

@implementation TeakPushStateChainEntry

- (NSDictionary*)to_h {
  NSMutableDictionary* ret = [NSMutableDictionary dictionaryWithDictionary:@{
    @"state" : [self stateAsString],
    @"date" : [NSNumber numberWithDouble:[self.date timeIntervalSince1970]],
  }];

  if (self.state == [TeakPushState Provisional] || self.state == [TeakPushState Authorized]) {
    [ret addEntriesFromDictionary:@{
      @"canShowOnLockscreen" : [NSNumber numberWithBool:self.canShowOnLockscreen],
      @"canShowBadge" : [NSNumber numberWithBool:self.canShowBadge],
      @"canShowInNotificationCenter" : [NSNumber numberWithBool:self.canShowInNotificationCenter],
    }];
  }

  return ret;
}

- (id)initWithState:(nonnull TeakState*)state {
  self = [super init];
  if (self) {
    self.state = state;
    self.date = [[NSDate alloc] init];
    self.canShowOnLockscreen = YES;
    self.canShowBadge = YES;
    self.canShowInNotificationCenter = YES;
  }
  return self;
}

- (id)initWithDictionary:(nonnull NSDictionary*)dictionary {
  self = [super init];
  if (self) {
    NSString* stateString = dictionary[@"state"];
    if ([stateString isEqualToString:@"provisional"])
      self.state = [TeakPushState Provisional];
    else if ([stateString isEqualToString:@"authorized"])
      self.state = [TeakPushState Authorized];
    else if ([stateString isEqualToString:@"denied"])
      self.state = [TeakPushState Denied];
    else
      self.state = [TeakPushState Unknown];

    self.date = [NSDate dateWithTimeIntervalSince1970:[dictionary[@"date"] doubleValue]];
    self.canShowOnLockscreen = [dictionary[@"canShowOnLockscreen"] boolValue];
    self.canShowBadge = [dictionary[@"canShowBadge"] boolValue];
    self.canShowInNotificationCenter = [dictionary[@"canShowInNotificationCenter"] boolValue];
  }
  return self;
}

- (NSString*)stateAsString {
  if (self.state == [TeakPushState Provisional]) return @"provisional";
  if (self.state == [TeakPushState Authorized]) return @"authorized";
  if (self.state == [TeakPushState Denied]) return @"denied";
  return @"unknown";
}

- (BOOL)isUpdatedState:(nonnull TeakPushStateChainEntry*)entry {
  if ([self.state canTransitionToState:entry.state]) return YES;

  //if (self.state == entry.state)
  return NO;
}
@end

@interface TeakPushState ()

@property (strong, nonatomic) NSArray* stateChain;
@property (strong, nonatomic) NSOperationQueue* operationQueue;

- (TeakPushStateChainEntry*)determineCurrentPushStateBlocking;
@end

@implementation TeakPushState

DefineTeakState(Unknown, (@[ @"Provisional", @"Authorized", @"Denied" ]));
DefineTeakState(Provisional, (@[ @"Authorized", @"Denied" ]));
DefineTeakState(Authorized, (@[ @"Denied" ]));
DefineTeakState(Denied, (@[ @"Authorized" ]));

- (TeakPushState*)init {
  self = [super init];
  if (self) {
    // Get the current state chain
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSArray* serializedStateChain = [userDefaults arrayForKey:kStateChainPreferencesKey];
    NSMutableArray* deserialziedStateChain = [[NSMutableArray alloc] init];
    if (serializedStateChain != nil && serializedStateChain.count > 0) {
      for (NSDictionary* entry in serializedStateChain) {
        [deserialziedStateChain addObject:[[TeakPushStateChainEntry alloc] initWithDictionary:entry]];
      }
      self.stateChain = deserialziedStateChain;
    }

    // Create serial NSOperationQueue
    self.operationQueue = [[NSOperationQueue alloc] init];
    self.operationQueue.maxConcurrentOperationCount = 1;

    // Listen for LifecycleActivate
    [TeakEvent addEventHandler:self];
  }
  return self;
}

- (void)handleEvent:(TeakEvent*)event {
  switch (event.type) {
    case LifecycleActivate: {
      [self.operationQueue addOperation:[self assignCurrentPushStateOperation]];
    } break;
    case PushRegistered: {
      [self.operationQueue addOperation:[self assignCurrentPushStateOperation]];
    } break;
    default:
      break;
  }
}

- (void)updateCurrentState:(TeakPushStateChainEntry*)newChainEntry {
  if (newChainEntry == nil) return;

  @synchronized(self) {
    TeakPushStateChainEntry* oldStateChainEntry = [self.stateChain lastObject];
    if (oldStateChainEntry == nil) oldStateChainEntry = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState Unknown]];

    if ([oldStateChainEntry isUpdatedState:newChainEntry]) {
      NSMutableArray* mutableStateChain = self.stateChain == nil ? [[NSMutableArray alloc] init] : [self.stateChain mutableCopy];
      [mutableStateChain addObject:newChainEntry];
      self.stateChain = mutableStateChain;

      // Turn stateChain into something serializable
      NSMutableArray* serializedStateChain = [[NSMutableArray alloc] init];
      for (TeakPushStateChainEntry* entry in self.stateChain) {
        [serializedStateChain addObject:[entry to_h]];
      }

      // Persist
      NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
      [userDefaults setObject:serializedStateChain forKey:kStateChainPreferencesKey];
      [userDefaults synchronize];

      TeakLog_i(@"push_state.new_state", @{@"old_state" : [oldStateChainEntry to_h], @"new_state" : [newChainEntry to_h]});
    }
  }
}

- (TeakState*)invocationOperationPushState {
  return [self.stateChain lastObject];
}

- (NSInvocationOperation*)currentPushState {
  NSInvocationOperation* operation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(invocationOperationPushState) object:nil];
  [self.operationQueue addOperation:operation];
  return operation;
}

- (NSInvocationOperation*)assignCurrentPushStateOperation {
  NSInvocationOperation* operation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(determineCurrentPushStateBlocking) object:nil];
  __weak typeof(self) weakSelf = self;
  __weak NSInvocationOperation* weakOperation = operation;
  operation.completionBlock = ^{
    __strong typeof(self) blockSelf = weakSelf;
    __strong NSInvocationOperation* blockOperation = weakOperation;
    [blockSelf updateCurrentState:blockOperation.result];
  };
  return operation;
}

- (void)determineCurrentPushStateWithCompletionHandler:(void (^_Nonnull)(TeakState* _Nonnull))completionHandler {
  NSInvocationOperation* operation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(determineCurrentPushStateBlocking) object:nil];
  __weak NSInvocationOperation* weakOperation = operation;
  operation.completionBlock = ^{
    __strong NSInvocationOperation* blockOperation = weakOperation;
    completionHandler(blockOperation.result);
  };
  [self.operationQueue addOperation:operation];
}

- (TeakPushStateChainEntry*)determineCurrentPushStateBlocking {
  __block TeakPushStateChainEntry* pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState Unknown]];

  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* _Nonnull settings) {
      switch (settings.authorizationStatus) {
        case UNAuthorizationStatusDenied: {
          pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState Denied]];
        } break;
        case UNAuthorizationStatusAuthorized: {
          pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState Authorized]];
        } break;
        case UNAuthorizationStatusNotDetermined: {
          // Remains as state 'Unknown'
        } break;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0
        case UNAuthorizationStatusProvisional: {
          pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState Provisional]];
        } break;
#endif
      }
      dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
  } else {
    BOOL pushEnabled = [TeakPushState applicationHasRemoteNotificationsEnabled:[UIApplication sharedApplication]];
    pushState = [[TeakPushStateChainEntry alloc] initWithState:(pushEnabled ? [TeakPushState Authorized] : [TeakPushState Denied])];
  }

  return pushState;
}

+ (BOOL)applicationHasRemoteNotificationsEnabled:(UIApplication*)application {
  BOOL pushEnabled = NO;
  if ([application respondsToSelector:@selector(isRegisteredForRemoteNotifications)]) {
    pushEnabled = [application isRegisteredForRemoteNotifications];
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIRemoteNotificationType types = [application enabledRemoteNotificationTypes];
    pushEnabled = types & UIRemoteNotificationTypeAlert;
#pragma clang diagnostic pop
  }
  return pushEnabled;
}

- (NSDictionary*)to_h {
  return @{
    @"state_chain" : self.stateChain
  };
}

@end
