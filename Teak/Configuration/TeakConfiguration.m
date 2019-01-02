#import "TeakConfiguration.h"

@interface TeakConfiguration ()
@property (strong, nonatomic, readwrite) TeakDebugConfiguration* _Nonnull debugConfiguration;
@property (strong, nonatomic, readwrite) TeakAppConfiguration* _Nonnull appConfiguration;
@property (strong, nonatomic, readwrite) TeakDeviceConfiguration* _Nonnull deviceConfiguration;
@property (strong, nonatomic, readwrite) TeakDataCollectionConfiguration* _Nonnull dataCollectionConfiguration;
@end

TeakConfiguration* TeakConfigurationInstance = nil;

@implementation TeakConfiguration

+ (nonnull TeakConfiguration*)configuration {
  if (TeakConfigurationInstance == nil) {
    [NSException raise:NSObjectNotAvailableException format:@"TeakConfiguration was not initialized before accessing."];
  }
  return TeakConfigurationInstance;
}

+ (BOOL)configureForAppId:(NSString* _Nonnull)appId andSecret:(NSString* _Nonnull)appSecret {
  if (TeakConfigurationInstance != nil) {
    [NSException raise:NSObjectNotAvailableException format:@"TeakConfiguration double-initialized."];
    return NO;
  }
  TeakConfigurationInstance = [[TeakConfiguration alloc] initForAppId:appId andSecret:appSecret];
  return (TeakConfigurationInstance != nil);
}

- (id)initForAppId:(NSString* _Nonnull)appId andSecret:(NSString* _Nonnull)appSecret {
  self = [super init];
  if (self) {
    self.debugConfiguration = [[TeakDebugConfiguration alloc] init];

    self.appConfiguration = [[TeakAppConfiguration alloc] initWithAppId:appId apiKey:appSecret];
    if (self.appConfiguration == nil) {
      [NSException raise:NSObjectNotAvailableException format:@"Teak App Configuration is nil."];
      return nil;
    }

    self.deviceConfiguration = [[TeakDeviceConfiguration alloc] init];
    if (self.deviceConfiguration == nil) {
      [NSException raise:NSObjectNotAvailableException format:@"Teak Device Configuration is nil."];
      return nil;
    }

    self.dataCollectionConfiguration = [[TeakDataCollectionConfiguration alloc] init];
    if (self.dataCollectionConfiguration == nil) {
      [NSException raise:NSObjectNotAvailableException format:@"Teak Data Collection Configuration is nil."];
      return nil;
    }
  }
  return self;
}

@end
