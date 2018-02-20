/* Teak -- Copyright (C) 2016 GoCarrot Inc.
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

#import "TeakRemoteConfiguration.h"

#import "Teak+Internal.h"
#import "TeakAppConfiguration.h"
#import "TeakLink.h"
#import "TeakRequest.h"
#import "TeakSession.h"

@interface TeakRemoteConfiguration ()
@property (strong, nonatomic, readwrite) NSString* hostname;
@property (strong, nonatomic, readwrite) NSString* sdkSentryDsn;
@property (strong, nonatomic, readwrite) NSString* appSentryDsn;
@end

@implementation TeakRemoteConfiguration

- (TeakRemoteConfiguration*)initForSession:(nonnull TeakSession*)session {
  self = [super init];
  if (self) {
    __weak TeakRemoteConfiguration* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      __strong TeakRemoteConfiguration* blockSelf = weakSelf;
      [blockSelf configureForSession:session];
    });
  }
  return self;
}

- (void)configureForSession:(nonnull TeakSession*)session {
  NSBlockOperation* configOp = [NSBlockOperation blockOperationWithBlock:^{
    NSDictionary* payload = @{@"id" : session.appConfiguration.appId,
                              @"deep_link_routes" : [TeakLink routeNamesAndDescriptions]};

    TeakRequest* request = [[TeakRequest alloc]
        initWithSession:session
            forEndpoint:[NSString stringWithFormat:@"/games/%@/settings.json", session.appConfiguration.appId]
            withPayload:payload
               callback:^(NSURLResponse* response, NSDictionary* reply) {
                 // TODO: Check response
                 if (NO) {
                 } else {
                   self.hostname = @"gocarrot.com";

                   NSString* sdkSentryDsn = [reply valueForKey:@"sdk_sentry_dsn"];
                   if (sdkSentryDsn) {
                     self.sdkSentryDsn = sdkSentryDsn;
                     // TODO: assign DSN via KVO?
                   }

                   // Optionally blackhole calls to [UIApplication unregisterForRemoteNotifications]
                   teak_try {
                     BOOL blackholeUnregisterForRemoteNotifications = [[reply valueForKey:@"blackhole_unregister_for_remote_notifications"] boolValue];
                     NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
                     [userDefaults setBool:blackholeUnregisterForRemoteNotifications forKey:kBlackholeUnregisterForRemoteNotifications];
                   }
                   teak_catch_report;
                 }
               }];
    [request send];
  }];

  if ([Teak sharedInstance].waitForDeepLinkOperation != nil) {
    [configOp addDependency:[Teak sharedInstance].waitForDeepLinkOperation];
  }

  [[Teak sharedInstance].operationQueue addOperation:configOp];
}

- (NSDictionary*)to_h {
  return @{
    @"hostname" : self.hostname,
    @"sdkSentryDsn" : self.sdkSentryDsn,
    @"appSentryDsn" : self.appSentryDsn
  };
}

@end
