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

#import <Foundation/Foundation.h>

extern NSString* _Nonnull const TeakRavenLevelError;
extern NSString* _Nonnull const TeakRavenLevelFatal;

@class Teak;

@interface TeakRavenLocationHelper : NSObject

@property (strong, nonatomic) NSException* _Nonnull exception;

+ (nonnull TeakRavenLocationHelper*)pushHelperForFile:(const char* _Nonnull)file line:(int)line function:(const char* _Nonnull)function;
+ (nullable TeakRavenLocationHelper*)popHelper;
+ (nullable TeakRavenLocationHelper*)peekHelper;

- (void)addBreadcrumb:(nonnull NSString*)category message:(nullable NSString*)message data:(nullable NSDictionary*)data file:(const char* _Nonnull)file line:(int)line;

@end

@interface TeakRaven : NSObject

+ (nullable TeakRaven*)ravenForTeak:(nonnull Teak*)teak;

- (BOOL)setDSN:(nonnull NSString*)dsn;
- (void)setUserValue:(nullable id)value forKey:(nonnull NSString*)key;
- (void)setAsUncaughtExceptionHandler;
- (void)unsetAsUncaughtExceptionHandler;

- (void)reportWithHelper:(nonnull TeakRavenLocationHelper*)helper;

+ (nonnull NSArray*)stacktraceSkippingFrames:(int)skipFrames;
+ (nonnull NSArray*)reverseStacktraceSkippingFrames:(int)skipFrames;
@end

#define teak_try           [TeakRavenLocationHelper pushHelperForFile:__FILE__ line:__LINE__ function:__PRETTY_FUNCTION__]; @try
#define teak_catch_report  @catch(NSException* exception) { [TeakRavenLocationHelper peekHelper].exception = exception; [[Teak sharedInstance].sdkRaven reportWithHelper:[TeakRavenLocationHelper peekHelper]]; } @finally { [TeakRavenLocationHelper popHelper]; }

#define teak_log_breadcrumb(message_nsstr) [[TeakRavenLocationHelper peekHelper] addBreadcrumb:@"log" message:message_nsstr data:nil file:__FILE__ line:__LINE__]
#define teak_log_data_breadcrumb(message_nsstr, data_nsdict) [[TeakRavenLocationHelper peekHelper] addBreadcrumb:@"log" message:message_nsstr data:data_nsdict file:__FILE__ line:__LINE__]
