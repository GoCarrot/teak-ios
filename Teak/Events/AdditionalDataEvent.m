#import "AdditionalDataEvent.h"

@interface AdditionalDataEvent ()
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull additionalData;
@end

@implementation AdditionalDataEvent

+ (void)additionalDataReceived:(NSDictionary*)additionalData {
  AdditionalDataEvent* event = [[AdditionalDataEvent alloc] initWithType:AdditionalData];
  event.additionalData = additionalData;
  [TeakEvent postEvent:event];
}
@end
