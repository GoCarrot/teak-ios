require 'json'

def get_teak_run_history
  stdin, stdout, stderr = Open3.popen3('teak log parse')
  stdin.puts($log_data[:out])
  stdin.close
  JSON.parse(stdout.gets)
end

Then(/^the Teak state should be "([^"]*?)"$/) do |state|
  current_state = get_teak_run_history['sdk']['state']
  fail "Current state is #{current_state}." unless current_state == state
end

Then(/^the Teak Session state should be "([^"]*?)"$/) do |state|
  current_state = get_teak_run_history['session']['state']
  fail "Current state is #{current_state}." unless current_state == state
end

Then(/^the Teak Session state should have transitioned from "([^"]*?)"$/) do |state|
  other_state = get_teak_run_history['session']['old_state']
  fail "Current state transitioned from #{other_state}." unless other_state == state
end

Then(/^I wait for the Teak Session state to be "([^"]*?)"$/) do |state|
  wait_for() do
    get_teak_run_history['session']['state'] == state
  end
end

Given(/^the Teak Session timeout is (\d+) seconds$/) do |value|
  backdoor "integrationTestTimeout:", value.to_s
end
