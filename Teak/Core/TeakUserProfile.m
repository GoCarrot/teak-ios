#import "TeakUserProfile.h"
#import "Teak+Internal.h"
#import "TeakSession.h"

@interface TeakUserProfile ()
@property (strong, nonatomic) NSMutableDictionary* stringAttributes;
@property (strong, nonatomic) NSMutableDictionary* numberAttributes;
@property (strong, nonatomic) NSString* context;
@property (strong, nonatomic) dispatch_block_t scheduledBlock;
@property (strong, nonatomic) NSDate* firstSetTime;
@end

@implementation TeakUserProfile

- (TeakUserProfile*)initForSession:(TeakSession*)session withDictionary:(NSDictionary*)dictionary {
  self = [super initWithSession:session forHostname:kTeakHostname withEndpoint:@"/me/profile" withPayload:@{} callback:nil addCommonPayload:YES];
  if (self) {
    self.stringAttributes = [dictionary[@"string_attributes"] mutableCopy];
    self.numberAttributes = [dictionary[@"number_attributes"] mutableCopy];
    self.context = [dictionary[@"context"] copy];
  }
  return self;
}

- (void)setNumericAttribute:(double)value forKey:(NSString*)key {
  [self setAttribute:[NSNumber numberWithDouble:value] forKey:key inDictionary:self.numberAttributes];
}

- (void)setStringAttribute:(NSString*)value forKey:(NSString*)key {
  [self setAttribute:value forKey:key inDictionary:self.stringAttributes];
}

- (void)setAttribute:(id)value forKey:(NSString*)key inDictionary:(NSMutableDictionary*)dictionary {
  // Future-Pat: *only* check vs nil here, not NSNull. NSNull is fine.
  if (dictionary[key] != nil) {
    if (self.firstSetTime == nil) {
      self.firstSetTime = [NSDate date];
    }

    dispatch_async([Teak operationQueue], ^{
      BOOL safeNotEquals = YES;
      @try {
        safeNotEquals = dictionary[key] == [NSNull null] || ![dictionary[key] isEqual:value];
      } @finally {
      }

      if (safeNotEquals) {
        if (self.scheduledBlock != nil) {
          dispatch_block_cancel(self.scheduledBlock);
        }

        dictionary[key] = value;

        self.scheduledBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
          [self send];
        });

        dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, self.batch.time * NSEC_PER_SEC);
        dispatch_after(delayTime, [Teak operationQueue], self.scheduledBlock);
      }
    });
  }
}

- (void)send {
  // No scheduledBlock means no pending update
  if (self.scheduledBlock != nil) {
    dispatch_block_cancel(self.scheduledBlock);
    self.scheduledBlock = nil;

    NSMutableDictionary* payload = [self.payload mutableCopy];
    [payload addEntriesFromDictionary:@{
      @"string_attributes" : [self.stringAttributes copy],
      @"number_attributes" : [self.numberAttributes copy],
      @"context" : [self.context copy],
      @"ms_since_first_event" : [NSNumber numberWithDouble:[self.firstSetTime timeIntervalSinceNow] * -1000.0]
    }];
    self.payload = payload;

    [super send];

    self.firstSetTime = nil;
  }
}

@end
