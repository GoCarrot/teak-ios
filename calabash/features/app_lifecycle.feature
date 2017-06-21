Feature: App Lifecycle

  @dev
  Scenario: QuickTesting
    Given the app has launched
      Then I send a push notification that says "Calabash Test"
      When I tap on the latest push notification
      And I wait for the Teak Session state to be "UserIdentified"
      Then the current Teak session attribution should have "teak_notif_id"

  Scenario: Teak Session expiration
    Given the app has launched
      Then I wait for the Teak Session state to be "UserIdentified"
    When I background the app for 3 seconds
      And I wait for 1 second
      Then the Teak Session state should be "Expiring"
    And I wait for 5 seconds
      Then I wait for the Teak Session state to be "UserIdentified"
      And the Teak Session state should have transitioned from "Expiring"
    Given the Teak Session timeout is 5 seconds
      When I background the app for 5 seconds
      And I wait for 5 second
      Then I wait for the Teak Session state to be "UserIdentified"
      And the Teak Session state should have transitioned from "IdentifyingUser"