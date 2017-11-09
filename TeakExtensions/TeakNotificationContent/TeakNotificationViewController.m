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

@interface TeakNotificationViewController () <UNNotificationContentExtension>

// Video related
@property (strong, nonatomic) AVPlayer* player;
@property (strong, nonatomic) AVPlayerItem* playerItem;

// Image related
@property (strong, nonatomic) UIImage* image;

// Common parent view for whatever is in the notification.
@property (strong, nonatomic) UIView* notificationContentView;
@end

@implementation TeakNotificationViewController

- (void)viewDidLoad {
  [super viewDidLoad];
}

- (void)didReceiveNotification:(UNNotification*)notification {
  // The first object of the attachments array will be displayed as the "preview" in the small view,
  // we can use any subsequent attachments differently
  UNNotificationAttachment* attachment = [notification.request.content.attachments lastObject];
  if (attachment == nil || attachment.URL == nil || ![attachment.URL startAccessingSecurityScopedResource]) return;

  if ([[attachment.URL pathExtension] isEqualToString:@"mp4"]) {
    AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:attachment.URL options:nil];
    [attachment.URL stopAccessingSecurityScopedResource];

    self.playerItem = [[AVPlayerItem alloc] initWithAsset:asset];
  } else { // if image type
    NSData* attachmentData = [[NSData alloc] initWithContentsOfURL:attachment.URL];
    [attachment.URL stopAccessingSecurityScopedResource];

    self.image = [UIImage imageWithData:attachmentData];
  }

  float scaledHeight = 0.0f;
  if (self.playerItem != nil) {
    AVAssetTrack* track = [[self.playerItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    CGSize trackSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
    float scaleRatio = self.view.frame.size.width / trackSize.width;
    scaledHeight = trackSize.height * scaleRatio;

    AVQueuePlayer* queuePlayer = [AVQueuePlayer queuePlayerWithItems:@[ self.playerItem ]];
    self.player = (AVPlayer*)queuePlayer;
    if ((NO)) { // If loop animation
      self.player = (AVPlayer*)[AVPlayerLooper playerLooperWithPlayer:queuePlayer
                                                         templateItem:self.playerItem];
    }

    TeakAVPlayerView* playerView = [[TeakAVPlayerView alloc] init];
    playerView.player = self.player;
    self.notificationContentView = playerView;
  } else if (self.image != nil) {
    float imageScaleRatio = self.view.frame.size.width / (self.image.size.width * self.image.scale);
    scaledHeight = self.image.size.height * self.image.scale * imageScaleRatio;

    UIImageView* imageView = [[UIImageView alloc] init];
    imageView.image = self.image;
    imageView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

    self.notificationContentView = imageView;
  }

  /////

  self.notificationContentView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

  self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y,
                               self.view.frame.size.width, scaledHeight);
  self.preferredContentSize = CGSizeMake(self.view.frame.size.width, scaledHeight);
  [self.view addSubview:self.notificationContentView];

  // If Autoplay
  if ((NO)) {
    [self.player play];
  }
}

- (void)didReceiveNotificationResponse:(UNNotificationResponse*)response
                     completionHandler:(void (^)(UNNotificationContentExtensionResponseOption option))completionHandler {
  [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                    object:self.playerItem
                                                     queue:nil
                                                usingBlock:^(NSNotification* notification) {
                                                  [[NSNotificationCenter defaultCenter] removeObserver:self];
                                                  completionHandler(UNNotificationContentExtensionResponseOptionDismissAndForwardAction);
                                                }];

  [self.player play];
}

@end
