#import <UserNotifications/UserNotifications.h>

NSURLSession* TeakURLSessionWithoutDelegate(void) {
  static NSURLSession* session = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURLSessionConfiguration* sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.URLCache = nil;
    sessionConfiguration.URLCredentialStorage = nil;
    sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    sessionConfiguration.HTTPAdditionalHeaders = @{
      @"X-Teak-DeviceType" : @"API",
      @"X-Teak-Supports-Templates" : @"TRUE"
    };
    session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
  });
  return session;
}

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

BOOL TeakSendHealthCheckIfNeededSynch(NSDictionary* userInfo) {
  BOOL teakHealthCheck = [userInfo[@"teakHealthCheck"] boolValue];
  if (teakHealthCheck || userInfo[@"teakExpectedDisplay"] != nil) {
    BOOL teakExpectedDisplay = [userInfo[@"teakExpectedDisplay"] boolValue];
    BOOL shouldSendHealthCheck = teakHealthCheck;
    UNAuthorizationStatus notificationState = -1; // 0 = UNAuthorizationStatusNotDetermined

    UNNotificationSettings* notificationSettings = UNNotificationCenterSettingsSync();
    if (notificationSettings != nil) {
      notificationState = notificationSettings.authorizationStatus;
      BOOL canDisplay = (notificationState == UNAuthorizationStatusAuthorized);
      if (@available(iOS 12.0, *)) {
        canDisplay |= (notificationState == UNAuthorizationStatusProvisional);
      }

      shouldSendHealthCheck |= (canDisplay != teakExpectedDisplay);
    }

    // Do this synchronously, and then it can be tossed in something async as needed
    if (shouldSendHealthCheck) {
      NSString* deviceId = @"unknown";
      @try {
        deviceId = [[NSUserDefaults standardUserDefaults] objectForKey:@"TeakDeviceId"];
      } @finally {
      }

      NSArray* _Nonnull const TeakNotificationStateName = @[
        @"UnableToDetermine",
        @"NotRequested",
        @"Disabled",
        @"Enabled",
        @"Provisional",
        @"Provisional" // Not a typo, this is actually 'Ephemeral' but that's the same as far as the back end is concerned
      ];
      @try {
        NSDictionary* payload = @{
          @"app_id" : ValueOrNSNull(userInfo[@"teakAppId"]),
          @"user_id" : ValueOrNSNull(userInfo[@"teakUserId"]),
          @"platform_id" : ValueOrNSNull(userInfo[@"teakNotifId"]),
          @"device_id" : ValueOrNSNull(deviceId),
          @"expected_display" : ValueOrNSNull(userInfo[@"teakExpectedDisplay"]),
          @"status" : TeakNotificationStateName[notificationState + 1] // Becaue Unknown is -1 and Enabled is 0
        };
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://parsnip.gocarrot.com/push_state"]
                                                               cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                           timeoutInterval:120];

        NSData* payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setHTTPMethod:@"POST"];
        [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[payloadData length]] forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:payloadData];

        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        [[TeakURLSessionWithoutDelegate() dataTaskWithRequest:request
                                            completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                              dispatch_semaphore_signal(sema);
                                            }] resume];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
      } @finally {
        // Ignored
      }
    }

    return shouldSendHealthCheck;
  }
  return NO;
}
