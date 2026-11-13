# Generates a throwaway app-hosted XCTest project around ProbeTests.swift.
# usage: bundle exec ruby generate_project.rb <dir containing Teak.framework (simulator)> <out dir>
require 'xcodeproj'
require 'fileutils'

fw_dir, out = ARGV.map { |p| File.expand_path(p) }
abort 'usage: generate_project.rb <framework dir> <out dir>' unless fw_dir && out
here = __dir__
FileUtils.mkdir_p(out)
proj = Xcodeproj::Project.new(File.join(out, 'Probe.xcodeproj'))
app = proj.new_target(:application, 'ProbeApp', :ios, '16.0')
test = proj.new_target(:unit_test_bundle, 'ProbeTests', :ios, '16.0')
test.add_dependency(app)
# ObjC/C-only observer, its own framework so `nm` can show it carries no Swift.
obs = proj.new_target(:framework, 'SK2Observer', :ios, '16.0')
test.add_dependency(obs)
g = proj.main_group
app.add_file_references([g.new_file(File.join(here, 'App/App.swift'))])
test.add_file_references([g.new_file(File.join(here, 'Tests/ProbeTests.swift'))])
obs_h = g.new_file(File.join(here, 'Observer/SK2Observer.h'))
obs.add_file_references([g.new_file(File.join(here, 'Observer/SK2Observer.m'))])
obs.headers_build_phase.add_file_reference(obs_h).settings = { 'ATTRIBUTES' => ['Public'] }
test.add_file_references([g.new_file(File.join(here, 'Tests/SK2ObserverTests.swift'))])
test.frameworks_build_phase.add_file_reference(obs.product_reference)
emb_obs = app.new_copy_files_build_phase('Embed SK2Observer')
emb_obs.symbol_dst_subfolder_spec = :frameworks
emb_obs.add_file_reference(obs.product_reference).settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
app.add_dependency(obs)
test.resources_build_phase.add_file_reference(g.new_file(File.join(here, 'Tests/Probe.storekit')))
fw = g.new_file(File.join(fw_dir, 'Teak.framework'))
[app, test].each { |t| t.frameworks_build_phase.add_file_reference(fw) }
emb = app.new_copy_files_build_phase('Embed Frameworks')
emb.symbol_dst_subfolder_spec = :frameworks
emb.add_file_reference(fw).settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
[app, test].each do |t|
  t.build_configurations.each do |c|
    s = c.build_settings
    s['PRODUCT_BUNDLE_IDENTIFIER'] = t == app ? 'io.teak.probe' : 'io.teak.probe.tests'
    s['SWIFT_VERSION'] = '5.0'
    s['GENERATE_INFOPLIST_FILE'] = 'YES'
    s['CODE_SIGNING_ALLOWED'] = 'NO'
    s['FRAMEWORK_SEARCH_PATHS'] = fw_dir
    s['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'
    s['SDKROOT'] = 'iphoneos'
  end
end
obs.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.teak.probe.sk2observer'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['DEFINES_MODULE'] = 'YES'
  s['CODE_SIGNING_ALLOWED'] = 'NO'
  s['CLANG_ENABLE_OBJC_ARC'] = 'YES'
  s['SDKROOT'] = 'iphoneos'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
end
# CONSUMABLE_HISTORY=1 merges SKIncludeConsumableInAppPurchaseHistory into the host app's Info.plist.
if ENV['CONSUMABLE_HISTORY'] == '1'
  app.build_configurations.each { |c| c.build_settings['INFOPLIST_FILE'] = File.join(here, 'App/ConsumableHistory.plist') }
end
test.build_configurations.each do |c|
  c.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/ProbeApp.app/ProbeApp'
  c.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end
proj.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(test)
scheme.save_as(File.join(out, 'Probe.xcodeproj'), 'Probe', true)
