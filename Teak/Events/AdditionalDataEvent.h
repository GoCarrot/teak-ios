#import "TeakEvent.h"

@interface AdditionalDataEvent : TeakEvent
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull additionalData;

+ (void)additionalDataReceived:(NSDictionary* _Nonnull)additionalData;
@end
