#import <UIKit/UIKit.h>

#import "TeakEvent.h"
#import "TeakState.h"

@interface TeakPushState : NSObject <TeakEventHandler>

DeclareTeakState(NotDetermined);
DeclareTeakState(Provisional);
DeclareTeakState(Authorized);
DeclareTeakState(Denied);

- (NSInvocationOperation* _Nonnull)currentPushState;
- (void)determineCurrentPushStateWithCompletionHandler:(void (^_Nonnull)(TeakState* _Nonnull))completionHandler;
- (nonnull NSDictionary*)to_h;

@end
