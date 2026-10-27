@messaging @US1
Feature: Content-free notifications
  As a DaChat user
  I want to be told about new messages without the content being exposed
  So that my lock screen and notification shade don't leak what people say

  @unit @FR-023
  Scenario: A notification shows the sender's display name but never the content
    Given "Aisha" is connected with "Ben"
    When "Ben" sends "the password is tulip" to "Aisha"
    Then "Aisha" gets a notification "New message from Ben"
    And no notification contains "the password is tulip"

  @unit @FR-023 @platform-android
  Scenario: The lock-screen version hides the sender too
    Given the platform is Android and the screen is locked
    When "Aisha" gets a notification
    Then the lock screen shows only "New message"

  @unit @FR-024 @platform-ios
  Scenario: iOS background pushes carry no sender or content
    Given the platform is iOS and DaChat is in the background
    When "Ben" sends "Aisha" a message
    Then the push "Aisha" receives says only "New activity in DaChat"
    And the push payload contains no sender, display name, or message content

  @unit @FR-034
  Scenario: No notification for a blocked contact
    Given "Aisha" has blocked "Ben"
    When "Ben" sends "Aisha" a message
    Then "Aisha" gets no notification

  @widget @platform-android @R15
  Scenario: The Android background connection can be turned off
    Given the platform is Android
    When "Aisha" turns off "Stay connected in the background" in settings
    Then the ongoing connection notification disappears
    And she is told new messages arrive only while DaChat is open
