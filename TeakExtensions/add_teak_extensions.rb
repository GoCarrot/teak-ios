#!/usr/bin/env ruby
require 'bundler/setup'
require 'fileutils'
require 'pathname'
require 'xcodeproj'

# Check if argument is empty
if ARGV.last.to_s.empty? then
  raise "Xcode Project required, eg: ruby #{__FILE__} foo/bar/Example/Example.xcodeproj"
end

# Check if argument is an Xcode project that exists (use File.exist? because it's a directory)
xcode_project_path = ARGV.last.chomp('/').chomp('\\')
if !xcode_project_path.end_with?(".xcodeproj") or !File.exist?(xcode_project_path) then
  raise "Argument should be Xcode Project"
end
xcode_project_path = File.expand_path(xcode_project_path)
xcode_project_name = File.basename(File.dirname(xcode_project_path))

# Configuration
symlink_instead_of_copy = false
bundle_id = ""

ARGV[0...-1].each do |arg|
  if arg == '--symlink-instead-of-copy' then
    symlink_instead_of_copy = true
  elsif arg =~ /--bundle-id=(.*)/ then
    bundle_id = $1
  end
end

puts "Adding Teak Notification Extensions to: #{xcode_project_path}"
xcode_proj = Xcodeproj::Project.open(xcode_project_path)

# List of Teak extensions
teak_extensions = [
  ["TeakNotificationService", ["MobileCoreServices", "UserNotifications"]],
  ["TeakNotificationContent", ["UserNotifications", "UserNotificationsUI", "AVFoundation", "UIKit"]]
]
teak_extensions.each do |service, deps|

  # Copy our files
  puts symlink_instead_of_copy ? "Creating symbolic links (--symlink-instead-of-copy)" : "Copying files..."
  target_path = File.join(File.dirname(xcode_project_path), service)
  FileUtils.mkdir_p(target_path)

  # Find or create PBXGroup
  product_group = xcode_proj[service] || xcode_proj.new_group(service, service)

  # Get or create target
  target = xcode_proj.native_targets.detect { |e| e.name == service} ||
    xcode_proj.new_target(:app_extension, service, :ios, nil, xcode_proj.products_group, :objc)

  # Add target dependencies
  deps.each do |framework|
    file_ref = xcode_proj.frameworks_group.new_reference("System/Library/Frameworks/#{framework}.framework")
    file_ref.name = "#{framework}.framework"
    file_ref.source_tree = 'SDKROOT'
    target.frameworks_build_phase.add_file_reference(file_ref, true)
  end

  # Add dependency on libTeak.a
  teak_framework_ref = xcode_proj.frameworks_group.new_reference("libTeak.a")
  teak_framework_ref.name = "libTeak.a"
  teak_framework_ref.source_tree = 'SOURCE_ROOT'
  target.frameworks_build_phase.add_file_reference(teak_framework_ref, true)

  Dir.glob(File.expand_path("#{service}/**/*", File.dirname(__FILE__))).map(&File.method(:realpath)).each do |file|
    target_file = File.join(target_path, File.basename(file))
    FileUtils.rm_f(target_file)

    puts "#{file} -> #{target_file}"
    if symlink_instead_of_copy then
      first = Pathname.new file
      second = Pathname.new File.dirname(target_file)
      FileUtils.ln_s(first.relative_path_from(second), target_file, :force => true)
    else
      FileUtils.cp(file, target_file)
    end

    # Find or add file
    file_ref = product_group[File.basename(file)] || product_group.new_reference(File.basename(file))

    # Add *.m files to build phase
    if File.extname(file) == ".m" then
      target.source_build_phase.add_file_reference(file_ref, true)
    end
  end

  # Add Resources build phase
  target.resources_build_phase

  # Assign build configurations
  target.build_configurations.each do |config|
    build_settings = xcode_proj.native_targets.detect { |e| e.name == xcode_project_name }.build_settings(config.name)
    next if not build_settings
    config.build_settings = {
      :CODE_SIGN_STYLE => "Automatic",
      :IPHONEOS_DEPLOYMENT_TARGET => 10.0,
      :CODE_SIGN_IDENTITY => build_settings['CODE_SIGN_IDENTITY'],
      :DEVELOPMENT_TEAM => build_settings['DEVELOPMENT_TEAM'],
      #"CODE_SIGN_IDENTITY[sdk=iphoneos*]" => "iPhone Developer", # Causes parse errors
      :LIBRARY_SEARCH_PATHS => [
          "$(SRCROOT)/Libraries/Teak/Plugins/iOS" # Unity path
      ],
      :INFOPLIST_FILE => "#{service}/Info.plist",
      :LD_RUNPATH_SEARCH_PATHS => "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
      :PRODUCT_BUNDLE_IDENTIFIER => "#{bundle_id}.#{service}",
      :PRODUCT_NAME => "$(TARGET_NAME)",
      :SKIP_INSTALL => :YES
    }
  end

  # Add to native targets
  xcode_proj.native_targets.each do |native_target|
    next if native_target.to_s != xcode_project_name

    puts "Adding #{target} as a dependency for #{native_target}"
    native_target.add_dependency(target)

    copy_phase = native_target.build_phases.detect { |e| e.respond_to?(:name) && e.name == "Embed Teak App Extensions" } || native_target.new_copy_files_build_phase("Embed Teak App Extensions")
    copy_phase.dst_subfolder_spec = '13'
    copy_phase.add_file_reference(target.product_reference, true)
  end
end

xcode_proj.save
