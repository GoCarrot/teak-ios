source "https://rubygems.org"

gem 'xcpretty'
gem 'xcodeproj'
gem 'plist'
gem 'fastlane'
gem 'rubocop'
gem 'cocoapods'
gem 'jazzy'

# In CI sqlite3 1.7.x is failing to install saying it is incompatible
# with ruby 2.7.8. sqlite3 for ruby claims it needs ruby 2.7+, but the
# platform specific build is claiming 3+. I am not certain why we are
# getting the general version in our Gemfile.lock, but CI is installing
# the platform specific version.
gem 'sqlite3', '~> 1.6.0'
