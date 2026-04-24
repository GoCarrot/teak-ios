Pod::Spec.new do |spec|
  spec.name         = "Teak"
  spec.version      = "4.3.11"
  spec.summary      = "Teak provides rewarded push notifications, emails, and links for free to play games."
  spec.homepage     = "https://teak.io"
  spec.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE" }
  spec.author       = { "Alex Scarborough" => "alex@teak.io" }

  spec.source       = { :git => "https://github.com/GoCarrot/teak-ios.git", :tag => spec.version.to_s }
  spec.platform     = :ios, "11.0"

  # Mirrors the "Define Version" Xcode build phase from Teak.xcodeproj.
  # Regenerated on each `pod install`. Output is gitignored.
  spec.prepare_command = <<-CMD
    version=$(git describe --tags 2>/dev/null || echo "#{spec.version}")
    echo "#define TEAK_SDK_VERSION \\"$version\\"" > Teak/TeakVersion.h
  CMD

  spec.default_subspec = 'Core'

  spec.subspec 'Core' do |core|
    core.source_files         = 'Teak/**/*.{h,m,c}'
    core.exclude_files        = 'Teak/Extensions/**/*'
    # Public surface = the Teak.h umbrella set. Everything else (Core/, Configuration/,
    # Events/, Store/, *+Internal.h, helpers, libtommath) is internal.
    core.public_header_files  = 'Teak/Teak.h',
                                'Teak/TeakLink.h',
                                'Teak/TeakNotification.h',
                                'Teak/TeakOperation.h',
                                'Teak/TeakReward.h',
                                'Teak/TeakSceneHooks.h',
                                'Teak/TeakUserConfiguration.h'
    core.private_header_files = 'Teak/3rdParty/**/*.h'
    core.resource_bundles     = { 'Teak' => ['Teak/PrivacyInfo.xcprivacy'] }
    core.frameworks           = 'AdSupport', 'AVFoundation', 'ImageIO', 'CoreServices',
                                'StoreKit', 'UserNotifications', 'CoreGraphics', 'UIKit',
                                'SystemConfiguration'
    core.pod_target_xcconfig  = {
      'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Teak/3rdParty/libtommath"'
    }
  end

  spec.subspec 'Extension' do |ext|
    # Extension code references TeakHealthCheck (HTTP health probe) and the
    # animated-GIF decoder via extern. Pull both in so the slim NSE/NCE binary
    # can link standalone.
    ext.source_files         = 'Teak/Extensions/**/*.{h,m}',
                               'Teak/TeakHelpers.{h,m}',
                               'Teak/TeakHealthCheck.m',
                               'Teak/3rdParty/UIImage+animatedGIF.m'
    ext.public_header_files  = 'Teak/Extensions/TeakNotificationServiceCore.h',
                               'Teak/Extensions/TeakNotificationViewControllerCore.h',
                               'Teak/TeakHelpers.h'
    ext.resource_bundles     = { 'TeakExtension' => ['Teak/Extensions/PrivacyInfo.xcprivacy'] }
    ext.frameworks           = 'ImageIO', 'CoreGraphics', 'UserNotifications'
  end
end
