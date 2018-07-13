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
#import <UserNotifications/UNNotificationSettings.h>
#import <UserNotifications/UNUserNotificationCenter.h>

#ifndef __IPHONE_12_0
#define __IPHONE_12_0 120000
#endif

@interface TeakPushState ()

@property (strong, nonatomic, readwrite) TeakState* currentState;

@property (strong, nonatomic) NSOperationQueue* operationQueue;

@end

@implementation TeakPushState

DefineTeakState(Unknown, (@[ @"Provisional", @"Authorized", @"Denied" ]));
DefineTeakState(Provisional, (@[ @"Authorized", @"Denied" ]));
DefineTeakState(Authorized, (@[ @"Denied" ]));
DefineTeakState(Denied, (@[ @"Authorized" ]));

- (TeakPushState*)init {
  self = [super init];
  if (self) {
    self.operationQueue = [[NSOperationQueue alloc] init];
    self.operationQueue.maxConcurrentOperationCount = 1;
    //[self.operationQueue addOperation:];
    [TeakEvent addEventHandler:self];
  }
  return self;
}

- (void)handleEvent:(TeakEvent*)event {
  switch (event.type) {
    case LifecycleActivate: {

    } break;
    default:
      break;
  }
}

- (TeakState*)invocationOperationPushState {
  return self.currentState;
}

- (NSInvocationOperation*)currentPushState {
  NSInvocationOperation* operation = [[NSInvocationOperation alloc] initWithTarget:TeakState.class selector:@selector(invocationOperationPushState) object:nil];
  [self.operationQueue addOperation:operation];
  return operation;
}

- (NSOperation*)currentPushStateOpteration {
  NSInvocationOperation* operation = [[NSInvocationOperation alloc] initWithTarget:TeakState.class selector:@selector(determineCurrentPushState) object:nil];
  __weak typeof(self) weakSelf = self;
  __weak NSInvocationOperation* weakOperation = operation;
  operation.completionBlock = ^{
    __strong typeof(self) blockSelf = weakSelf;
    __strong NSInvocationOperation* blockOperation = weakOperation;
    blockSelf.currentState = blockOperation.result;
  };
  return operation;
}

- (void)currentPushStateWithCompletionHandler:(void (^_Nonnull)(TeakState* _Nonnull))completionHandler {
  NSInvocationOperation* operation = [[NSInvocationOperation alloc] initWithTarget:TeakState.class selector:@selector(invocationOperationPushState) object:nil];
  __weak NSInvocationOperation* weakOperation = operation;
  operation.completionBlock = ^{
    __strong NSInvocationOperation* blockOperation = weakOperation;
    completionHandler(blockOperation.result);
  };
  [self.operationQueue addOperation:operation];
}

+ (TeakState*)determineCurrentPushState {
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

@end
