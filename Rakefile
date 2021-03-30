# frozen_string_literal: true

require 'rake/clean'

CLEAN.include '**/.DS_Store'

task :clean do
  xcode_artifacts = File.expand_path('~/Library/Developer/Xcode/')

  ['Sample', 'Automated', 'Teak'].each do |project|
    FileUtils.rm_rf Dir[File.join(xcode_artifacts, 'DerivedData', "#{project}-*")]
  end

  # Remove empty directories
  Dir[File.join(xcode_artifacts, '**', '*')].select { |d| File.directory? d }
                                            .select { |d| (Dir.entries(d) - %w[. ..]).empty? }
                                            .each   { |d| Dir.rmdir d }
end

task :docs do
  # https://github.com/realm/jazzy
  sh "jazzy \
    --objc \
    --clean \
    --theme jony \
    --author Teak.io, Inc. \
    --author_url https://teak.io \
    --module-version `cat VERSION` \
    --readme VERSION \
    --build-tool-arguments --objc,Teak/Teak.h,--,-x,objective-c,-isysroot,$(xcrun --show-sdk-path),-I,$(pwd) \
    --module Teak \
    --output docs/appledoc/objc_output"
end
