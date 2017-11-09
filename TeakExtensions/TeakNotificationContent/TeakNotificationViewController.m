/* Teak -- Copyright (C) 2017 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "TeakNotificationViewController.h"
#import <AVKit/AVKit.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

@interface TeakNotificationViewController () <UNNotificationContentExtension>
@property (strong, nonatomic) AVPlayerLayer* playerLayer;
@property (strong, nonatomic) AVPlayer* player;
@property (strong, nonatomic) AVPlayerItem* lastPlayerItem;
@end

@implementation TeakNotificationViewController

- (void)viewDidLoad {
  [super viewDidLoad];
}

- (void)didReceiveNotification:(UNNotification*)notification {

  // -- Data Load
  NSArray* videoQueue = @[
    @"https://i.imgur.com/GrckkFr.mp4",
    @"https://i.imgur.com/oiS34rh.mp4"
  ];
  NSMutableArray* avItems = [[NSMutableArray alloc] init];
  for (NSString* videoUrl in videoQueue) {
    NSURL* url = [NSURL URLWithString:videoUrl];
    AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:url options:nil];
    AVPlayerItem* item = [[AVPlayerItem alloc] initWithAsset:asset];
    [avItems addObject:item];
  }
  self.lastPlayerItem = [avItems lastObject];
  // -- stopAccessingSecurityScopedResource

  AVAssetTrack* track = [[self.lastPlayerItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
  CGSize trackSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
  float scaleRatio = self.view.frame.size.width / trackSize.width;
  float scaledHeight = trackSize.height * scaleRatio;

  AVQueuePlayer* queuePlayer = [AVQueuePlayer queuePlayerWithItems:avItems];
  if ((NO)) { // If loop animation
    self.player = [AVPlayerLooper playerLooperWithPlayer:queuePlayer
                                            templateItem:self.lastPlayerItem];
  } else {
    self.player = queuePlayer;
  }

  self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
  self.playerLayer.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);
  [self.view.layer addSublayer:self.playerLayer];

  self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y,
                               self.view.frame.size.width, scaledHeight);
  self.view.layer.frame = self.view.frame;
  self.view.layer.bounds = self.view.frame;

  // If Autoplay
  if ((NO)) {
    [self.player play];
  }
  /*
  // The first object of the attachments array will be displayed as the "preview" in the small view,
  // we can use any subsequent attachments differently
  UNNotificationAttachment* attachment = [notification.request.content.attachments lastObject];
  if(attachment != nil && attachment.URL != nil && [attachment.URL startAccessingSecurityScopedResource]) {
    NSData* attachmentData = [[NSData alloc] initWithContentsOfURL:attachment.URL];
    UIImage* image = [UIImage imageWithData:attachmentData];
    [attachment.URL stopAccessingSecurityScopedResource];

    float imageScaleRatio =  self.view.frame.size.width / (image.size.width * image.scale);
    float scaledHeight = image.size.height * image.scale * imageScaleRatio;

    UIImageView* imageView = [[UIImageView alloc] init];
    imageView.image = image;
    imageView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

    self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y,
      self.view.frame.size.width, scaledHeight); // TODO: Add size of text box(es)
    [self.view addSubview:imageView];
  }*/
}

- (void)didReceiveNotificationResponse:(UNNotificationResponse*)response
                     completionHandler:(void (^)(UNNotificationContentExtensionResponseOption option))completionHandler {
  [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                    object:self.lastPlayerItem
                                                     queue:nil
                                                usingBlock:^(NSNotification* notification) {
                                                  [[NSNotificationCenter defaultCenter] removeObserver:self];
                                                  completionHandler(UNNotificationContentExtensionResponseOptionDismissAndForwardAction);
                                                }];

  [self.player play];
}

@end
