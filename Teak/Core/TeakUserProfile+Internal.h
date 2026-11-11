#pragma once

#import "TeakUserProfile.h"

@interface TeakUserProfile ()
@property (strong, nonatomic) NSMutableDictionary* stringAttributes;
@property (strong, nonatomic) NSMutableDictionary* numberAttributes;
@property (strong, nonatomic) NSString* context;
@property (strong, nonatomic) dispatch_block_t scheduledBlock;
@property (strong, nonatomic) NSDate* firstSetTime;
@end
