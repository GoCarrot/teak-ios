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
// An update is waiting for the last send's reply. Only touched on operationQueue.
@property (nonatomic) BOOL sendWaitingForReply;
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

// Starts a send only when an attribute change is pending.
- (void)send {
  // Hop onto the serial operationQueue that setAttribute:forKey:inDictionary: mutates the
  // attribute dictionaries on, so these reads are never concurrent with those writes.
  dispatch_async([Teak operationQueue], ^{
    // No scheduledBlock means no pending update
    if (self.scheduledBlock != nil) {
      dispatch_block_cancel(self.scheduledBlock);
      self.scheduledBlock = nil;
      [self sendOrWaitForReply];
    }
  });
}

// Every send carries the full attribute dictionaries, not just what changed, so a new send covers
// everything the last one did, and the last one's retries can go. But if the last one is on the
// wire, cancelling it can't stop the server from applying it after the new one. Then the new send
// waits for that reply instead. Runs on operationQueue.
- (void)sendOrWaitForReply {
  if ([self.currentSend supersede]) {
    if (!self.sendWaitingForReply) {
      TeakLog_i(@"user_profile.send.held", [self.currentSend to_h]);
    }
    self.sendWaitingForReply = YES;
    return;
  }

  // Built here, not when the update was scheduled, so a send that waited carries the latest values.
  NSMutableDictionary* payload = [self.payload mutableCopy];
  [payload addEntriesFromDictionary:@{
    @"string_attributes" : [self.stringAttributes copy],
    @"number_attributes" : [self.numberAttributes copy],
    @"context" : [self.context copy],
    @"ms_since_first_event" : [NSNumber numberWithDouble:[self.firstSetTime timeIntervalSinceNow] * -1000.0]
  }];
  self.payload = payload;

  // Whatever was held goes out with this send.
  self.sendWaitingForReply = NO;
  [super send];

  self.firstSetTime = nil;
}

- (void)response:(NSHTTPURLResponse*)response payload:(NSDictionary*)payload withError:(NSError*)error forSend:(TeakRequestSend*)send {
  [super response:response payload:payload withError:error forSend:send];

  dispatch_async([Teak operationQueue], ^{
    if (self.sendWaitingForReply && send == self.currentSend) {
      // The held update goes out now, so a timer still armed for it would only repeat it.
      if (self.scheduledBlock != nil) {
        dispatch_block_cancel(self.scheduledBlock);
        self.scheduledBlock = nil;
      }
      // The send that was out is finished; there's nothing of it left to cancel.
      self.currentSend = nil;
      TeakLog_i(@"user_profile.send.released", [send to_h]);
      [self sendOrWaitForReply];
    }
  });
}

@end
