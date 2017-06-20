Then /^I background the app for (\d+) seconds$/ do |secs|
  secs = secs.to_f
  send_app_to_background(secs)
end
