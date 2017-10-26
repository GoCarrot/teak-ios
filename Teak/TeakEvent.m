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

NSString* eventHandlersMutex = @"io.teak.sdk.eventHandlersMutex";
NSMutableSet* eventHandlers;

@implementation TeakEvent

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
    @synchronized(eventHandlersMutex) {
      handlers = eventHandlers;
      eventHandlers = [eventHandlers copy];
    }

    for (TeakEventHandler* handler in handlers) {
      handler.block(event);
    }
  });
  return YES;
}

+ (void)addEventHandler:(TeakEventHandler* _Nonnull)handler {
  @synchronized(eventHandlersMutex) {
    [eventHandlers addObject:handler];
  }
}

+ (void)removeEventHandler:(TeakEventHandler* _Nonnull)handler {
  @synchronized(eventHandlersMutex) {
    [eventHandlers removeObject:handler];
  }
}

@end

///// TeakEventHandler

@interface TeakEventHandler ()
@property (copy, nonatomic, readwrite) TeakEventHandlerBlock _Nonnull block;
@end

@implementation TeakEventHandler
+ (nullable TeakEventHandler*)handlerWithBlock:(TeakEventHandlerBlock _Nonnull)block {
  TeakEventHandler* ret = [[TeakEventHandler alloc] init];
  if (ret) {
    ret.block = block;
  }
  return ret;
}
@end
