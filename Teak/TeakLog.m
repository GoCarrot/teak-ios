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

#import "Teak+Internal.h"
#import "TeakLog.h"
#import "TeakDeviceConfiguration.h"
#import "TeakAppConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRaven.h"

#import<libkern/OSAtomic.h>
#import <stdatomic.h>

NSString* INFO = @"INFO";
NSString* ERROR = @"ERROR";

__attribute__((overloadable)) void TeakLog_e(NSString* eventType) {
   TeakLog_e(eventType, nil, nil);
}

__attribute__((overloadable)) void TeakLog_e(NSString* eventType, NSString* message) {
   TeakLog_e(eventType, message, nil);
}

extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType, NSDictionary* _Nullable eventData) {
   TeakLog_e(eventType, nil, eventData);
}

__attribute__((overloadable)) void TeakLog_e(NSString* eventType, NSString* message, NSDictionary* eventData) {
   NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:eventData == nil ? @{} : eventData];
   if (message != nil) {
      [payload setValue:message forKey:@"message"];
   }
   [[Teak sharedInstance].log logEvent:eventType level:ERROR eventData:payload];
}

__attribute__((overloadable)) void TeakLog_i(NSString* eventType) {
   TeakLog_i(eventType, nil, nil);
}

__attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType, NSDictionary* _Nullable eventData) {
   TeakLog_i(eventType, nil, eventData);
}

__attribute__((overloadable)) void TeakLog_i(NSString* eventType, NSString* message) {
   TeakLog_i(eventType, message, nil);
}

__attribute__((overloadable)) void TeakLog_i(NSString* eventType, NSString* message, NSDictionary* eventData) {
   NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:eventData == nil ? @{} : eventData];
   if (message != nil) {
      [payload setValue:message forKey:@"message"];
   }
   [[Teak sharedInstance].log logEvent:eventType level:INFO eventData:payload];
}

@interface TeakLog ()
@property (strong, nonatomic) NSDictionary* sdkVersion;
@property (strong, nonatomic) TeakDeviceConfiguration* deviceConfiguration;
@property (strong, nonatomic) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic) TeakRemoteConfiguration* remoteConfiguration;

@property (strong, nonatomic) NSString* runId;
@property (nonatomic)         volatile OSAtomic_int64_aligned64_t eventCounter;
@end

@implementation TeakLog

- (id)init {
   self = [super init];
   if (self) {
      CFUUIDRef theUUID = CFUUIDCreate(NULL);
      CFStringRef string = CFUUIDCreateString(NULL, theUUID);
      CFRelease(theUUID);
      self.runId = [(__bridge NSString *)string stringByReplacingOccurrencesOfString:@"-" withString:@""];
      CFRelease(string);

      self.eventCounter = 0;
   }
   return self;
}

- (void)useSdk:(nonnull NSDictionary*)sdkVersion {
   self.sdkVersion = sdkVersion;
   [self logEvent:@"sdk_init" level:INFO eventData:nil];
}

- (void)useDeviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
   [self logEvent:@"device_configuration" level:INFO eventData:[deviceConfiguration to_h]];
   self.deviceConfiguration = deviceConfiguration;
}

- (void)useAppConfiguration:(nonnull TeakAppConfiguration*)appConfiguration {
   [self logEvent:@"app_configuration" level:INFO eventData:[appConfiguration to_h]];
   self.appConfiguration = appConfiguration;
}

- (void)useRemoteConfiguration:(nonnull TeakRemoteConfiguration*)remoteConfiguration {
   [self logEvent:@"remote_configuration" level:INFO eventData:[remoteConfiguration to_h]];
   self.remoteConfiguration = remoteConfiguration;
}

- (void)logEvent:(nonnull NSString*)eventType level:(nonnull NSString*)logLevel eventData:(nullable NSDictionary*)eventData {
   NSMutableDictionary* payload = [[NSMutableDictionary alloc] init];
   [payload setValue:self.runId forKey:@"run_id"];
   [payload setValue:[NSNumber numberWithLongLong:OSAtomicIncrement64(&_eventCounter)] forKey:@"event_id"];
   [payload setValue:[NSNumber numberWithLong:[[NSDate date] timeIntervalSince1970]] forKey:@"timestamp"];
   [payload setValue:self.sdkVersion forKey:@"sdk_version"];

   if (self.deviceConfiguration != nil) {
      [payload setValue:self.deviceConfiguration.deviceId forKey:@"device_id"];
   }

   if (self.appConfiguration != nil) {
      [payload setValue:self.appConfiguration.bundleId forKey:@"bundle_id"];
      [payload setValue:self.appConfiguration.appId forKey:@"app_id"];
      [payload setValue:self.appConfiguration.appVersion forKey:@"client_app_version"];
   }

   [payload setValue:eventType forKey:@"event_type"];
   [payload setValue:eventData == nil ? @{} : eventData forKey:@"event_data"];

   NSError* error = nil;
   NSData* jsonData = [NSJSONSerialization dataWithJSONObject:payload
                                                      options:0
                                                        error:&error];
   if (error != nil) {
      return;
   }

   const static int maxLogLength = 900; // 1024 but leave space for formatting
   NSString* jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
   int numLogLines = ceil((float)[jsonString length] / (float)maxLogLength);
   if (numLogLines > 1) {
      for (int i = 0; i < numLogLines; i++) {
         NSLog(@"TeakMulti[%d-%d]: %@", i + 1, numLogLines,
               [jsonString substringWithRange:NSMakeRange(i * maxLogLength, MIN([jsonString length] - i * maxLogLength, maxLogLength))]);
      }
   } else {
      NSLog(@"Teak: %@", jsonString);
   }
}
@end
