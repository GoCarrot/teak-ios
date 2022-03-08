#import "TeakLaunchData.h"
#import "Teak+Internal.h"

extern BOOL TeakLink_WillHandleDeepLink(NSURL* deepLink);

@interface TeakLaunchDataOperation ()
@property (strong, nonatomic) NSURL* resolvedLaunchUrl;
@end

@interface TeakLaunchData ()
@property (copy, nonatomic, readwrite) NSURL* launchUrl;
@property (strong, nonatomic) NSDictionary* launchUrlQuery;

- (id)init;
- (id)initWithUrl:(NSURL*)url;
@end

@interface TeakAttributedLaunchData ()
@property (copy, nonatomic, readwrite) NSString* scheduleName;
@property (copy, nonatomic, readwrite) NSString* scheduleId;
@property (copy, nonatomic, readwrite) NSString* creativeName;
@property (copy, nonatomic, readwrite) NSString* creativeId;
@property (copy, nonatomic, readwrite) NSString* channelName;
@property (copy, nonatomic, readwrite) NSString* rewardId;
@property (copy, nonatomic, readwrite) NSURL* deepLink;
@property (strong, nonatomic) NSDictionary* deepLinkUrlQuery;

- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink;
@end

@interface TeakNotificationLaunchData ()
@property (copy, nonatomic, readwrite) NSString* sourceSendId;

- (id)initWithUrl:(NSURL*)url;
- (id)initWithTeakNotification:(TeakNotification*)teakNotification;
@end

@interface TeakRewardlinkLaunchData ()
- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink;
@end

/// Implementations

#define NewIfNotOld(x, y) (x == nil ? y : x)
#define ValueOrNSNull(x) (x == nil ? [NSNull null] : x)

@implementation TeakLaunchDataOperation

+ (TeakLaunchDataOperation*)fromPushNotification:(TeakNotification*)teakNotification {
  TeakNotificationLaunchData* notificationLaunchData = [[TeakNotificationLaunchData alloc] initWithTeakNotification:teakNotification];
  return [[TeakLaunchDataOperation alloc] initWithLaunchData:notificationLaunchData];
}

+ (TeakLaunchDataOperation*)fromUniversalLink:(NSURL*)url {
  TeakLaunchDataOperation* launchDataOp = [TeakLaunchDataOperation alloc];
  return [launchDataOp initWithTarget:launchDataOp selector:@selector(resolveUniversalLink:) object:url];
}

+ (TeakLaunchDataOperation*)fromOpenUrl:(NSURL*)url {
  NSDictionary* query = TeakGetQueryParameterDictionaryFromUrl(url);

  TeakLaunchData* launchData = nil;
  if (query[@"teak_rewardlink_id"]) {
    // If it has a 'teak_rewardlink_id' then it's a reward link
    launchData = [[TeakRewardlinkLaunchData alloc] initWithUrl:url andShortLink:nil];
  } else if (query[@"teak_notif_id"]) {
    // If it has a 'teak_notif_id' then it's a notification
    launchData = [[TeakNotificationLaunchData alloc] initWithUrl:url];
  } else {
    // Otherwise this is not a Teak attributed launch
    launchData = [[TeakLaunchData alloc] initWithUrl:url];
  }

  return [[TeakLaunchDataOperation alloc] initWithLaunchData:launchData];
}

+ (TeakLaunchDataOperation*)unattributed {
  return [[TeakLaunchDataOperation alloc] initWithLaunchData:[[TeakLaunchData alloc] init]];
}

- (id)initWithLaunchData:(TeakLaunchData*)launchData {
  return [super initWithTarget:self selector:@selector(returnLaunchData:) object:launchData];
}

- (TeakLaunchData*)returnLaunchData:(TeakLaunchData*)launchData {
  return launchData;
}

- (TeakLaunchDataOperation*)updateDeepLink:(NSURL*)updatedDeepLink {
  TeakLaunchData* launchData = self.result;
  if ([launchData isKindOfClass:TeakAttributedLaunchData.class]) {
    [launchData updateDeepLink:updatedDeepLink];
    return self;
  }

  // Create a new launch data operation and queue it (it uses the returnLaunchData: path)
  TeakLaunchDataOperation* launchDataOperation = [TeakLaunchDataOperation fromOpenUrl:updatedDeepLink];
  [[Teak sharedInstance].operationQueue addOperation:launchDataOperation];
  return launchDataOperation;
}

// This will get run as an NSInvocationOperation
- (TeakLaunchData*)resolveUniversalLink:(NSURL*)url {
  // Resolve the universal link, wait for the NSURLSession to complete (or timeout)
  // then run super, which will use the updated contents.
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  [self resolveUniversalLink:url retryCount:0 thenSignal:sema];
  dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

  // Process the resolved link
  NSDictionary* query = TeakGetQueryParameterDictionaryFromUrl(self.resolvedLaunchUrl);
  if (query[@"teak_rewardlink_id"]) {
    // If it has a 'teak_rewardlink_id' then it's a reward link
    return [[TeakRewardlinkLaunchData alloc] initWithUrl:self.resolvedLaunchUrl andShortLink:url];
  } else if (query[@"teak_notif_id"]) {
    // If it has a 'teak_notif_id' then it's a notification
    return [[TeakNotificationLaunchData alloc] initWithUrl:self.resolvedLaunchUrl];
  } else {
    // Otherwise this is not a Teak attributed launch
    return [[TeakLaunchData alloc] initWithUrl:url];
  }
}

- (void)resolveUniversalLink:(NSURL*)url retryCount:(int)retryCount thenSignal:(dispatch_semaphore_t)sema {
  // Make sure the URL we fetch is https
  NSURLComponents* components = [NSURLComponents componentsWithURL:url
                                           resolvingAgainstBaseURL:YES];
  components.scheme = @"https";
  NSURL* fetchUrl = components.URL;

  TeakLog_i(@"deep_link.request.send", [fetchUrl absoluteString]);
  // Fetch the data for the short link
  NSURLSession* session = [Teak URLSessionWithoutDelegate];
  NSURLSessionDataTask* task =
      [session dataTaskWithURL:fetchUrl
             completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
               // If we aren't already retrying, and there's any kind of error (for example iOS 12 malarky)
               // wait 1.5 seconds and retry.
               if (error != nil && retryCount < 1) {
                 __weak typeof(self) weakSelf = self;
                 double delayInSeconds = 1.5;
                 dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                 dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul), ^(void) {
                   [weakSelf resolveUniversalLink:url retryCount:retryCount + 1 thenSignal:sema];
                 });

                 // Bail out here so that we do not set the attribution
                 return;
               } else if (error != nil) {
                 // We already retried, and there's still an error, so log the error
                 TeakLog_e(@"deep_link.request.error", @{
                   @"url" : url.absoluteString,
                   @"error" : [error description]
                 });

                 // But don't return because we'll still send the link along as attribution
               } else {
                 TeakLog_i(@"deep_link.request.reply", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

                 NSDictionary* reply = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                 if (error == nil) {
                   NSString* iOSPath = reply[@"iOSPath"];
                   if (iOSPath != nil) {
                     NSRegularExpression* regExp = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z0-9+.\\-_]*:"
                                                                                             options:0
                                                                                               error:&error];

                     // Get resolved launchUrl
                     if (error != nil || [regExp numberOfMatchesInString:iOSPath
                                                                 options:0
                                                                   range:NSMakeRange(0, [iOSPath length])] == 0) {
                       self.resolvedLaunchUrl = [NSURL URLWithString:[NSString stringWithFormat:@"teak%@://%@",
                                                                                                [Teak sharedInstance].configuration.appConfiguration.appId,
                                                                                                iOSPath]];
                     } else {
                       self.resolvedLaunchUrl = [NSURL URLWithString:iOSPath];
                     }

                     TeakLog_i(@"deep_link.request.resolve", self.resolvedLaunchUrl.absoluteString);
                   }
                 } else {
                   TeakLog_e(@"deep_link.json.error", @{
                     @"url" : url.absoluteString,
                     @"error" : [error description]
                   });
                 }
               }

               // Signal, even if it ultimately failed
               dispatch_semaphore_signal(sema);
             }];
  [task resume];
}

@end

@implementation TeakLaunchData

- (id)init {
  return [self initWithUrl:nil];
}

- (id)initWithUrl:(NSURL*)url {
  self = [super init];
  if (self) {
    self.launchUrl = url;
    self.launchUrlQuery = TeakGetQueryParameterDictionaryFromUrl(url);
  }
  return self;
}

- (NSDictionary*)sessionAttribution {
  NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];

  if (self.launchUrl != nil) {
    dictionary[@"launch_link"] = ValueOrNSNull(self.launchUrl.absoluteString);
  }

  return dictionary;
}

- (NSDictionary*)to_h {
  NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];
  dictionary[@"launch_link"] = ValueOrNSNull(self.launchUrl.absoluteString);
  return dictionary;
}

- (void)updateDeepLink:(NSURL*)updatedDeepLink {
  // Empty on purpose
}

@end

@implementation TeakAttributedLaunchData

- (id)initWithUrl:(NSURL*)deepLink andShortLink:(NSURL*)shortLink {
  self = [super initWithUrl:shortLink];
  if (self) {
    self.deepLink = self.launchUrlQuery[@"teak_deep_link"] != nil ? [NSURL URLWithString:self.launchUrlQuery[@"teak_deep_link"]] : deepLink;
    self.deepLinkUrlQuery = TeakGetQueryParameterDictionaryFromUrl(self.deepLink);

    self.scheduleName = self.deepLinkUrlQuery[@"teak_schedule_name"];
    self.scheduleId = self.deepLinkUrlQuery[@"teak_schedule_id"];

    // In the non-mobile world, there is no such thing as "not a link launch" and so the
    // parameter names are different to properly differentiate session source
    self.creativeName = self.deepLinkUrlQuery[@"teak_creative_name"];
    if (self.creativeName == nil) {
      self.creativeName = self.deepLinkUrlQuery[@"teak_rewardlink_name"];
    }
    self.creativeId = self.deepLinkUrlQuery[@"teak_creative_id"];
    if (self.creativeId == nil) {
      self.creativeId = self.deepLinkUrlQuery[@"teak_rewardlink_id"];
    }

    self.channelName = self.deepLinkUrlQuery[@"teak_channel_name"];
    self.rewardId = self.deepLinkUrlQuery[@"teak_reward_id"];
  }
  return self;
}

- (id)initWithTeakNotification:(TeakNotification*)teakNotification {
  self = [super initWithUrl:[NSURL URLWithString:teakNotification.teakDeepLink]];
  if (self) {
    self.scheduleName = teakNotification.teakScheduleName;
    self.scheduleId = teakNotification.teakScheduleId;
    self.creativeName = teakNotification.teakCreativeName;
    self.creativeId = teakNotification.teakCreativeId;
    self.channelName = teakNotification.teakChannelName;
    self.rewardId = teakNotification.teakRewardId;
    self.deepLink = self.launchUrl; // 'teakNotification.teakDeepLink', resolved by call to super
    self.deepLinkUrlQuery = TeakGetQueryParameterDictionaryFromUrl(self.deepLink);
  }
  return self;
}

- (id)initWithAttributedLaunchData:(TeakAttributedLaunchData*)oldLaunchData andUpdatedDeepLink:(NSURL*)updatedDeepLink {
  self = [super initWithUrl:oldLaunchData.launchUrl];
  if (self) {
    TeakAttributedLaunchData* newLaunchData = [[TeakAttributedLaunchData alloc] initWithUrl:updatedDeepLink];
    self.scheduleName = NewIfNotOld(oldLaunchData.scheduleName, newLaunchData.scheduleName);
    self.scheduleId = NewIfNotOld(oldLaunchData.scheduleId, newLaunchData.scheduleId);
    self.creativeName = NewIfNotOld(oldLaunchData.creativeName, newLaunchData.creativeName);
    self.creativeId = NewIfNotOld(oldLaunchData.creativeId, newLaunchData.creativeId);
    self.rewardId = NewIfNotOld(oldLaunchData.rewardId, newLaunchData.rewardId);
    self.channelName = NewIfNotOld(oldLaunchData.channelName, newLaunchData.channelName);
    self.deepLink = updatedDeepLink;
    self.deepLinkUrlQuery = TeakGetQueryParameterDictionaryFromUrl(self.deepLink);
  }
  return self;
}

- (NSDictionary*)sessionAttribution {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super sessionAttribution];

  if (self.deepLink != nil) {
    dictionary[@"deep_link"] = self.deepLink.absoluteString;

    // Add any query parameter that starts with 'teak_' to the launch attribution dictionary
    for (NSString* key in self.deepLinkUrlQuery) {
      if ([key hasPrefix:@"teak_"]) {
        dictionary[key] = self.deepLinkUrlQuery[key];
      }
    }
  }

  return dictionary;
}

- (NSDictionary*)to_h {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super to_h];
  dictionary[@"teakScheduleName"] = ValueOrNSNull(self.scheduleName);
  dictionary[@"teakScheduleId"] = ValueOrNSNull(self.scheduleId);
  dictionary[@"teakCreativeName"] = ValueOrNSNull(self.creativeName);
  dictionary[@"teakCreativeId"] = ValueOrNSNull(self.creativeId);
  dictionary[@"teakRewardId"] = ValueOrNSNull(self.rewardId);
  dictionary[@"teakChannelName"] = ValueOrNSNull(self.channelName);
  dictionary[@"teakDeepLink"] = TeakLink_WillHandleDeepLink(self.launchUrl) ? self.launchUrl.absoluteString : [NSNull null];
  return dictionary;
}

- (void)updateDeepLink:(NSURL*)updatedDeepLink {
  TeakAttributedLaunchData* updatedLaunchData = [[TeakAttributedLaunchData alloc] initWithAttributedLaunchData:self andUpdatedDeepLink:updatedDeepLink];
  self.scheduleName = updatedLaunchData.scheduleName;
  self.scheduleId = updatedLaunchData.scheduleId;
  self.creativeName = updatedLaunchData.creativeName;
  self.creativeId = updatedLaunchData.creativeId;
  self.rewardId = updatedLaunchData.rewardId;
  self.channelName = updatedLaunchData.channelName;
  self.deepLink = updatedLaunchData.deepLink;
  self.deepLinkUrlQuery = updatedLaunchData.deepLinkUrlQuery;
}

@end

@implementation TeakNotificationLaunchData

- (id)initWithTeakNotification:(TeakNotification*)teakNotification {
  self = [super initWithTeakNotification:teakNotification];
  if (self) {
    self.sourceSendId = teakNotification.teakNotifId;
  }
  return self;
}

- (id)initWithUrl:(NSURL*)url {
  self = [super initWithUrl:url andShortLink:nil];
  if (self) {
    self.sourceSendId = self.deepLinkUrlQuery[@"teak_notif_id"];
  }
  return self;
}

- (id)initWithAttributedLaunchData:(TeakNotificationLaunchData*)oldLaunchData andUpdatedDeepLink:(NSURL*)updatedDeepLink {
  self = [super initWithAttributedLaunchData:oldLaunchData andUpdatedDeepLink:updatedDeepLink];
  if (self) {
    self.sourceSendId = NewIfNotOld(oldLaunchData.sourceSendId, self.deepLinkUrlQuery[@"teak_notif_id"]);
  }
  return self;
}

- (NSDictionary*)sessionAttribution {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super sessionAttribution];
  dictionary[@"teak_notif_id"] = self.sourceSendId;
  return dictionary;
}

- (NSDictionary*)to_h {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super to_h];
  dictionary[@"teakNotifId"] = ValueOrNSNull(self.sourceSendId);
  return dictionary;
}

- (void)updateDeepLink:(NSURL*)updatedDeepLink {
  [super updateDeepLink:updatedDeepLink];

  TeakNotificationLaunchData* updatedLaunchData = [[TeakNotificationLaunchData alloc] initWithAttributedLaunchData:self andUpdatedDeepLink:updatedDeepLink];
  self.sourceSendId = updatedLaunchData.sourceSendId;
}

@end

@implementation TeakRewardlinkLaunchData

- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink {
  self = [super initWithUrl:url andShortLink:shortLink];
  if (self) {
    // Nothing right now
  }
  return self;
}

@end
