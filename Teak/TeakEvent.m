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

#import "TeakEvent.h"

NSString* TeakEventHandlersMutex = @"io.teak.sdk.eventHandlersMutex";
NSMutableSet* TeakEventHandlerSet;

@interface TeakEvent ()
@property (nonatomic, readwrite) TeakEventType type;
@end

@implementation TeakEvent

- (TeakEvent*)initWithType:(TeakEventType)type {
  self = [super init];
  if (self) {
    self.type = type;
  }
  return self;
}

+ (dispatch_queue_t)eventProcessingQueue {
  static dispatch_queue_t queue = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    queue = dispatch_queue_create("io.teak.sdk.eventProcessingQueue", NULL);
  });
  return queue;
}

+ (bool)postEvent:(TeakEvent* _Nonnull)event {
  dispatch_async([TeakEvent eventProcessingQueue], ^{
    NSSet* handlers = nil;
    @synchronized(TeakEventHandlersMutex) {
      handlers = TeakEventHandlerSet;
      TeakEventHandlerSet = [TeakEventHandlerSet copy];
    }

    for (id<TeakEventHandler> handler in handlers) {
      [handler handleEvent:event];
    }
  });
  return YES;
}

+ (void)addEventHandler:(id<TeakEventHandler> _Nonnull)handler {
  @synchronized(TeakEventHandlersMutex) {
    if (TeakEventHandlerSet == nil) TeakEventHandlerSet = [[NSMutableSet alloc] init];
    [TeakEventHandlerSet addObject:handler];
  }
}

+ (void)removeEventHandler:(id<TeakEventHandler> _Nonnull)handler {
  @synchronized(TeakEventHandlersMutex) {
    if (TeakEventHandlerSet == nil) TeakEventHandlerSet = [[NSMutableSet alloc] init];
    [TeakEventHandlerSet removeObject:handler];
  }
}

@end

@interface TeakEventBlockHandler ()
@property (copy, nonatomic) TeakEventHandlerBlock _Nonnull block;
@end

@implementation TeakEventBlockHandler
+ (nonnull TeakEventBlockHandler*)handlerWithBlock:(TeakEventHandlerBlock _Nonnull)block {
  TeakEventBlockHandler* handler = [[TeakEventBlockHandler alloc] init];
  handler.block = block;
  return handler;
}

- (void)handleEvent:(TeakEvent* _Nonnull)event {
  self.block(event);
}
@end
