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
#import "TeakSession.h""
#import "TeakRequestThread.h"
#import "TeakAppConfiguration.h"

#define LOG_TAG "Teak:RemoteConfig"

@interface TeakRemoteConfiguration ()
@property (strong, nonatomic, readwrite) NSString* hostname;
@property (strong, nonatomic, readwrite) NSString* sdkSentryDsn;
@property (strong, nonatomic, readwrite) NSString* appSentryDsn;
@end

@implementation TeakRemoteConfiguration

- (TeakRemoteConfiguration*)initForSession:(nonnull TeakSession*)session {
   self = [super init];
   if (self) {
      __block typeof(self) blockSelf = self;
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
         [blockSelf configureForSession:session];
      });
   }
   return self;
}

- (void)configureForSession:(nonnull TeakSession*)session {
   TeakRequest* request = [TeakRequest requestForService:TeakRequestServiceAuth
                                              atEndpoint:[NSString stringWithFormat:@"/games/%@/settings.json", session.appConfiguration.appId]
                                             usingMethod:TeakRequestTypePOST
                                             withPayload:@{@"id" : session.appConfiguration.appId}
                                                callback:
                           ^(TeakRequest* request, NSHTTPURLResponse* response, NSData* data, TeakRequestThread* requestThread) {
                              NSError* error = nil;
                              NSDictionary* config = [NSJSONSerialization JSONObjectWithData:data
                                                                                     options:kNilOptions
                                                                                       error:&error];
                              if (error) {
                                 TeakLog(@"Unable to perform services configuration for Teak. Teak is in offline mode. %@", error);
                              } else {
                                 self.hostname = @"gocarrot.com";
                                 
                                 NSString* sdkSentryDsn = [config valueForKey:@"sdk_sentry_dsn"];
                                 if (sdkSentryDsn) {
                                    self.sdkSentryDsn = sdkSentryDsn;
                                    // TODO: assign DSN via KVO?
                                 }
                              }
                           }];
   [session.requestThread processRequest:request onHost:@"gocarrot.com"];
}

@end
