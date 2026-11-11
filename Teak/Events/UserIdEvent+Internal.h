#pragma once

#import "UserIdEvent.h"

@interface UserIdEvent ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull userId;
@property (strong, nonatomic, readwrite) TeakUserConfiguration* _Nonnull userConfiguration;
@end
