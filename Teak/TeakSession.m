#import "TeakSession.h"
#import "AdditionalDataEvent.h"
#import "FacebookAccessTokenEvent.h"
#import "Teak+Internal.h"
#import "TeakAppConfiguration.h"
#import "TeakDebugConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest.h"
#import "TeakReward.h"
#import "TeakUserProfile.h"
#import "UserIdEvent.h"

NSTimeInterval TeakSameSessionDeltaSeconds = 120.0;

TeakSession* currentSession;
NSString* const currentSessionMutex = @"TeakCurrentSessionMutex";

extern BOOL TeakLink_WillHandleDeepLink(NSURL* deepLink);

@interface TeakSession ()
@property (strong, nonatomic, readwrite) TeakState* currentState;
@property (strong, nonatomic) TeakState* previousState;
@property (strong, nonatomic) NSDate* startDate;
@property (strong, nonatomic) NSDate* endDate;
@property (strong, nonatomic) NSString* countryCode;
@property (strong, nonatomic) dispatch_queue_t heartbeatQueue;
@property (strong, nonatomic) dispatch_source_t heartbeat;
@property (strong, nonatomic) NSDictionary* launchAttribution;
@property (nonatomic) BOOL launchAttributionProcessed;
@property (strong, nonatomic) NSMutableArray* attributionChain;
@property (strong, nonatomic) NSString* facebookAccessToken;

@property (strong, nonatomic, readwrite) NSString* userId;
@property (strong, nonatomic, readwrite) NSString* email;
@property (strong, nonatomic, readwrite) NSString* sessionId;
@property (strong, nonatomic, readwrite) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic, readwrite) TeakDeviceConfiguration* deviceConfiguration;
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;

@property (strong, nonatomic, readwrite) TeakUserProfile* userProfile;

@property (nonatomic) BOOL userIdentificationSent;
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
      return NO;
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
      @"timezone" : timeZoneString
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

    if (self.launchAttribution != nil) {
      for (NSString* key in self.launchAttribution) {
        payload[key] = self.launchAttribution[key];
      }
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

    TeakLog_i(@"session.identify_user", @{@"userId" : self.userId, @"timezone" : [NSString stringWithFormat:@"%f", timeZoneOffset], @"locale" : [[NSLocale preferredLanguages] objectAtIndex:0]});

    __weak typeof(self) weakSelf = self;
    TeakRequest* request = [TeakRequest requestWithSession:self
                                               forEndpoint:[NSString stringWithFormat:@"/games/%@/users.json", self.appConfiguration.appId]
                                               withPayload:payload
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
                                                      NSMutableDictionary* updatedAttribution = [NSMutableDictionary dictionaryWithDictionary:blockSelf.launchAttribution];
                                                      updatedAttribution[@"deep_link"] = deepLink;
                                                      blockSelf.launchAttribution = updatedAttribution;
                                                      TeakLog_i(@"deep_link.processed", deepLink);
                                                    }

                                                    // Additional data
                                                    if (reply[@"additional_data"]) {
                                                      NSDictionary* additionalData = reply[@"additional_data"];
                                                      TeakLog_i(@"additional_data.received", additionalData);
                                                      [AdditionalDataEvent additionalDataReceived:additionalData];
                                                    }

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
                                      @"https://iroko.gocarrot.com/ping?game_id=%@&api_key=%@&sdk_version=%@&sdk_platform=%@&app_version=%@%@&buster=%08x",
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
    self.attributionChain = [[NSMutableArray alloc] init];

    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    self.sessionId = [(__bridge NSString*)string stringByReplacingOccurrencesOfString:@"-" withString:@""];
    CFRelease(string);

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
      [self.attributionChain addObjectsFromArray:session.attributionChain];
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

- (void)processAttributionAndDispatchEvents {
  if (self.launchAttribution == nil || self.launchAttributionProcessed) return;
  self.launchAttributionProcessed = YES;

  // Check for a deep link, and dispatch
  [TeakLink checkAttributionForDeepLinkAndDispatchEvents:self.launchAttribution];

  // Check for a reward, and dispatch
  [TeakReward checkAttributionForRewardAndDispatchEvents:self.launchAttribution];
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
            [configuration.dataCollectionConfiguration addConfigurationFromDeveloper:userIdEvent.optOut];
          }

          [TeakSession setUserId:userIdEvent.userId andEmail:userIdEvent.email];
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

+ (void)setUserId:(nonnull NSString*)userId andEmail:(nullable NSString*)email {
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

      BOOL needsIdentifyUser = currentSession.currentState == [TeakSession Configured];
      if (![email isEqualToString:currentSession.email]) {
        currentSession.email = email;
        needsIdentifyUser = YES;
      }

      currentSession.userId = userId;

      if (needsIdentifyUser) {
        [currentSession sendUserIdentifier];
      }
    }
  }
}

+ (void)setLaunchAttribution:(nonnull NSDictionary*)attribution {
  @synchronized(currentSessionMutex) {
    // Call getCurrentSession() so the null || Expired logic stays in one place
    [TeakSession currentSession];

    // If there's already an active session, then create a new one
    if (currentSession.currentState != [TeakSession Allocated] &&
        currentSession.currentState != [TeakSession Created]) {
      TeakLog_i(@"session.attribution", attribution);

      TeakSession* oldSession = currentSession;
      currentSession = [[TeakSession alloc] initWithSession:oldSession];

      [oldSession setState:[TeakSession Expiring]];
      [oldSession setState:[TeakSession Expired]];
    }

    currentSession.launchAttribution = attribution;
    [currentSession.attributionChain addObject:attribution];

    [currentSession identifyUserInfoHasChanged];
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

+ (void)didLaunchFromTeakNotification:(nonnull TeakNotification*)notification inBackground:(BOOL)inBackground {
  NSMutableDictionary* launchAttribution = [[NSMutableDictionary alloc] init];

  launchAttribution[@"teak_notif_id"] = notification.teakNotifId;

  if (notification.teakDeepLink != nil) {
    launchAttribution[@"launch_link"] = [notification.teakDeepLink copy];
    launchAttribution[@"deep_link"] = [notification.teakDeepLink copy];
  }

  if (notification.teakRewardId) {
    launchAttribution[@"teak_reward_id"] = notification.teakRewardId;
  }

  if (notification.teakCreativeName) {
    launchAttribution[@"teak_creative_name"] = notification.teakCreativeName;
  }

  if (notification.teakCreativeId) {
    launchAttribution[@"teak_creative_id"] = notification.teakCreativeId;
  }

  if (notification.teakScheduleName) {
    launchAttribution[@"teak_schedule_name"] = notification.teakScheduleName;
  }

  if (notification.teakScheduleId) {
    launchAttribution[@"teak_schedule_id"] = notification.teakScheduleId;
  }

  launchAttribution[@"notification_placement"] = inBackground ? @"background" : @"foreground";

  [TeakSession setLaunchAttribution:launchAttribution];
}

+ (BOOL)didLaunchFromLink:(nonnull NSString*)launchLink wasTeakLink:(BOOL)wasTeakLink {
  // The launch link always goes into 'launch_link'
  NSMutableDictionary* launchAttribution = [NSMutableDictionary dictionaryWithObjectsAndKeys:[launchLink copy], @"launch_link", nil];

  // If the link begins with teakXXXX:// we should attempt to personalize it
  BOOL shouldPersonalizeLink = NO;
  @try {
    NSURL* launchUrl = [NSURL URLWithString:launchLink];
    if (launchUrl) {
      shouldPersonalizeLink = TeakLink_WillHandleDeepLink(launchUrl);
    }
  } @finally {
  }

  // If we're personalizing it, we're sending it as 'deep_link' to the server
  if (shouldPersonalizeLink || wasTeakLink) {
    launchAttribution[@"deep_link"] = [launchLink copy];
  }

  // Add any query parameter that starts with 'teak_' to the launch attribution dictionary
  NSURLComponents* components = [NSURLComponents componentsWithString:launchLink];
  for (NSURLQueryItem* item in components.queryItems) {
    if ([item.name hasPrefix:@"teak_"]) {
      if ([launchAttribution objectForKey:item.name] != nil) {
        if ([[launchAttribution objectForKey:item.name] isKindOfClass:[NSArray class]]) {
          NSMutableArray* array = [launchAttribution objectForKey:item.name];
          [array addObject:item.value];
          [launchAttribution setValue:array forKey:item.name];
        } else {
          NSMutableArray* array = [NSMutableArray arrayWithObjects:[launchAttribution objectForKey:item.name], item.value, nil];
          [launchAttribution setValue:array forKey:item.name];
        }
      } else {
        [launchAttribution setValue:item.value forKey:item.name];
      }
    }
  }

  [TeakSession setLaunchAttribution:launchAttribution];
  return shouldPersonalizeLink;
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
        [self sendUserIdentifier];
      }
    }
  }];
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
          [self sendUserIdentifier];
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
    } else if (newValue == [TeakSession Expired]) {
      // TODO: Report Session to server, once we collect that info.
    }
  }
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
