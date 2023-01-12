#import "TeakChannelStatus.h"

NSString* _Nonnull const TeakChannelStatusOptOut = @"opt_out";
NSString* _Nonnull const TeakChannelStatusAvailable = @"available";
NSString* _Nonnull const TeakChannelStatusOptIn = @"opt_in";
NSString* _Nonnull const TeakChannelStatusAbsent = @"absent";
NSString* _Nonnull const TeakChannelStatusUnknown = @"unknown";

@interface TeakChannelStatus ()
@property (strong, nonatomic, readwrite) NSString* status;
@property (nonatomic, readwrite) BOOL deliveryFault;
@end

@implementation TeakChannelStatus

+ (nonnull TeakChannelStatus*)unknown {
  static TeakChannelStatus* unknownStatus = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    unknownStatus = [[TeakChannelStatus alloc] initWithStatus:TeakChannelStatusUnknown hasDeliveryFault:false];
  });
  return unknownStatus;
}

- (id)initWithStatus:(NSString*)status hasDeliveryFault:(BOOL)deliveryFault {
  static dispatch_once_t onceToken;
  static NSArray* TeakChannelStatusStates = nil;
  dispatch_once(&onceToken, ^{
    TeakChannelStatusStates = @[
      TeakChannelStatusOptOut,
      TeakChannelStatusAvailable,
      TeakChannelStatusOptIn,
      TeakChannelStatusAbsent
    ];
  });

  self = [super init];
  if (self) {
    if ([TeakChannelStatusStates containsObject:status]) {
      self.status = status;
      self.deliveryFault = deliveryFault;
    } else {
      return [TeakChannelStatus unknown];
    }
  }
  return self;
}

- (id)initWithDictionary:(NSDictionary*)dictionary {
  return [[TeakChannelStatus alloc] initWithStatus:[dictionary[@"state"] stringValue]
                                  hasDeliveryFault:[dictionary[@"delivery_fault"] boolValue]];
}

- (NSDictionary*)toDictionary {
  return @{
    @"state" : self.status,
    @"delivery_fault" : self.deliveryFault ? @"true" : @"false"
  };
}

@end
