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

extern NSString* const TeakRavenLevelError;
extern NSString* const TeakRavenLevelFatal;

@interface TeakRavenLocationHelper : NSObject

@property (strong, nonatomic) NSException* exception;

+ (TeakRavenLocationHelper*)helperForFile:(const char*)file line:(int)line function:(const char*)function;

@end

@interface TeakRaven : NSObject

+ (TeakRaven*)ravenForApp:(nonnull NSString*)appId;

- (BOOL)setDSN:(NSString*)dsn;
- (void)setUserValue:(id)value forKey:(nonnull NSString*)key;
- (void)setAsUncaughtExceptionHandler;

- (void)reportException:(nonnull NSException*)exception level:(nonnull NSString*)level;
- (void)reportWithHelper:(TeakRavenLocationHelper*)helper;

@end
