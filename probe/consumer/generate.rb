#!/usr/bin/env ruby
# Generates Consumer.xcodeproj: an app + notification service extension linking
# prebuilt Teak / TeakExtension xcframeworks (dynamic, embedded).
#   generate.rb <frameworks_dir> <out_dir> <scene|legacy>
require 'bundler/setup'
require 'xcodeproj'
require 'fileutils'

fw_dir, out_dir, mode = ARGV
abort 'usage: generate.rb <frameworks_dir> <out_dir> <scene|legacy>' unless fw_dir && out_dir && %w[scene legacy].include?(mode)
fw_dir = File.expand_path(fw_dir)
FileUtils.rm_rf(out_dir)
FileUtils.mkdir_p(out_dir)
src = File.expand_path('src', __dir__)
FileUtils.cp_r(Dir["#{src}/*"], out_dir)
Dir.chdir(out_dir)

app_plist = {
  'CFBundleDevelopmentRegion' => 'en', 'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
  'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion' => '6.0',
  'CFBundleName' => '$(PRODUCT_NAME)', 'CFBundlePackageType' => 'APPL',
  'CFBundleShortVersionString' => '1.0', 'CFBundleVersion' => '1', 'LSRequiresIPhoneOS' => true,
  'UIBackgroundModes' => ['remote-notification'], 'UILaunchScreen' => {},
  'CFBundleURLTypes' => [{ 'CFBundleTypeRole' => 'Editor', 'CFBundleURLSchemes' => ['teak613659812345256'] }]
}
if mode == 'scene'
  app_plist['UIApplicationSceneManifest'] = {
    'UIApplicationSupportsMultipleScenes' => false,
    'UISceneConfigurations' => { 'UIWindowSceneSessionRoleApplication' => [
      { 'UISceneConfigurationName' => 'Default', 'UISceneDelegateClassName' => 'SceneDelegate' }
    ] }
  }
end
nse_plist = {
  'CFBundleDevelopmentRegion' => 'en', 'CFBundleExecutable' => '$(EXECUTABLE_NAME)',
  'CFBundleIdentifier' => '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion' => '6.0',
  'CFBundleName' => '$(PRODUCT_NAME)', 'CFBundlePackageType' => 'XPC!',
  'CFBundleShortVersionString' => '1.0', 'CFBundleVersion' => '1',
  'NSExtension' => { 'NSExtensionPointIdentifier' => 'com.apple.usernotifications.service',
                     'NSExtensionPrincipalClass' => 'NotificationService' }
}
Xcodeproj::Plist.write_to_path(app_plist, 'App-Info.plist')
Xcodeproj::Plist.write_to_path(nse_plist, 'NSE-Info.plist')

project = Xcodeproj::Project.new('Consumer.xcodeproj')
app = project.new_target(:application, 'Consumer', :ios, '15.0')
nse = project.new_target(:app_extension, 'ConsumerNSE', :ios, '15.0')

common = {
  'CODE_SIGNING_ALLOWED' => 'NO', 'CODE_SIGN_IDENTITY' => '', 'CLANG_ENABLE_OBJC_ARC' => 'YES',
  'TARGETED_DEVICE_FAMILY' => '1,2', 'FRAMEWORK_SEARCH_PATHS' => ['$(inherited)'], 'SWIFT_VERSION' => '5.0'
}
app.build_configurations.each do |c|
  c.build_settings.merge!(common)
  c.build_settings['INFOPLIST_FILE'] = 'App-Info.plist'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.teak.probe.consumer'
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'App.entitlements'
  c.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
end
nse.build_configurations.each do |c|
  c.build_settings.merge!(common)
  c.build_settings['INFOPLIST_FILE'] = 'NSE-Info.plist'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.teak.probe.consumer.nse'
  c.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

group = project.main_group
app_files = %w[main.m AppDelegate.m SceneDelegate.m].map { |f| group.new_file(f) }
%w[AppDelegate.h SceneDelegate.h NotificationService.h].each { |f| group.new_file(f) }
app.add_file_references(app_files)
nse.add_file_references([group.new_file('NotificationService.m')])

fw_group = project.frameworks_group
teak = fw_group.new_file(File.join(fw_dir, 'Teak.xcframework'))
teak_ext = fw_group.new_file(File.join(fw_dir, 'TeakExtension.xcframework'))

app.frameworks_build_phase.add_file_reference(teak)
nse.frameworks_build_phase.add_file_reference(teak_ext)
%w[AdSupport AVFoundation ImageIO CoreServices StoreKit UserNotifications CoreGraphics UIKit SystemConfiguration].each do |f|
  app.add_system_framework(f)
end
%w[ImageIO CoreGraphics UserNotifications].each { |f| nse.add_system_framework(f) }

embed = app.new_copy_files_build_phase('Embed Frameworks')
embed.symbol_dst_subfolder_spec = :frameworks
[teak, teak_ext].each { |f| embed.add_file_reference(f).settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] } }

embed_ext = app.new_copy_files_build_phase('Embed App Extensions')
embed_ext.symbol_dst_subfolder_spec = :plug_ins
embed_ext.add_file_reference(nse.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.add_dependency(nse)

project.save
Xcodeproj::XCScheme.share_scheme(project.path, 'Consumer') rescue nil
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'Consumer', true)
puts "generated #{out_dir}/Consumer.xcodeproj (#{mode})"
