#!/usr/bin/env ruby
require 'bundler/setup'
require 'xcodeproj'
require 'yaml'

expected = YAML.load_file('MIN_VERSIONS.yml').fetch('min-ios')
project = Xcodeproj::Project.open('Teak.xcodeproj')

project.targets.each do |target|
  target.build_configurations.each do |config|
    next unless config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
    raise "Wrong deployment target version (#{config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']}), expected #{expected}" unless config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] == expected
  end
end
