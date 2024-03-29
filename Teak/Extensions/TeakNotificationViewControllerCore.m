#import <AVKit/AVKit.h>
#import <Teak/TeakNotificationViewControllerCore.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

/////
// For XCode 8.x
#import <AVFoundation/AVFoundation.h>

#define iOS12OrGreater() ([[UIDevice currentDevice].systemVersion doubleValue] >= 12.0)
/////

extern UIImage* UIImage_animatedImageWithAnimatedGIFData(NSData* data);
extern void TeakAssignPayloadToRequest(NSString* method, NSMutableURLRequest* request, NSDictionary* payload);

/////

@interface TeakAVPlayerView : UIView
@property (strong, nonatomic, setter=setPlayer:) AVPlayer* player;

+ (Class)layerClass;
- (void)setPlayer:(AVPlayer*)player;
@end

@implementation TeakAVPlayerView
+ (Class)layerClass {
  return [AVPlayerLayer class];
}

- (void)setPlayer:(AVPlayer*)player {
  [(AVPlayerLayer*)self.layer setPlayer:player];
  _player = player;
}
@end

/////

@interface UIImageArrayView : UIImageView
@property (strong, nonatomic, setter=setImageArray:) NSArray* imageArray;
@property (nonatomic, setter=setImageIndex:) NSUInteger imageIndex;

- (id)initWithImageArray:(NSArray*)imageArray;
- (void)setImageArray:(NSArray*)imageArray;
@end

@implementation UIImageArrayView
- (id)initWithImageArray:(NSArray*)imageArray {
  self = [super init];
  if (self) {
    self.imageArray = imageArray;
  }
  return self;
}

- (void)setImageArray:(NSArray*)imageArray {
  _imageArray = imageArray;
  self.imageIndex = 0;
}

- (void)setImageIndex:(NSUInteger)imageIndex {
  _imageIndex = imageIndex;
  self.image = self.imageArray[_imageIndex];
}
@end

/////

@interface TeakNotificationViewControllerCore () <UNNotificationContentExtension>
@property (strong, nonatomic) NSURLSession* session;
@property (strong, nonatomic) NSOperationQueue* operationQueue;
@property (strong, nonatomic) NSOperation* sessionFinishOperation;
@property (strong, nonatomic) NSArray* assets;
@property (strong, nonatomic) NSDictionary* notificationUserData;

// Video related
@property (strong, nonatomic) AVPlayerLooper* playerLooper;
@property (strong, nonatomic) AVPlayer* videoPlayer;

// Common parent view for whatever is in the notification.
@property (strong, nonatomic) UIView* notificationContentView;

// Configuration
@property (strong, nonatomic) NSDictionary* actions;
@property (nonatomic) BOOL autoPlay;
@property (nonatomic) BOOL loopInitialContent;
@property (nonatomic, copy) void (^prepareContentView)(void);

// Input
@property (nonatomic) dispatch_once_t inputHandlerDispatchOnce;
@end

@implementation TeakNotificationViewControllerCore

- (void)viewDidLoad {
  [super viewDidLoad];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];

  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self.videoPlayer pause];
  self.videoPlayer = nil;
}

- (void)configureForNotification:(UNNotification*)notification {
  self.notificationUserData = notification.request.content.userInfo[@"aps"];

  // Button actions, nil = just launch the app
  self.actions = self.notificationUserData[@"playableActions"];
  if (self.actions == nil || self.actions == (NSDictionary*)[NSNull null]) {
    self.actions = [[NSDictionary alloc] init];
  }

  // Video options
  self.autoPlay = TeakBoolFor(self.notificationUserData[@"autoplay"]);
  self.loopInitialContent = TeakBoolFor(self.notificationUserData[@"loopInitialContent"]);
}

- (void)initURLSession {
  self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
  self.operationQueue = [[NSOperationQueue alloc] init];
  __weak typeof(self) weakSelf = self;
  self.sessionFinishOperation = [NSBlockOperation blockOperationWithBlock:^{
    __strong typeof(self) blockSelf = weakSelf;
    [blockSelf.session finishTasksAndInvalidate];
  }];
}

- (void)queueMetricSend {
  NSString* teakNotifId = TeakNSStringOrNilFor(self.notificationUserData[@"teakNotifId"]);
  NSString* teakUserId = TeakNSStringOrNilFor(self.notificationUserData[@"teakUserId"]);
  if ([teakNotifId length] > 0 && [teakUserId length] > 0) {
    NSOperation* metricOperation = [self sendMetricForPayload:@{
      @"user_id" : teakUserId,
      @"platform_id" : teakNotifId,
      @"network_id" : @3
    }];
    [self.sessionFinishOperation addDependency:metricOperation];
  }
}

- (void)createThumbnailViewForItem:(AVPlayerItem*)item atTime:(CMTime)time {
  AVAsset* asset = item.asset;
  AVAssetImageGenerator* imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
  CGImageRef imageRef = [imageGenerator copyCGImageAtTime:time actualTime:NULL error:NULL];
  UIImage* thumbnail = [UIImage imageWithCGImage:imageRef];
  UIImageView* imageView = [[UIImageView alloc] initWithImage:thumbnail];
  float imageScaleRatio = self.view.frame.size.width / (thumbnail.size.width * thumbnail.scale);
  float scaledHeight = thumbnail.size.height * thumbnail.scale * imageScaleRatio;

  imageView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);
  [self.view insertSubview:imageView belowSubview:self.notificationContentView];
  CGImageRelease(imageRef); // CGImageRef won't be released by ARC
}

- (void)didReceiveNotification:(UNNotification*)notification {
  [self configureForNotification:notification];
  [self initURLSession];
  [self queueMetricSend];

  // Move this if more ops are added
  [self.operationQueue addOperation:self.sessionFinishOperation];

  BOOL startAssetIsImage = NO;
  NSMutableArray* buildingAssets = [[NSMutableArray alloc] init];
  NSUInteger contentIndex = [self.notificationUserData[@"content"] unsignedIntegerValue];
  for (NSUInteger i = contentIndex; i < [notification.request.content.attachments count]; i++) {
    UNNotificationAttachment* attachment = notification.request.content.attachments[i];

    // Bail if something has gone wrong with the attachments
    if (attachment == nil || attachment.URL == nil || ![attachment.URL startAccessingSecurityScopedResource]) return;

    // mp4 is video, assume everything else is an image of some type
    if ([[attachment.URL pathExtension] isEqualToString:@"mp4"]) {
      AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:attachment.URL options:nil];
      [attachment.URL stopAccessingSecurityScopedResource];
      [buildingAssets addObject:[AVPlayerItem playerItemWithAsset:asset]];
    } else { // It's an image
      NSData* attachmentData = [[NSData alloc] initWithContentsOfURL:attachment.URL];
      [attachment.URL stopAccessingSecurityScopedResource];
      UIImage* image = nil;
      if ([[attachment.URL pathExtension] isEqualToString:@"gif"]) {
        image = UIImage_animatedImageWithAnimatedGIFData(attachmentData);
      } else {
        image = [UIImage imageWithData:attachmentData];
      }
      [buildingAssets addObject:image];
      startAssetIsImage = YES;
    }
  }
  self.assets = buildingAssets;

  if (self.assets.count > 0) {
    float scaledHeight = 0.0f;
    if (startAssetIsImage) {
      UIImage* firstImage = [self.assets firstObject];
      float imageScaleRatio = self.view.frame.size.width / (firstImage.size.width * firstImage.scale);
      scaledHeight = firstImage.size.height * firstImage.scale * imageScaleRatio;

      self.notificationContentView = [[UIImageArrayView alloc] initWithImageArray:self.assets];
      self.notificationContentView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

      __weak typeof(self) weakSelf = self;
      self.prepareContentView = ^{
        __strong typeof(self) blockSelf = weakSelf;
        TeakAVPlayerView* playerView = [[TeakAVPlayerView alloc] init];
        playerView.frame = blockSelf.notificationContentView.frame;
        [blockSelf.view insertSubview:playerView aboveSubview:blockSelf.notificationContentView];
        blockSelf.notificationContentView = playerView;
      };
    } else {
      AVPlayerItem* firstPlayerItem = [self.assets firstObject];
      AVAssetTrack* track = [[firstPlayerItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
      CGSize trackSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
      float scaleRatio = self.view.frame.size.width / trackSize.width;
      scaledHeight = trackSize.height * scaleRatio;

      if (self.loopInitialContent) {
        AVQueuePlayer* videoPlayer = [AVQueuePlayer queuePlayerWithItems:@[ firstPlayerItem ]];
        self.videoPlayer = videoPlayer;
        self.playerLooper = [AVPlayerLooper playerLooperWithPlayer:videoPlayer
                                                      templateItem:firstPlayerItem];
      } else {
        self.videoPlayer = [AVPlayer playerWithPlayerItem:firstPlayerItem];
      }

      TeakAVPlayerView* playerView = [[TeakAVPlayerView alloc] init];
      playerView.player = self.videoPlayer;
      self.notificationContentView = playerView;

      __weak typeof(self) weakSelf = self;
      self.prepareContentView = ^{
        __strong typeof(self) blockSelf = weakSelf;
        [blockSelf createThumbnailViewForItem:blockSelf.videoPlayer.currentItem atTime:[blockSelf.videoPlayer currentTime]];
        [blockSelf.playerLooper disableLooping];
      };
    }

    /////

    self.notificationContentView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

    ///// Top level view

    self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y,
                                 self.view.frame.size.width, scaledHeight);
    self.preferredContentSize = CGSizeMake(self.view.frame.size.width, scaledHeight);
    [self.view addSubview:self.notificationContentView];

    ///// Button
    if (iOS12OrGreater()) {
      UIButton* defaultButton = [[UIButton alloc] init];
      [defaultButton setFrame:self.view.frame];
      [defaultButton setBackgroundColor:[UIColor clearColor]];
      [defaultButton addTarget:self action:@selector(buttonTouchUpInside:forEvent:) forControlEvents:UIControlEventTouchUpInside];
      [self.view insertSubview:defaultButton aboveSubview:self.notificationContentView];
    }

    // Start video if auto-play
    if (self.autoPlay) {
      [self.videoPlayer play];
    }
  }
}

- (void)didReceiveNotificationResponse:(UNNotificationResponse*)response
                     completionHandler:(void (^)(UNNotificationContentExtensionResponseOption))completionHandler {
  int attachmentIndex = NSNullOrNil(self.actions[response.actionIdentifier]) ? -1 : [self.actions[response.actionIdentifier] intValue];
  [self handleNotificationResponseForAction:attachmentIndex
                          completionHandler:^{
                            completionHandler(UNNotificationContentExtensionResponseOptionDismissAndForwardAction);
                          }];
}

- (void)handleNotificationResponseForAction:(int)attachmentIndex completionHandler:(void (^)(void))completionHandler {
  dispatch_once(&_inputHandlerDispatchOnce, ^{
    if (attachmentIndex < 0) {
      // Launch the app when the button is pressed
      completionHandler();
    } else {
      // Will prepare next content view
      self.prepareContentView();

      AVPlayerItem* assetToPlay = self.assets[attachmentIndex];
      AVPlayer* newPlayer = [AVPlayer playerWithPlayerItem:assetToPlay];
      [newPlayer play];
      TeakAVPlayerView* playerView = (TeakAVPlayerView*)self.notificationContentView;
      playerView.player = newPlayer;
      self.videoPlayer = newPlayer;
      // Start playing when button is pressed, launch app when the last asset finishes playing
      [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                        object:assetToPlay
                                                         queue:nil
                                                    usingBlock:^(NSNotification* notification) {
                                                      completionHandler();
                                                    }];
    }
  });
}

- (IBAction)buttonTouchUpInside:(id)sender forEvent:(UIEvent*)event {
  int attachmentIndex = [self.notificationUserData[@"defaultAction"] intValue];
  [self handleNotificationResponseForAction:attachmentIndex
                          completionHandler:^{
                            // To allow us to continue to build on Xcode 8 for CI builds
                            SEL selector = NSSelectorFromString(@"performNotificationDefaultAction");
                            ((void (*)(id, SEL))[[self extensionContext] methodForSelector:selector])([self extensionContext], selector);
                          }];
}

- (NSOperation*)sendMetricForPayload:(NSDictionary*)payload {
  NSString* urlString = [NSString stringWithFormat:@"https://parsnip.%@/notification_expanded", kTeakHostname];
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
  TeakAssignPayloadToRequest(@"POST", request, payload);

  NSOperation* metricOperation = [NSBlockOperation blockOperationWithBlock:^{}];
  NSURLSessionUploadTask* uploadTask =
      [self.session uploadTaskWithRequest:request
                                 fromData:nil
                        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                          [self.operationQueue addOperation:metricOperation];
                        }];
  [uploadTask resume];
  return metricOperation;
}

@end
