#import <Foundation/Foundation.h>

#define DeclareTeakState(_name) +(nonnull TeakState*)_name

#define DefineTeakState(_name, _allowedTransitions)                                                                             \
  +(nonnull TeakState*)_name {                                                                                                  \
    static TeakState* _state = nil;                                                                                             \
    static dispatch_once_t onceToken;                                                                                           \
    dispatch_once(&onceToken, ^{ _state = [[TeakState alloc] initWithName:@ #_name allowedTransitions:_allowedTransitions]; }); \
    return _state;                                                                                                              \
  }

@interface TeakState : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull name;

- (nullable id)initWithName:(nonnull NSString*)name allowedTransitions:(nonnull NSArray*)allowedTransitions;
- (BOOL)canTransitionToState:(nonnull TeakState*)nextState;

+ (nonnull TeakState*)Invalid;
@end
