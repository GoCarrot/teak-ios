#import "TeakIntegrationChecker.h"
#import "RemoteConfigurationEvent.h"
#import <Teak/Teak.h>

@interface TeakIntegrationChecker ()
@property (nonatomic) BOOL enhancedIntegrationChecks;
@property (strong, nonatomic) NSMutableDictionary* errorsToReport;
@end

@implementation TeakIntegrationChecker

+ (TeakIntegrationChecker*)checkIntegrationForTeak:(nonnull Teak*)teak {
  return [[TeakIntegrationChecker alloc] initForTeak:teak];
}

- (id)initForTeak:(nonnull Teak*)teak {
  self = [super init];

  if (self) {
    self.enhancedIntegrationChecks = NO;
    self.errorsToReport = [[NSMutableDictionary alloc] init];
    [TeakEvent addEventHandler:self];
  }

  return self;
}

- (void)dealloc {
  [TeakEvent removeEventHandler:self];
}

- (void)handleEvent:(TeakEvent* _Nonnull)event {
  if (event.type == RemoteConfigurationReady) {
    TeakRemoteConfiguration* remoteConfiguration = ((RemoteConfigurationEvent*)event).remoteConfiguration;
    self.enhancedIntegrationChecks = remoteConfiguration.enhancedIntegrationChecks;

    // Report pending errors
    if (self.enhancedIntegrationChecks) {
      @synchronized(self.errorsToReport) {
        for (id key in self.errorsToReport) {
          [self displayErrorWithDescription:self.errorsToReport[key] andCategory:key];
        }

        // Clear pending errors
        [self.errorsToReport removeAllObjects];
      }
    }
  }
}

- (void)reportError:(nonnull NSString*)description forCategory:(nonnull NSString*)category {
  if (self.enhancedIntegrationChecks) {
    [self displayErrorWithDescription:description andCategory:category];
  } else {
    @synchronized(self.errorsToReport) {
      self.errorsToReport[category] = description;
    }
  }
}

- (void)displayErrorWithDescription:(nonnull NSString*)description andCategory:(nonnull NSString*)category {
  // Execute on the main thread
  dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIAlertView* alert = [[UIAlertView alloc] initWithTitle:category
                                                    message:description
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
#pragma clang diagnostic pop
  });
}

@end
