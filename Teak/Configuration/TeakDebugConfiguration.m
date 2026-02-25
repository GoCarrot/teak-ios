#import "TeakDebugConfiguration.h"
#import "Teak+Internal.h"

#define kLogLocalPreferencesKey @"TeakLogLocal"
#define kLogRemotePreferencesKey @"TeakLogRemote"
#define kTeakForceDebugOutput @"TeakForceDebugOutput"

@interface TeakDebugConfiguration ()
@property (nonatomic, readwrite) BOOL logLocal;
@property (nonatomic, readwrite) BOOL logRemote;

@property (nonatomic) BOOL forceDebugOutput;
@property (strong, nonatomic) NSUserDefaults* userDefaults;
@end

@implementation TeakDebugConfiguration

- (id)init {
  NSUserDefaults* defaults = nil;
  teak_try {
    defaults = [NSUserDefaults standardUserDefaults];
  }
  teak_catch_report;

  return [self initWithUserDefaults:defaults infoDictionary:[[NSBundle mainBundle] infoDictionary]];
}

- (id)initWithUserDefaults:(NSUserDefaults*)userDefaults infoDictionary:(NSDictionary*)infoDictionary {
  self = [super init];
  if (self) {
    self.userDefaults = userDefaults;

    if (self.userDefaults == nil) {
      NSLog(@"Teak: [NSUserDefaults standardUserDefaults] returned nil. Some debug functionality is disabled.");
    } else {
      self.logLocal = [self.userDefaults boolForKey:kLogLocalPreferencesKey];
      self.logRemote = [self.userDefaults boolForKey:kLogRemotePreferencesKey];
    }

    // Store and apply Info.plist TeakForceDebugOutput (local logging only).
    // This flag is authoritative — it survives server responses that call setLogLocal:logRemote:.
    if ([infoDictionary objectForKey:kTeakForceDebugOutput] != nil) {
      self.forceDebugOutput = [[infoDictionary objectForKey:kTeakForceDebugOutput] boolValue];
    }
    self.logLocal |= self.forceDebugOutput;
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
      NSLog(@"Teak: Error occurred while writing to userDefaults. %@", exception);
    }
    self.logLocal = logLocal | self.forceDebugOutput;
    self.logRemote = logRemote;
  }
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %@> logLocal %@, logRemote %@", NSStringFromClass([self class]),
                                    [NSString stringWithFormat:@"0x%16@", self],
                                    self.logLocal ? @"YES" : @"NO", self.logRemote ? @"YES" : @"NO"];
}
@end
