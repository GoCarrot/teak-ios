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
#define kStateChainEntryDateKey @"date"
#define kStateChainEntryStateKey @"state"

@interface TeakPushStateChainEntry : NSObject
+ (NSDictionary*)chainEntryForState:(TeakState*)state;
+ (TeakState*)getState:(NSDictionary*)dictionary;
+ (NSDate*)getDate:(NSDictionary*)dictionary;
@end

@implementation TeakPushStateChainEntry

+ (TeakState*)getState:(NSDictionary*)dictionary {
  return [TeakPushStateChainEntry numberToState:[dictionary objectForKey:kStateChainEntryStateKey]];
}

+ (NSDate*)getDate:(NSDictionary*)dictionary {
  return [NSDate dateWithTimeIntervalSince1970:[[dictionary objectForKey:kStateChainEntryDateKey] doubleValue]];
}

+ (TeakState*)numberToState:(NSNumber*)number {
  switch ([number integerValue]) {
    case 1:
      return [TeakPushState Provisional];
    case 2:
      return [TeakPushState Authorized];
    case 3:
      return [TeakPushState Denied];
    default:
      return [TeakPushState Unknown];
  }
}

+ (NSNumber*)stateToNumber:(TeakState*)state {
  if (state == [TeakPushState Provisional]) return [NSNumber numberWithInteger:1];
  if (state == [TeakPushState Authorized]) return [NSNumber numberWithInteger:2];
  if (state == [TeakPushState Denied]) return [NSNumber numberWithInteger:3];
  return [NSNumber numberWithInteger:0];
}

+ (nullable NSDictionary*)chainEntryForState:(TeakState*)state {
  return [TeakPushStateChainEntry chainEntryWithDictionary:@{
    kStateChainEntryStateKey : [TeakPushStateChainEntry stateToNumber:state],
    kStateChainEntryDateKey : [NSNumber numberWithDouble:[[[NSDate alloc] init] timeIntervalSince1970]]
  }];
}

+ (nullable NSDictionary*)chainEntryWithDictionary:(NSDictionary*)dictionary {
  if ([dictionary objectForKey:kStateChainEntryDateKey] == nil) {
    TeakLog_e(@"push_state.entry", @"chainEntryWithDictionary: did not include date key.");
    return nil;
  }
  if ([dictionary objectForKey:kStateChainEntryStateKey] == nil) {
    TeakLog_e(@"push_state.entry", @"chainEntryWithDictionary: did not include state key.");
    return nil;
  }
  return dictionary;
}

@end

@interface TeakPushState ()

@property (strong, nonatomic) NSArray* stateChain;
@property (strong, nonatomic) NSOperationQueue* operationQueue;

- (TeakState*)determineCurrentPushStateBlocking;
@end

@implementation TeakPushState

DefineTeakState(Unknown, (@[ @"Provisional", @"Authorized", @"Denied" ]));
DefineTeakState(Provisional, (@[ @"Authorized", @"Denied" ]));
DefineTeakState(Authorized, (@[ @"Denied" ]));
DefineTeakState(Denied, (@[ @"Authorized" ]));

- (TeakPushState*)init {
  self = [super init];
  if (self) {
    // Get the current state chain, or assign Unknown
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    self.stateChain = [userDefaults arrayForKey:kStateChainPreferencesKey];
    if (self.stateChain == nil || self.stateChain.count < 1) {
      self.stateChain = @[ [TeakPushStateChainEntry chainEntryForState:[TeakPushState Unknown]] ];
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

- (void)updateCurrentState:(TeakState*)newState {
  @synchronized(self) {
    NSDictionary* oldStateChainEntry = [self.stateChain lastObject];
    TeakState* oldState = [TeakPushStateChainEntry getState:oldStateChainEntry];
    if ([oldState canTransitionToState:newState]) {
      NSMutableArray* mutableStateChain = [self.stateChain mutableCopy];
      NSDictionary* newChainEntry = [TeakPushStateChainEntry chainEntryForState:newState];
      if (newChainEntry != nil) {
        [mutableStateChain addObject:newChainEntry];
        self.stateChain = mutableStateChain;

        // Persist
        NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
        [userDefaults setObject:self.stateChain forKey:kStateChainPreferencesKey];
        [userDefaults synchronize];

        TeakLog_i(@"push_state.new_state", @{@"old_state" : oldStateChainEntry, @"new_state" : newChainEntry});
      }
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

- (TeakState*)determineCurrentPushStateBlocking {
  __block TeakState* pushState = [TeakPushState Unknown];

  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* _Nonnull settings) {
      switch (settings.authorizationStatus) {
        case UNAuthorizationStatusDenied: {
          pushState = [TeakPushState Denied];
        } break;
        case UNAuthorizationStatusAuthorized: {
          pushState = [TeakPushState Authorized];
        } break;
        case UNAuthorizationStatusNotDetermined: {
          pushState = [TeakPushState Unknown];
        } break;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0
        case UNAuthorizationStatusProvisional: {
          pushState = [TeakPushState Provisional];
        } break;
#endif
      }
      dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
  } else {
    BOOL pushEnabled = [TeakPushState applicationHasRemoteNotificationsEnabled:[UIApplication sharedApplication]];
    pushState = (pushEnabled ? [TeakPushState Authorized] : [TeakPushState Denied]);
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
