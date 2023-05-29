#import "TeakPushState.h"
#import "TeakLog.h"
#import <UserNotifications/UNNotificationSettings.h>
#import <UserNotifications/UNUserNotificationCenter.h>

#ifndef __IPHONE_12_0
#define __IPHONE_12_0 120000
#endif

#define kStateChainPreferencesKey @"TeakPushStateChain"

UNNotificationSettings* UNNotificationCenterSettingsSync(void);

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
  return [self initWithState:state canShowOnLockscreen:YES canShowBadge:YES canShowInNotificationCenter:YES];
}

- (id)initWithState:(nonnull TeakState*)state canShowOnLockscreen:(BOOL)canShowOnLockscreen canShowBadge:(BOOL)canShowBadge canShowInNotificationCenter:(BOOL)canShowInNotificationCenter {
  self = [super init];
  if (self) {
    self.state = state;
    self.date = [[NSDate alloc] init];
    self.canShowOnLockscreen = canShowOnLockscreen;
    self.canShowBadge = canShowBadge;
    self.canShowInNotificationCenter = canShowInNotificationCenter;
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
      self.state = [TeakPushState NotDetermined];

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
  return @"not_determined";
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

DefineTeakState(NotDetermined, (@[ @"Provisional", @"Authorized", @"Denied" ]));
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
    if (oldStateChainEntry == nil) oldStateChainEntry = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState NotDetermined]];

    if ([oldStateChainEntry isUpdatedState:newChainEntry]) {
      NSMutableArray* mutableStateChain = self.stateChain == nil ? [[NSMutableArray alloc] init] : [self.stateChain mutableCopy];
      [mutableStateChain addObject:newChainEntry];

      // Trim the state chain to 50 max
      // NOTE: This should only get called once if we clear out the backlog.
      while (mutableStateChain.count > 50) {
        [mutableStateChain removeObjectAtIndex:0];
      }

      // Assign
      self.stateChain = mutableStateChain;

      // Persist
      NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
      [userDefaults setObject:[self serializedStateChain] forKey:kStateChainPreferencesKey];
      [userDefaults synchronize];

      TeakLog_i(@"push_state.new_state", @{@"old_state" : [oldStateChainEntry to_h], @"new_state" : [newChainEntry to_h]});
    }
  }
}

- (TeakState*)invocationOperationPushState {
  TeakPushStateChainEntry* lastEntry = [self.stateChain lastObject];
  return lastEntry == nil ? [TeakPushState NotDetermined] : lastEntry.state;
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
    TeakPushStateChainEntry* chainEntry = blockOperation.result;
    completionHandler(chainEntry.state);
  };
  [self.operationQueue addOperation:operation];
}

- (TeakPushStateChainEntry*)determineCurrentPushStateBlocking {
  TeakPushStateChainEntry* pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState NotDetermined]];

  UNNotificationSettings* settings = UNNotificationCenterSettingsSync();
  if (settings != nil) {

    switch (settings.authorizationStatus) {
      case UNAuthorizationStatusDenied: {
        pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState Denied]];
      } break;
      case UNAuthorizationStatusAuthorized: {
        pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState Authorized]
                                               canShowOnLockscreen:(settings.lockScreenSetting == UNNotificationSettingEnabled)
                                                      canShowBadge:(settings.badgeSetting == UNNotificationSettingEnabled)
                                       canShowInNotificationCenter:(settings.notificationCenterSetting == UNNotificationSettingEnabled)];
      } break;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0
      case UNAuthorizationStatusProvisional: {
        pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState Provisional]
                                               canShowOnLockscreen:(settings.lockScreenSetting == UNNotificationSettingEnabled)
                                                      canShowBadge:(settings.badgeSetting == UNNotificationSettingEnabled)
                                       canShowInNotificationCenter:(settings.notificationCenterSetting == UNNotificationSettingEnabled)];
      } break;
#endif
      case UNAuthorizationStatusNotDetermined: {
        pushState = [[TeakPushStateChainEntry alloc] initWithState:[TeakPushState NotDetermined]];
      } break;

      // UNAuthorizationStatusEphemeral
      default: {
      } break;
    }
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
    @"push_state_chain" : [self serializedStateChain]
  };
}

- (NSArray*)serializedStateChain {
  NSMutableArray* serializedStateChain = [[NSMutableArray alloc] init];
  for (TeakPushStateChainEntry* entry in self.stateChain) {
    [serializedStateChain addObject:[entry to_h]];
  }
  return serializedStateChain;
}

@end

UNNotificationSettings* UNNotificationCenterSettingsSync(void) {
  __block UNNotificationSettings* ret = nil;

  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* _Nonnull settings) {
      ret = settings;
      dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
  }

  return ret;
}
