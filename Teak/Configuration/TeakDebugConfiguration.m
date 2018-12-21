#import "TeakDebugConfiguration.h"
#import "Teak+Internal.h"

#define kLogLocalPreferencesKey @"TeakLogLocal"
#define kLogRemotePreferencesKey @"TeakLogRemote"

@interface TeakDebugConfiguration ()
@property (nonatomic, readwrite) BOOL logLocal;
@property (nonatomic, readwrite) BOOL logRemote;

@property (strong, nonatomic) NSUserDefaults* userDefaults;
@end

@implementation TeakDebugConfiguration

- (id)init {
  self = [super init];
  if (self) {
    teak_try {
      self.userDefaults = [NSUserDefaults standardUserDefaults];
    }
    teak_catch_report;

    if (self.userDefaults == nil) {
      NSLog(@"[NSUserDefaults standardUserDefaults] returned nil. Some debug functionality is disabled.");
    } else {
      self.logLocal = [self.userDefaults boolForKey:kLogLocalPreferencesKey];
      self.logRemote = [self.userDefaults boolForKey:kLogRemotePreferencesKey];
    }
  }
  return self;
}

- (void)setLogLocal:(BOOL)logLocal logRemote:(BOOL)logRemote {
  if (self.userDefaults == nil) {
    TeakLog_e(@"debug_configuration", @"[NSUserDefaults standardUserDefaults] returned nil. Setting force debug is disabled.");
  } else {
    @try {
      [self.userDefaults setBool:logLocal forKey:kLogLocalPreferencesKey];
      [self.userDefaults setBool:logRemote forKey:kLogRemotePreferencesKey];
    } @catch (NSException* exception) {
      NSLog(@"Error occurred while writing to userDefaults. %@", exception);
    }
    self.logLocal = logLocal;
    self.logRemote = logRemote;
  }
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %@> logLocal %@, logRemote %@", NSStringFromClass([self class]),
                                    [NSString stringWithFormat:@"0x%16@", self],
                                    self.logLocal ? @"YES" : @"NO", self.logRemote ? @"YES" : @"NO"];
}
@end
