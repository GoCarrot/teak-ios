#import "TeakState.h"

@interface TeakState ()
@property (strong, nonatomic, readwrite) NSString* name;

@property (strong, nonatomic) NSArray* allowedTransitions;
@end

@implementation TeakState

DefineTeakState(Invalid, (@[]));

- (id)initWithName:(nonnull NSString*)name allowedTransitions:(nonnull NSArray*)allowedTransitions {
  self = [super init];
  if (self) {
    self.name = name;
    for (id state in allowedTransitions) {
      if (![state isKindOfClass:[NSString class]]) {
        [NSException raise:NSInvalidArgumentException format:@"Non-NSString element of allowedTransitions. Returning nil."];
        return nil;
      }
    }
    self.allowedTransitions = allowedTransitions;
  }
  return self;
}

- (BOOL)canTransitionToState:(nonnull TeakState*)nextState {
  if (nextState == [TeakState Invalid]) return YES;
  for (NSString* stateName in self.allowedTransitions) {
    if ([stateName isEqualToString:nextState.name]) return YES;
  }
  return NO;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> name: %@", NSStringFromClass([self class]), self, self.name];
}
@end
