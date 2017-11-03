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

ARGV[0...-1].each do |arg|
  if arg == '--symlink-instead-of-copy' then
    symlink_instead_of_copy = true
  end
end

puts "Adding Teak Notification Extensions to: #{xcode_project_path}"
xcode_proj = Xcodeproj::Project.open(xcode_project_path)

# List of Teak extensions
teak_extensions = ["TeakNotificationService"]
teak_extensions.each do |service|

  # Copy our files
  puts symlink_instead_of_copy ? "Creating symbolic links (--symlink-instead-of-copy)" : "Copying files..."
  target_path = File.join(File.dirname(xcode_project_path), service)
  FileUtils.mkdir_p(target_path)

  # Find or create PBXGroup
  product_group = xcode_proj[service] || xcode_proj.new_group(service, service)

  # Get or create target
  target = xcode_proj.native_targets.detect { |e| e.name == service} ||
    xcode_proj.new_target(:app_extension, service, :ios, nil, xcode_proj.products_group, :objc)

  Dir.glob(File.expand_path("#{service}/*", File.dirname(__FILE__))).map(&File.method(:realpath)).each do |file|
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
    if File.extname(file) == "m" then
      target.source_build_phase.add_file_reference(file_ref, true)
    end
  end

  # Add Resources build phase
  target.resources_build_phase

  # Get build settings for debug/release
  build_settings = {
    'Debug' => xcode_proj.native_targets.detect { |e| e.name == xcode_project_name }.build_settings('Debug'),
    'Release' => xcode_proj.native_targets.detect { |e| e.name == xcode_project_name }.build_settings('Release')
  }

  # Assign build configurations
  target.build_configurations.each do |config|
    config.build_settings = {
      :CODE_SIGN_IDENTITY => build_settings[config.name]['CODE_SIGN_IDENTITY'],
      :DEVELOPMENT_TEAM => build_settings[config.name]['DEVELOPMENT_TEAM'],
      :INFOPLIST_FILE => "#{service}/Info.plist",
      :LD_RUNPATH_SEARCH_PATHS => "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
      :PRODUCT_BUNDLE_IDENTIFIER => "#{build_settings[config.name]['PRODUCT_BUNDLE_IDENTIFIER']}.#{service}",
      :PRODUCT_NAME => "$(TARGET_NAME)",
      :SKIP_INSTALL => :YES
    }
  end

  # Add to native targets
  xcode_proj.native_targets.each do |native_target|
    next if native_target == target

    puts "Adding #{target} as a dependency for #{native_target}"
    native_target.add_dependency(target)

    copy_phase = native_target.build_phases.detect { |e| e.respond_to?(:name) && e.name == "Embed Teak App Extensions" } || native_target.new_copy_files_build_phase("Embed Teak App Extensions")
    copy_phase.dst_subfolder_spec = '13'
    copy_phase.add_file_reference(target.product_reference, true)
  end
end

xcode_proj.save
