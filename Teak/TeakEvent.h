/* Teak -- Copyright (C) 2017 GoCarrot Inc.
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

@class TeakEvent;
@class TeakEventHandler;

typedef void (^TeakEventHandlerBlock)(TeakEvent* _Nonnull);

@interface TeakEvent : NSObject

@property (strong, nonatomic, readonly) NSString* _Nonnull type;

+ (bool)postEvent:(TeakEvent* _Nonnull)event;

+ (void)addEventHandler:(TeakEventHandler* _Nonnull)handler;
+ (void)removeEventHandler:(TeakEventHandler* _Nonnull)handler;

@end

@interface TeakEventHandler : NSObject
@property (copy, nonatomic, readonly) TeakEventHandlerBlock _Nonnull block;
+ (nullable TeakEventHandler*)handlerWithBlock:(TeakEventHandlerBlock _Nonnull)block;
@end
