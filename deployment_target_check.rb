#!/usr/bin/env ruby
require 'bundler/setup'
require 'xcodeproj'
project = Xcodeproj::Project.open('Teak.xcodeproj')

project.targets.each do |target|
  target.build_configurations.each do |config|
    next unless config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
    raise "Wrong deployment target version (#{config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']})" unless config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] == '9.0'
  end
end
