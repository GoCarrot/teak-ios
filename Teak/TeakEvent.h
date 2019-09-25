#import <Foundation/Foundation.h>

@class TeakEvent;
@protocol TeakEventHandler;

typedef enum {
  PushRegistered,
  PushUnRegistered,
  UserIdentified,
  TrackedEvent,
  PurchaseFailed,
  PurchaseSucceeded,
  LifecycleFinishedLaunching,
  LifecycleActivate,
  LifecycleDeactivate,
  FacebookAccessToken,
  RemoteConfigurationReady,
  AdditionalData
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
