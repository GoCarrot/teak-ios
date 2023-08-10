#import "TeakSession.h"
#import "AdditionalDataEvent.h"
#import "FacebookAccessTokenEvent.h"
#import "Teak+Internal.h"
#import "TeakAppConfiguration.h"
#import "TeakDebugConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakLaunchData.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest.h"
#import "TeakReward.h"
#import "TeakUserProfile.h"
#import "UserDataEvent.h"
#import "UserIdEvent.h"

NSTimeInterval TeakSameSessionDeltaSeconds = 120.0;

TeakSession* currentSession;
NSString* const currentSessionMutex = @"TeakCurrentSessionMutex";

NSString* const TeakOptedIn = @"opted_in";
NSString* const TeakOptedOut = @"opted_out";
NSString* const TeakAvailable = @"available";

extern BOOL TeakLink_HandleDeepLink(NSURL* deepLink);
extern BOOL TeakLink_WillHandleDeepLink(NSURL* deepLink);

@interface TeakSession ()
@property (strong, nonatomic, readwrite) TeakState* currentState;
@property (strong, nonatomic) TeakState* previousState;
@property (strong, nonatomic) NSDate* startDate;
@property (strong, nonatomic) NSDate* endDate;
@property (strong, nonatomic) NSString* countryCode;
@property (strong, nonatomic) dispatch_queue_t heartbeatQueue;
@property (strong, nonatomic) dispatch_source_t heartbeat;
@property (strong, nonatomic) TeakLaunchDataOperation* launchDataOperation;
@property (nonatomic) BOOL launchAttributionProcessed;
@property (strong, nonatomic) NSString* facebookAccessToken;

@property (strong, nonatomic, readwrite) NSString* userId;
@property (strong, nonatomic, readwrite) NSString* facebookId;
@property (strong, nonatomic, readwrite) NSString* sessionId;
@property (strong, nonatomic, readwrite) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic, readwrite) TeakDeviceConfiguration* deviceConfiguration;
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;

@property (strong, nonatomic, readwrite) TeakChannelStatus* _Nonnull emailStatus;
@property (strong, nonatomic, readwrite) TeakChannelStatus* _Nonnull pushStatus;
@property (strong, nonatomic, readwrite) TeakChannelStatus* _Nonnull smsStatus;

@property (strong, nonatomic, readwrite) NSDictionary* additionalData;

@property (strong, nonatomic, readwrite) TeakUserProfile* userProfile;

@property (nonatomic) BOOL userIdentificationSent;
@property (strong, nonatomic) dispatch_block_t reportDurationBlock;
@property (nonatomic) BOOL reportDurationSent;
@property (nonatomic) UIBackgroundTaskIdentifier backgroundUpdateTask;
@property (strong, nonatomic) NSString* serverSessionId;
@property int sessionVectorClock;
@end

@implementation TeakSession

DefineTeakState(Allocated, (@[ @"Created", @"Expiring" ]));
DefineTeakState(Created, (@[ @"Configured", @"Expiring" ]));
DefineTeakState(Configured, (@[ @"IdentifyingUser", @"Expiring" ]));
DefineTeakState(IdentifyingUser, (@[ @"UserIdentified", @"Expiring" ]));
DefineTeakState(UserIdentified, (@[ @"IdentifyingUser", @"Expiring" ]));
DefineTeakState(Expiring, (@[ @"Allocated", @"Created", @"Configured", @"IdentifyingUser", @"UserIdentified", @"Expired" ]));
DefineTeakState(Expired, (@[]));

+ (NSMutableArray*)whenUserIdIsReadyRunBlocks {
  static NSMutableArray* ret = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    ret = [[NSMutableArray alloc] init];
  });
  return ret;
}

+ (NSMutableArray*)whenDeviceIsAwakeRunBlocks {
  static NSMutableArray* ret = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    ret = [[NSMutableArray alloc] init];
  });
  return ret;
}

+ (void)whenDeviceIsAwakeRun:(nonnull void (^)(void))block {
  @synchronized(currentSessionMutex) {
    if (currentSession.currentState != [TeakSession Expiring] && currentSession.currentState != [TeakSession Expired]) {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        block();
      });
    } else {
      [[TeakSession whenDeviceIsAwakeRunBlocks] addObject:[block copy]];
    }
  }
}

+ (void)whenUserIdIsReadyRun:(nonnull UserIdReadyBlock)block {
  @synchronized(currentSessionMutex) {
    if (currentSession != nil && currentSession.currentState == [TeakSession UserIdentified]) {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        block(currentSession);
      });
    } else {
      [[TeakSession whenUserIdIsReadyRunBlocks] addObject:[block copy]];
    }
  }
}

+ (void)whenUserIdIsOrWasReadyRun:(nonnull UserIdReadyBlock)block {
  @synchronized(currentSessionMutex) {
    if (currentSession != nil && (currentSession.currentState == [TeakSession UserIdentified] ||
                                  (currentSession.currentState == [TeakSession Expiring] &&
                                   currentSession.previousState == [TeakSession UserIdentified]))) {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        block(currentSession);
      });
    } else {
      [[TeakSession whenUserIdIsReadyRunBlocks] addObject:[block copy]];
    }
  }
}

- (BOOL)setState:(nonnull TeakState*)newState {
  @synchronized(self) {
    if (self.currentState == newState) {
      TeakLog_i(@"session.same_state", @{@"state" : self.currentState.name});
      return YES;
    }

    if (![self.currentState canTransitionToState:newState]) {
      TeakLog_i(@"session.invalid_state", @{@"state" : self.currentState.name, @"new_state" : newState.name});
      return NO;
    }

    NSMutableArray* invalidValuesForTransition = [[NSMutableArray alloc] init];

    // Check the data that should be valid before transitioning to the next state. Perform any
    // logic that should occur on transition.
    if (newState == [TeakSession Created]) {
      if (self.startDate == nil) {
        [invalidValuesForTransition addObject:@[ @"startDate", @"nil" ]];
      } else if (self.appConfiguration == nil) {
        [invalidValuesForTransition addObject:@[ @"appConfiguration", @"nil" ]];
        //invalidValuesForTransition.add(new Object[]{"appConfiguration", "null"});
      } else if (self.deviceConfiguration == nil) {
        [invalidValuesForTransition addObject:@[ @"deviceConfiguration", @"nil" ]];
      }
    } else if (newState == [TeakSession IdentifyingUser]) {
      if (self.userId == nil) {
        [invalidValuesForTransition addObject:@[ @"userId", @"nil" ]];
      }
    }

    // Print out any invalid values
    if (invalidValuesForTransition.count > 0) {
      NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
      [dict setValue:self.currentState.name forKey:@"state"];
      [dict setValue:newState forKey:@"new_state"];
      for (NSArray* elem in invalidValuesForTransition) {
        [dict setValue:elem[1] forKey:elem[0]];
      }
      TeakLog_e(@"session.invalid_values", dict);

      // Invalidate this session
      [self setState:[TeakState Invalid]];
      return NO;
    }

    self.previousState = self.currentState;
    self.currentState = newState;

    TeakLog_i(@"session.state", @{@"state" : self.currentState.name, @"old_state" : self.previousState.name});

    return YES;
  }
}

- (void)sendUserIdentifier {
  // This method is executed via an NSInvocationOperation
  @synchronized(self) {
    if ([self setState:[TeakSession IdentifyingUser]] == NO) {
      return;
    }

    TeakDataCollectionConfiguration* dataCollectionConfiguration = [[TeakConfiguration configuration] dataCollectionConfiguration];

    // Time zone
    NSTimeZone* timeZone = [NSTimeZone localTimeZone];
    float timeZoneOffset = (((float)[timeZone secondsFromGMT]) / 60.0f) / 60.0f;
    NSString* timeZoneString = [NSString stringWithFormat:@"%f", timeZoneOffset];
    if (timeZoneString == nil) {
      timeZoneString = @"unknown";
    }

    // Locale
    NSString* locale = nil;
    @try {
      locale = [[NSLocale preferredLanguages] objectAtIndex:0];
    } @catch (NSException* exception) {
      locale = @"unknown"; // TODO: report
    }

    NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:@{
      @"locale" : locale,
      @"timezone" : timeZoneString,
      @"timezone_id": timeZone.name
    }];

    // Kick off checking for push notification enabled
    payload[@"notifications_enabled"] = self.deviceConfiguration.notificationDisplayEnabled;
    payload[@"supports_content_extensions"] = @([[UNUserNotificationCenter currentNotificationCenter] supportsContentExtensions]);

    // Always send if ad tracking is limited, send empty string if it is limited (by either the game, or the OS)
    payload[@"ios_limit_ad_tracking"] = [NSNumber numberWithBool:!dataCollectionConfiguration.enableIDFA];
    if ([self.deviceConfiguration.advertisingIdentifier length] > 0 && dataCollectionConfiguration.enableIDFA) {
      payload[@"ios_ad_id"] = self.deviceConfiguration.advertisingIdentifier;
    } else {
      payload[@"ios_ad_id"] = @"";
    }

    // Additional device information
    payload[@"device_num_cores"] = [NSNumber numberWithUnsignedInteger:self.deviceConfiguration.numberOfCores];
    payload[@"device_device_memory_in_bytes"] = [NSNumber numberWithUnsignedLongLong:self.deviceConfiguration.phyiscalMemoryInBytes];
    payload[@"device_display_metrics"] = self.deviceConfiguration.displayMetrics;

    if (self.userIdentificationSent) {
      payload[@"do_not_track_event"] = @YES;
    }
    self.userIdentificationSent = YES;

    if (self.email != nil) {
      payload[@"email"] = self.email;
    }

    if ([self.deviceConfiguration.pushToken length] > 0 && dataCollectionConfiguration.enablePushKey) {
      payload[@"apns_push_key"] = self.deviceConfiguration.pushToken;
      [payload addEntriesFromDictionary:[[Teak sharedInstance].pushState to_h]];
    } else {
      payload[@"apns_push_key"] = @"";
    }

    if (!self.appConfiguration.sdk5Behaviors) {
      if (dataCollectionConfiguration.enableFacebookAccessToken) {
        if (self.facebookAccessToken == nil) {
          self.facebookAccessToken = [FacebookAccessTokenEvent currentUserToken];
        }

        if (self.facebookAccessToken != nil) {
          payload[@"access_token"] = self.facebookAccessToken;
        }
      }
    }

    if (self.facebookId != nil) {
      payload[@"facebook_id"] = self.facebookId;
    }

    // Then add the attribution, then send request
    // The launchDataOperation is a dependency for this operation, so it should always be ready
    if (self.launchDataOperation && self.launchDataOperation.isFinished) {
      [payload addEntriesFromDictionary:[self.launchDataOperation.result sessionAttribution]];
    }

    TeakLog_i(@"session.identify_user", @{@"userId" : self.userId, @"timezone" : [NSString stringWithFormat:@"%f", timeZoneOffset], @"locale" : [[NSLocale preferredLanguages] objectAtIndex:0]});

    __weak typeof(self) weakSelf = self;
    TeakRequest* request = [TeakRequest requestWithSession:self
                                               forEndpoint:[NSString stringWithFormat:@"/games/%@/users.json", self.appConfiguration.appId]
                                               withPayload:payload
                                                    method:TeakRequest_POST
                                                  callback:^(NSDictionary* reply) {
                                                    __strong typeof(self) blockSelf = weakSelf;

                                                    bool logLocal = [reply[@"verbose_logging"] boolValue];
                                                    bool logRemote = [reply[@"log_remote"] boolValue];
                                                    [[TeakConfiguration configuration].debugConfiguration setLogLocal:logLocal logRemote:logRemote];

                                                    [Teak sharedInstance].enableDebugOutput |= logLocal;
                                                    [Teak sharedInstance].enableRemoteLogging |= logRemote;

                                                    blockSelf.countryCode = reply[@"country_code"];

                                                    // User profile
                                                    blockSelf.userProfile = [[TeakUserProfile alloc] initForSession:blockSelf withDictionary:reply[@"user_profile"]];

                                                    // Deep link
                                                    if (reply[@"deep_link"]) {
                                                      NSString* deepLink = reply[@"deep_link"];
                                                      NSURL* url = [NSURL URLWithString:deepLink];
                                                      if (url && blockSelf.launchDataOperation != nil) {
                                                        NSString* payloadLaunchLink = payload[@"launch_link"];
                                                        NSURL* launchLink = payloadLaunchLink == nil || payloadLaunchLink == ((NSString*)[NSNull null]) ? nil : [NSURL URLWithString:payloadLaunchLink];
                                                        blockSelf.launchDataOperation = [blockSelf.launchDataOperation updateDeepLink:url withLaunchLink:launchLink];
                                                      }
                                                      TeakLog_i(@"deep_link.processed", deepLink);
                                                    }

                                                    // Additional data
                                                    if (reply[@"additional_data"]) {
                                                      blockSelf.additionalData = reply[@"additional_data"];
                                                      TeakLog_i(@"additional_data.received", blockSelf.additionalData);
                                                      [AdditionalDataEvent additionalDataReceived:blockSelf.additionalData];
                                                    }

                                                    // Opt Out State
                                                    if (reply[@"opt_out_states"]) {
                                                      blockSelf.emailStatus = [[TeakChannelStatus alloc] initWithDictionary:reply[@"opt_out_states"][@"email"]];
                                                      blockSelf.pushStatus = [[TeakChannelStatus alloc] initWithDictionary:reply[@"opt_out_states"][@"push"]];
                                                      blockSelf.smsStatus = [[TeakChannelStatus alloc] initWithDictionary:reply[@"opt_out_states"][@"sms"]];
                                                    }

                                                    if(reply[@"session_id"]) {
                                                      blockSelf.serverSessionId = reply[@"session_id"];
                                                      blockSelf.sessionVectorClock = 0;
                                                    }

                                                    [blockSelf dispatchUserDataEvent];

                                                    // Assign new state
                                                    // Prevent warning for 'do_not_track_event'
                                                    if (blockSelf.currentState == [TeakSession Expiring]) {
                                                      blockSelf.previousState = [TeakSession UserIdentified];
                                                    } else if (blockSelf.currentState != [TeakSession UserIdentified]) {
                                                      [blockSelf setState:[TeakSession UserIdentified]];
                                                    }
                                                  }];

    [request send];
  }
}

- (void)sendHeartbeat {
  NSString* urlString = [NSString stringWithFormat:
                                      @"https://%@/ping?game_id=%@&api_key=%@&sdk_version=%@&sdk_platform=%@&app_version=%@%@&buster=%08x",
                                      kTeakHostname,
                                      URLEscapedString(self.appConfiguration.appId),
                                      URLEscapedString(self.userId),
                                      URLEscapedString([Teak sharedInstance].sdkVersion),
                                      URLEscapedString(self.deviceConfiguration.platformString),
                                      URLEscapedString(self.appConfiguration.appVersion),
                                      self.countryCode == nil ? @"" : [NSString stringWithFormat:@"&country_code=%@", self.countryCode],
                                      arc4random()];

  NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                       timeoutInterval:120];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [NSURLConnection sendSynchronousRequest:request
                        returningResponse:nil
                                    error:nil];
#pragma clang diagnostic pop
}

- (TeakSession*)init {
  self = [super init];
  if (self) {
    TeakConfiguration* configuration = [TeakConfiguration configuration];

    self.currentState = [TeakSession Allocated];
    self.startDate = [[NSDate alloc] init];
    self.appConfiguration = configuration.appConfiguration;
    self.deviceConfiguration = configuration.deviceConfiguration;
    self.serverSessionId = nil;
    self.sessionVectorClock = 0;

    // Assign unattributed launch at init
    self.launchDataOperation = [TeakLaunchDataOperation unattributed];
    [[Teak sharedInstance].operationQueue addOperation:self.launchDataOperation];

    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    self.sessionId = [(__bridge NSString*)string stringByReplacingOccurrencesOfString:@"-" withString:@""];
    CFRelease(string);

    self.emailStatus = [TeakChannelStatus unknown];
    self.pushStatus = [TeakChannelStatus unknown];
    self.smsStatus = [TeakChannelStatus unknown];

    RegisterKeyValueObserverFor(self.deviceConfiguration, advertisingIdentifier);
    RegisterKeyValueObserverFor(self.deviceConfiguration, pushToken);
    RegisterKeyValueObserverFor(self, currentState);

    [TeakEvent addEventHandler:self];

    [self setState:[TeakSession Created]];
  }
  return self;
}

- (TeakSession*)initWithSession:(nullable TeakSession*)session {
  self = [self init];
  if (self) {
    if (session != nil) {
      self.userId = session.userId;
      self.facebookAccessToken = session.facebookAccessToken;
    }
  }
  return self;
}

- (void)dealloc {
  // This observer is only registered in the 'Created' state
  if ([self currentState] == [TeakSession Created]) {
    UnRegisterKeyValueObserverFor(self.remoteConfiguration, hostname);
  }
  UnRegisterKeyValueObserverFor(self.deviceConfiguration, advertisingIdentifier);
  UnRegisterKeyValueObserverFor(self.deviceConfiguration, pushToken);
  UnRegisterKeyValueObserverFor(self, currentState);

  [TeakEvent removeEventHandler:self];
}

- (void)handleEvent:(TeakEvent*)event {
  switch (event.type) {
    case FacebookAccessToken: {
      id oldValue = self.facebookAccessToken;
      id newValue = ((FacebookAccessTokenEvent*)event).accessToken;
      if (oldValue != newValue && (NSNullOrNil(oldValue) || ![newValue isEqualToString:oldValue])) {
        self.facebookAccessToken = newValue;
        [self identifyUserInfoHasChanged];
      }
    } break;
    default:
      break;
  }
}

- (NSOperation*)identifyUserOperation {
  NSOperation* identifyUserOperation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(sendUserIdentifier) object:nil];
  if (self.launchDataOperation) {
    [identifyUserOperation addDependency:self.launchDataOperation];
  }
  return identifyUserOperation;
}

- (void)processAttributionAndDispatchEvents {
  if (self.launchDataOperation == nil || !self.launchDataOperation.finished || self.launchAttributionProcessed) return;
  self.launchAttributionProcessed = YES;

  // Grab the resolved launch data (it should never be nil, but let's still check)
  TeakLaunchData* launchData = self.launchDataOperation.result;
  if (launchData == nil) return;

  if ([launchData isKindOfClass:[TeakAttributedLaunchData class]]) {
    TeakAttributedLaunchData* attributedLaunchData = (TeakAttributedLaunchData*)launchData;

    // Check for a reward, and dispatch
    [TeakSession checkLaunchDataForRewardAndDispatchEvents:attributedLaunchData];

    [TeakSession checkLaunchDataForNotificationAndDispatchEvents:attributedLaunchData];
  }

  // Check for a deep link, and dispatch
  [TeakSession checkLaunchDataForDeepLinkAndDispatchEvents:launchData];

  // Always send out an app launch
  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    [[NSNotificationCenter defaultCenter] postNotificationName:TeakPostLaunchSummary
                                                        object:session
                                                      userInfo:[launchData to_h]];
  }];
}

+ (void)registerStaticEventListeners {
  static id<TeakEventHandler> handler = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    handler = [TeakEventBlockHandler handlerWithBlock:^(TeakEvent* _Nonnull event) {
      switch (event.type) {
        case UserIdentified: {
          UserIdEvent* userIdEvent = (UserIdEvent*)event;
          TeakConfiguration* configuration = [TeakConfiguration configuration];
          if (configuration != nil) {
            [configuration.dataCollectionConfiguration addConfigurationFromDeveloper:userIdEvent.userConfiguration];
          }

          [TeakSession setUserId:userIdEvent.userId andEmail:userIdEvent.userConfiguration.email andFacebookId:userIdEvent.userConfiguration.facebookId];
        } break;
        case LifecycleActivate: {
          [TeakSession applicationDidBecomeActive];
        } break;
        case LifecycleDeactivate: {
          [TeakSession applicationWillResignActive];
        } break;
        case Logout: {
          [TeakSession logoutReusingCurrentSession:false];
        } break;
        default:
          break;
      }
    }];
  });
  [TeakEvent addEventHandler:handler];
}

+ (void)logoutReusingCurrentSession:(BOOL)reuseSession {
  @synchronized(currentSessionMutex) {
    @synchronized(currentSession) {
      TeakSession* newSession = nil;
      if (reuseSession) {
        newSession = [[TeakSession alloc] initWithSession:currentSession];
      } else {
        newSession = [[TeakSession alloc] init];
      }

      [currentSession setState:[TeakSession Expiring]];
      [currentSession setState:[TeakSession Expired]];

      currentSession = newSession;
    }
  }
}

+ (void)setUserId:(nonnull NSString*)userId andEmail:(nullable NSString*)email andFacebookId:(nullable NSString*)facebookId {
  if (userId.length == 0) {
    TeakLog_e(@"session", @"userId cannot be nil or empty.");
    return;
  }

  @synchronized(currentSessionMutex) {
    [TeakSession currentSession];
    @synchronized(currentSession) {
      if (currentSession.userId != nil && ![currentSession.userId isEqualToString:userId]) {
        [TeakSession logoutReusingCurrentSession:true];
      }

      BOOL needsIdentifyUser = (currentSession.currentState == [TeakSession Configured]);
#define CURRENT_SESSION_STATE_IS_IDENTIFIED (currentSession.currentState == [TeakSession IdentifyingUser] || currentSession.currentState == [TeakSession UserIdentified])
      if (!TeakStringsAreEqualConsideringNSNull(currentSession.email, email) && CURRENT_SESSION_STATE_IS_IDENTIFIED) {
        needsIdentifyUser = YES;
      }
      if (!TeakStringsAreEqualConsideringNSNull(currentSession.facebookId, facebookId) && CURRENT_SESSION_STATE_IS_IDENTIFIED) {
        needsIdentifyUser = YES;
      }
#undef CURRENT_SESSION_STATE_IS_IDENTIFIED

      currentSession.userId = userId;
      currentSession.email = email;
      currentSession.facebookId = facebookId;

      if (needsIdentifyUser) {
        [[Teak sharedInstance].operationQueue addOperation:[currentSession identifyUserOperation]];
      }
    }
  }
}

+ (void)applicationDidBecomeActive {
  @synchronized(currentSessionMutex) {
    [TeakSession currentSession];

    if (currentSession.currentState == [TeakSession Expiring]) {
      [currentSession setState:currentSession.previousState];
    }

    // Process WhenDeviceIsAwakeRun queue
    NSMutableArray* blocks = [TeakSession whenDeviceIsAwakeRunBlocks];
    for (void (^block)(void) in blocks) {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        block();
      });
    }
    [blocks removeAllObjects];
  }
}

+ (void)applicationWillResignActive {
  @synchronized(currentSessionMutex) {
    [currentSession setState:[TeakSession Expiring]];
  }
}

+ (void)didLaunchWithData:(nonnull TeakLaunchDataOperation*)launchDataOperation {
  @synchronized(currentSessionMutex) {
    // Call getCurrentSession() so the null || Expired logic stays in one place
    [TeakSession currentSession];

    // If there's already an active session, then create a new one
    if (currentSession.currentState != [TeakSession Allocated] &&
        currentSession.currentState != [TeakSession Created]) {

      TeakSession* oldSession = currentSession;
      currentSession = [[TeakSession alloc] initWithSession:oldSession];

      [oldSession setState:[TeakSession Expiring]];
      [oldSession setState:[TeakSession Expired]];
    }

    // Assign launch data
    currentSession.launchDataOperation = launchDataOperation;

    // This will use launchData as a dependency for an identify user operation, if
    // an identify user is needed.
    [currentSession identifyUserInfoHasChanged];

    // Enqueue processing the launch data
    [[Teak sharedInstance].operationQueue addOperation:launchDataOperation];
  }
}

+ (TeakSession*)currentSession {
  @synchronized(currentSessionMutex) {
    if (currentSession == nil || [currentSession hasExpired]) {
      TeakSession* oldSession = currentSession;
      currentSession = [[TeakSession alloc] initWithSession:oldSession];
    }
    return currentSession;
  }
}

+ (nullable TeakSession*)currentSessionOrNil {
  @synchronized(currentSessionMutex) {
    return currentSession;
  }
}

- (void)identifyUserInfoHasChanged {
  [TeakSession whenDeviceIsAwakeRun:^{
    // If identify user is in progress, wait for it to complete
    TeakState* thisSessionState = nil;
    @synchronized(self) {
      thisSessionState = self.currentState;
    }
    while (thisSessionState == [TeakSession IdentifyingUser]) {
      sleep(1);
      @synchronized(self) {
        thisSessionState = self.currentState;
      }
    }

    // Re-send identify user if needed
    @synchronized(self) {
      if (self.userIdentificationSent) {
        [[Teak sharedInstance].operationQueue addOperation:[self identifyUserOperation]];
      }
    }
  }];
}

+ (void)checkLaunchDataForRewardAndDispatchEvents:(nonnull TeakAttributedLaunchData*)launchData {
  if (launchData.rewardId == nil) return;

  TeakReward* reward = [TeakReward rewardForRewardId:launchData.rewardId];
  if (reward == nil) return;

  __weak TeakReward* tempWeakReward = reward;
  reward.onComplete = ^() {
    __strong TeakReward* blockReward = tempWeakReward;
    if (blockReward.json != nil) {
      NSMutableDictionary* userInfo = [[NSMutableDictionary alloc] initWithDictionary:[launchData to_h]];
      [userInfo addEntriesFromDictionary:blockReward.json];

      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
        [[NSNotificationCenter defaultCenter] postNotificationName:TeakOnReward
                                                            object:session
                                                          userInfo:userInfo];
      }];
    }
  };
}

+ (void)checkLaunchDataForNotificationAndDispatchEvents:(nonnull TeakAttributedLaunchData*)launchData {
  if (![launchData isKindOfClass:[TeakNotificationLaunchData class]]) return;

  [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
    [[NSNotificationCenter defaultCenter] postNotificationName:TeakNotificationAppLaunch
                                                        object:session
                                                      userInfo:[launchData to_h]];
  }];
}

+ (void)checkLaunchDataForDeepLinkAndDispatchEvents:(nonnull TeakLaunchData*)launchData {
  @try {
    // This is an attributed launch, it came from a Teak source
    if ([launchData isKindOfClass:[TeakAttributedLaunchData class]]) {
      TeakAttributedLaunchData* attributedLaunchData = (TeakAttributedLaunchData*)launchData;

      // If this was a RewardLink send the appropriate event
      if ([attributedLaunchData isKindOfClass:[TeakRewardlinkLaunchData class]]) {
        [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
          [[NSNotificationCenter defaultCenter] postNotificationName:TeakLaunchedFromLink
                                                              object:session
                                                            userInfo:[launchData to_h]];
        }];
      }

      // If TeakLinks will not handle the deep link, then it's an external deep link and
      // so we should launch an intent with it
      if (attributedLaunchData.deepLink != nil && !TeakLink_WillHandleDeepLink(attributedLaunchData.deepLink)) {
        dispatch_async(dispatch_get_main_queue(), ^{
          UIApplication* application = [UIApplication sharedApplication];

          // It is safe to do this even with links that are handled by Teak,
          // because the Teak delegate hooks check if the link was opened by the
          // host app and bail if it was. By doing this, we ensure that all links
          // are handled to application delegates even in cases where Teak failed
          // to hook the application delegate, e.g. Unity custom application
          // delegates.
          if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
            [application openURL:attributedLaunchData.deepLink
                options:@{}
                completionHandler:^(BOOL success) {
                  TeakLog_i(@"deep_link.url_open_attempt", @{@"url" : [attributedLaunchData.deepLink absoluteString], @"success" : [NSNumber numberWithBool:success]});
                }];
          } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [application openURL:attributedLaunchData.deepLink];
#pragma clang diagnostic pop
          }
        });
      } else {
        // Otherwise, handle the deep link
        TeakLink_HandleDeepLink(attributedLaunchData.deepLink);
      }
    } else {
      // If this is not an attributed launch, then we should check to see if TeakLinks can
      // do anything with the **launchLink**, because a customer may still want to use the
      // TeakLink system outside of the context of a Teak Reward Link, and that should still
      // function properly.
      TeakLink_HandleDeepLink(launchData.launchUrl);
    }
  } @finally {
  }
}

KeyValueObserverFor(TeakSession, TeakSession, currentState) {
  @synchronized(self) {
    if (oldValue == [TeakSession Created]) {
      UnRegisterKeyValueObserverFor(self.remoteConfiguration, hostname);
    }

    if (newValue == [TeakSession Created]) {
      self.remoteConfiguration = [[TeakRemoteConfiguration alloc] initForSession:self];
      RegisterKeyValueObserverFor(self.remoteConfiguration, hostname);
    } else if (newValue == [TeakSession Configured]) {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.userId != nil) {
          [[Teak sharedInstance].operationQueue addOperation:[self identifyUserOperation]];
        }
      });
    } else if (newValue == [TeakSession UserIdentified]) {
      // Stop heartbeat, since UserIdentified->IdentifyingUser->UserIdentified
      if (self.heartbeat != nil) {
        dispatch_source_cancel(self.heartbeat);
      }
      self.heartbeat = nil;
      self.heartbeatQueue = nil;

      // Heartbeat queue
      self.heartbeatQueue = dispatch_queue_create("io.teak.sdk.heartbeat", NULL);

      // Heartbeat
      __weak typeof(self) weakSelf = self;
      self.heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.heartbeatQueue);
      dispatch_source_set_event_handler(self.heartbeat, ^{
        __strong typeof(self) blockSelf = weakSelf;
        [blockSelf sendHeartbeat];
      });

      dispatch_source_set_timer(self.heartbeat, dispatch_walltime(NULL, 0), self.remoteConfiguration.heartbeatInterval * NSEC_PER_SEC, 1ull * NSEC_PER_SEC);

      // Only start heartbeat if the interval is greater than zero
      if (self.remoteConfiguration.heartbeatInterval > 0) {
        dispatch_resume(self.heartbeat);
      }

      // Process WhenUserIdIsReadyRun queue
      @synchronized(currentSessionMutex) {
        NSMutableArray* blocks = [TeakSession whenUserIdIsReadyRunBlocks];
        for (UserIdReadyBlock block in blocks) {
          dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            block(self);
          });
        }
        [blocks removeAllObjects];
      }

      // Process deep links and/or rewards
      [self processAttributionAndDispatchEvents];

      // Send the server a "hey nevermind that" message if needed
      if (oldValue == [TeakSession Expiring]) {
        // Cancel any pending duration report
        if ([self resetReportDurationBlock]) {
          // The report duration got sent, so send a resume
          self.sessionVectorClock++;
          NSDictionary* payload = @{
            @"session_id" : self.serverSessionId == nil ? @"null" : URLEscapedString(self.serverSessionId),
            @"session_vector_clock": [NSNumber numberWithLong:self.sessionVectorClock]
          };

          TeakRequest* request = [TeakRequest requestWithSession:self
                                                     forEndpoint:@"/session_resume"
                                                     withPayload:payload
                                                          method:TeakRequest_POST
                                                        callback:nil];
          [request send];
        }
      }
    } else if (newValue == [TeakSession Expiring]) {
      self.endDate = [[NSDate alloc] init];

      // Stop heartbeat, Expiring->Expiring is possible, so no invalid data here
      if (self.heartbeat != nil) {
        dispatch_source_cancel(self.heartbeat);
      }
      self.heartbeat = nil;
      self.heartbeatQueue = nil;

      // Send user profile out now
      if (self.userProfile != nil) {
        __weak typeof(self) weakSelf = self;
        dispatch_async([Teak operationQueue], ^{
          __strong typeof(self) blockSelf = weakSelf;
          [blockSelf.userProfile send];
        });
      }

      // Reset duraation report and set it
      if(self.serverSessionId != nil) {
        [self resetReportDurationBlock];
        self.reportDurationBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
          [self beginBackgroundUpdateTask];

          self.sessionVectorClock++;

          // Send request for "if you don't hear back from me, this session ended now"
          NSDictionary* payload = @{
            @"session_id" : URLEscapedString(self.serverSessionId),
            @"session_duration_ms" : [NSNumber numberWithLong:[self.endDate timeIntervalSinceDate:self.startDate] * 1000],
            @"session_vector_clock": [NSNumber numberWithLong:self.sessionVectorClock]
          };

          TeakRequest* request = [TeakRequest requestWithSession:self
                                                     forEndpoint:@"/session_stop"
                                                     withPayload:payload
                                                          method:TeakRequest_POST
                                                        callback:nil];

          // Make sure we're not canceled
          if (self.reportDurationBlock != nil && !dispatch_block_testcancel(self.reportDurationBlock)) {
            self.reportDurationSent = YES;
            [request send];
          }

          [self endBackgroundUpdateTask];
        });
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), self.reportDurationBlock);
      }
    } else if (newValue == [TeakSession Expired]) {
    }
  }
}

- (BOOL)resetReportDurationBlock {
  BOOL lastReportDurationSent = self.reportDurationSent;
  if (self.reportDurationBlock) {
    dispatch_block_cancel(self.reportDurationBlock);
    self.reportDurationBlock = nil;
    self.reportDurationSent = NO;
  }
  return lastReportDurationSent;
}

- (void)beginBackgroundUpdateTask {
  self.backgroundUpdateTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
    [self endBackgroundUpdateTask];
  }];
}

- (void)endBackgroundUpdateTask {
  [[UIApplication sharedApplication] endBackgroundTask:self.backgroundUpdateTask];
  self.backgroundUpdateTask = UIBackgroundTaskInvalid;
}

- (void)dispatchUserDataEvent {
  @synchronized(self) {
    TeakDataCollectionConfiguration* dataCollectionConfiguration = [[TeakConfiguration configuration] dataCollectionConfiguration];

    NSDictionary* pushRegistration = (NSDictionary*)[NSNull null];
    if ([self.deviceConfiguration.pushToken length] > 0 && dataCollectionConfiguration.enablePushKey) {
      pushRegistration = @{
        @"apns" : self.deviceConfiguration.pushToken
      };
    }
    [UserDataEvent userDataReceived:self.additionalData
                        emailStatus:self.emailStatus
                         pushStatus:self.pushStatus
                          smsStatus:self.smsStatus
                   pushRegistration:pushRegistration];
  }
}

- (void)optOutPushPreference:(NSString*)optOut {
  // TODO: The thing
}

- (void)optOutEmailPreference:(NSString*)optOut {
  // TODO: The thing
}

KeyValueObserverFor(TeakSession, TeakDeviceConfiguration, advertisingIdentifier) {
  TeakUnusedKVOValues;
  [self identifyUserInfoHasChanged];
}

KeyValueObserverFor(TeakSession, TeakDeviceConfiguration, pushToken) {
  TeakUnusedKVOValues;
  [self identifyUserInfoHasChanged];
}

KeyValueObserverFor(TeakSession, TeakDeviceConfiguration, notificationDisplayEnabled) {
  TeakUnusedKVOValues;
  [self identifyUserInfoHasChanged];
}

KeyValueObserverFor(TeakSession, TeakRemoteConfiguration, hostname) {
  TeakUnusedKVOValues;
  [self setState:[TeakSession Configured]];
}

- (BOOL)hasExpired {
  @synchronized(self) {
    if (self.currentState == [TeakSession Expiring] && [[[NSDate alloc] init] timeIntervalSinceDate:self.endDate] > TeakSameSessionDeltaSeconds) {
      [self setState:[TeakSession Expired]];
    }
    return self.currentState == [TeakSession Expired];
  }
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
KeyValueObserverSupported(TeakSession);
#pragma clang diagnostic pop

@end
