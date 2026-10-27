@contacts @US2
Feature: Verify contacts and surface identity changes
  As a DaChat user
  I want to verify contacts by safety code and be warned when an identity changes
  So that I am never silently talking to someone else

  Background:
    Given "Aisha" and "Ben" are connected

  @widget @FR-014 @FR-039 @US2-6
  Scenario: Comparing matching safety codes verifies the contact
    Given "Ben" is not verified for "Aisha"
    When "Aisha" opens "Ben"'s safety code
    Then the screen is protected from screenshots and app-switcher previews
    And she sees a 60-digit code in 12 groups of 5
    When she confirms the code matches what "Ben" sees
    Then "Ben" becomes verified for "Aisha"

  @integration @FR-014 @US2-6
  Scenario: Scanning the safety code in person verifies the contact
    Given "Ben" is not verified for "Aisha"
    When "Aisha" scans "Ben"'s safety-code QR in person
    Then "Ben" becomes verified for "Aisha"

  @unit @FR-014 @US2-6
  Scenario: A mismatched safety code leaves the contact not verified
    Given "Ben" is not verified for "Aisha"
    When "Aisha" scans a safety-code QR that does not match
    Then "Ben" stays not verified
    And "Aisha" sees what a mismatch could mean

  @unit @R10
  Scenario: Both people see the same safety code
    Then the safety code "Aisha" sees for "Ben" equals the code "Ben" sees for "Aisha"
    And the code changes if either person's post-quantum key changes

  @unit @FR-017
  Scenario: Trust persists until the identity changes
    Given "Ben" is verified for "Aisha"
    When "Aisha" restarts the app and exchanges more messages with "Ben"
    Then "Ben" is still verified for "Aisha"

  @widget @FR-015 @SC-006 @US2-7
  Scenario: A verified contact's identity change blocks messaging until acknowledged
    Given "Ben" is verified for "Aisha"
    When "Ben"'s identity changes
    Then "Aisha" sees a prominent warning in the conversation with "Ben"
    And she cannot send to "Ben" until she acknowledges the warning
    And "Ben" is not verified for "Aisha"
    When she acknowledges the warning
    Then she can send to "Ben" again
    And "Ben" stays not verified until she verifies again

  @unit @FR-015 @edge-queued
  Scenario: Queued messages are held until the warning is acknowledged
    Given "Ben" is verified for "Aisha"
    And "Aisha" has 2 messages to "Ben" waiting to be sent
    When "Ben"'s identity changes
    Then neither message is sent
    When "Aisha" acknowledges the warning
    Then both messages are sent to "Ben"'s new identity

  @widget @FR-016 @US2-8
  Scenario: A not-verified contact's identity change shows a visible notice
    Given "Ben" is not verified for "Aisha"
    When "Ben"'s identity changes
    Then "Aisha" sees a "safety code changed" notice in the conversation
    And she can keep messaging "Ben"

  @unit @R11
  Scenario Outline: What counts as an identity change
    Given "Ben" is "<trust>" for "Aisha"
    When "<event>"
    Then "Aisha" gets a "<result>"

    Examples:
      | trust        | event                                                                | result           |
      | verified     | the server returns a bundle for Ben with different identity keys     | blocking warning |
      | verified     | a message from Ben's address carries a different identity key        | blocking warning |
      | not verified | the server returns a bundle for Ben with a failing ML-DSA signature  | visible notice   |
      | verified     | Aisha confirms a new connection is Ben with a new identity           | blocking warning |
      | not verified | Aisha confirms a new connection is Ben with a new identity           | visible notice   |

  @unit @R11
  Scenario: A matching display name alone never links two identities
    Given "Aisha" has a contact named "Ben"
    When a new identity named "Ben" connects with "Aisha"
    Then it is added as a new, separate contact
    And "Aisha" is offered, but not required, to say it replaces her existing contact "Ben"
