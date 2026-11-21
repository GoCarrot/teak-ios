#import "TeakUserProfile.h"
#import "Teak+Internal.h"
#import "TeakSession.h"
#import "TeakHelpers.h"

@interface TeakUserProfile ()
@property (strong, nonatomic) NSMutableDictionary* stringAttributes;
@property (strong, nonatomic) NSMutableDictionary* numberAttributes;
@property (strong, nonatomic) NSString* context;
@property (strong, nonatomic) dispatch_block_t scheduledBlock;
@property (strong, nonatomic) NSDate* firstSetTime;
// Orders this profile's sends for the server: 1 for the first payload, +1 for each after. Only
// touched on operationQueue.
@property (nonatomic) NSUInteger profileSeq;
@end

@implementation TeakUserProfile

- (TeakUserProfile*)initForSession:(TeakSession*)session withDictionary:(NSDictionary*)dictionary {
  self = [super initWithSession:session forHostname:kTeakHostname withEndpoint:@"/me/profile" withPayload:@{} method:TeakRequest_POST callback:nil addCommonPayload:YES];
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
  // The nil-guard, firstSetTime stamp, equality test, and write all run on the serial
  // operationQueue so the dictionary is only ever touched from one queue. Reading the
  // dict on the caller's queue while the writer mutates it here is a use-after-free.
  dispatch_async([Teak operationQueue], ^{
    // Future-Pat: *only* check vs nil here, not NSNull. NSNull is fine.
    if (dictionary[key] == nil) {
      return;
    }

    if (self.firstSetTime == nil) {
      self.firstSetTime = [NSDate date];
    }

    BOOL safeNotEquals = dictionary[key] == [NSNull null] || ![dictionary[key] isEqual:value];

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

// Starts a send only when an attribute change is pending. The send happens on the operation queue,
// so this always returns YES, and a callback runs only if an update was pending.
- (BOOL)send {
  // Hop onto the serial operationQueue that setAttribute:forKey:inDictionary: mutates the
  // attribute dictionaries on, so these reads are never concurrent with those writes.
  dispatch_async([Teak operationQueue], ^{
    // No scheduledBlock means no pending update
    if (self.scheduledBlock != nil) {
      dispatch_block_cancel(self.scheduledBlock);
      self.scheduledBlock = nil;

      NSMutableDictionary* payload = [self.payload mutableCopy];
      [payload addEntriesFromDictionary:@{
        @"string_attributes" : [self.stringAttributes copy],
        @"number_attributes" : [self.numberAttributes copy],
        @"context" : [self.context copy],
        // Cancelling the last send can't recall bytes already on the wire, so the server uses
        // this to tell which of two overlapping sends is newer. A retry resends the frozen
        // send, so it keeps its number.
        @"profile_seq" : @(++self.profileSeq),
        @"ms_since_first_event" : [NSNumber numberWithDouble:[self.firstSetTime timeIntervalSinceNow] * -1000.0]
      }];
      self.payload = payload;

      // Every send carries the full attribute dictionaries, not just what changed, so this send
      // covers everything the last one did. Cancel the last one rather than let its retries or
      // its attempt in flight land after this one with older values.
      [self.currentSend cancel];
      [super send];

      self.firstSetTime = nil;
    }
  });
  return YES;
}

@end
