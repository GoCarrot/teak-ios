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
@protocol TeakEventHandler;

typedef enum {
  PushRegistered,
  PushUnRegistered,
  UserIdentified
} TeakEventType;

typedef void (^TeakEventHandlerBlock)(TeakEvent* _Nonnull);

@interface TeakEvent : NSObject

@property (nonatomic, readonly) TeakEventType type;
- (nonnull TeakEvent*)initWithType:(TeakEventType)type;

+ (bool)postEvent:(TeakEvent* _Nonnull)event;

+ (void)addEventHandler:(id<TeakEventHandler> _Nonnull)handler;
+ (void)removeEventHandler:(id<TeakEventHandler> _Nonnull)handler;

@end

@protocol TeakEventHandler
@required
- (void)handleEvent:(TeakEvent* _Nonnull)event;
@end

@interface TeakEventBlockHandler : NSObject <TeakEventHandler>
+ (nonnull TeakEventBlockHandler*)handlerWithBlock:(TeakEventHandlerBlock _Nonnull)block;
@end
