Then /^I background the app for (\d+) seconds$/ do |secs|
  secs = secs.to_f
  send_app_to_background(secs)
end

Then(/^I send a push notification that says "([^"]*)"$/) do |message|
puts message
  backdoor "integrationTestSchedulePush:", message
  sleep 2
end

Then /^I tap on the latest push notification$/ do
  # Background app so push shows up in notification center
  send_app_to_background(20)

  # Open notification center
  swipe(:down, { offset: { x: 350, y: -368 } }) # TODO: -368 gets us to y = 0 on iPhone 6 S

  # Wait for notification
  sleep 10

  # Tap top notification
  tap_point(350, 200)
end
