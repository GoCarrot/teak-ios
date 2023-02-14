#import "TeakChannelStatus.h"

NSString* _Nonnull const TeakChannelStateOptOut = @"opt_out";
NSString* _Nonnull const TeakChannelStateAvailable = @"available";
NSString* _Nonnull const TeakChannelStateOptIn = @"opt_in";
NSString* _Nonnull const TeakChannelStateAbsent = @"absent";
NSString* _Nonnull const TeakChannelStateUnknown = @"unknown";

NSString* _Nonnull const TeakChannelTypePush = @"push";
NSString* _Nonnull const TeakChannelTypeEmail = @"email";
NSString* _Nonnull const TeakChannelTypeSms = @"sms";
NSString* _Nonnull const TeakChannelTypeUnknown = @"unknown";

@interface TeakChannelStatus ()
@property (strong, nonatomic, readwrite) NSString* state;
@property (nonatomic, readwrite) BOOL deliveryFault;
@end

@implementation TeakChannelStatus

+ (nonnull TeakChannelStatus*)unknown {
  static TeakChannelStatus* unknownStatus = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    unknownStatus = [[TeakChannelStatus alloc] initWithState:TeakChannelStateUnknown hasDeliveryFault:false];
  });
  return unknownStatus;
}

- (id)initWithState:(NSString*)state hasDeliveryFault:(BOOL)deliveryFault {
  static dispatch_once_t onceToken;
  static NSArray* TeakChannelStates = nil;
  dispatch_once(&onceToken, ^{
    TeakChannelStates = @[
      TeakChannelStateOptOut,
      TeakChannelStateAvailable,
      TeakChannelStateOptIn,
      TeakChannelStateAbsent
    ];
  });

  self = [super init];
  if (self) {
    if ([state isEqualToString:TeakChannelStateUnknown] || [TeakChannelStates containsObject:state]) {
      self.state = state;
      self.deliveryFault = deliveryFault;
    } else {
      return [TeakChannelStatus unknown];
    }
  }
  return self;
}

- (id)initWithDictionary:(NSDictionary*)dictionary {
  if (dictionary == nil) return [TeakChannelStatus unknown];

  return [[TeakChannelStatus alloc] initWithState:dictionary[@"state"]
                                  hasDeliveryFault:[dictionary[@"delivery_fault"] boolValue]];
}

- (NSDictionary*)toDictionary {
  return @{
    @"state" : self.state,
    @"delivery_fault" : self.deliveryFault ? @"true" : @"false"
  };
}

@end
