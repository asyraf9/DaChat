@messaging @US1
Feature: End-to-end-protected one-to-one messaging
  As a connected DaChat user
  I want to exchange text messages the server cannot read, with accurate delivery states
  So that my conversations are private and I know what happened to each message

  Background:
    Given "Aisha" and "Ben" are connected as verified contacts

  @integration @FR-018 @SC-002 @US1-5
  Scenario: Message content is never readable by the server
    When "Aisha" sends "meet at the library" to "Ben"
    Then "Ben" sees "meet at the library"
    And an inspection of everything the main server stores and relays finds no "meet at the library"
    And it finds no display names and no real-world identifiers
    And the contact backups appear only as opaque blobs

  @integration @FR-019 @SC-003 @SC-004
  Scenario: Delivery to an online recipient
    Given "Ben" is online
    When "Aisha" sends "hi" to "Ben"
    Then "Ben" sees "hi" within 3 seconds
    And "Aisha" sees the message as "delivered"

  @integration @FR-019 @FR-021 @SC-003 @US1-6
  Scenario: Delivery to an offline recipient
    Given "Ben" is offline
    When "Aisha" sends "one", "two", and "three" to "Ben"
    Then "Aisha" sees each message as "sent"
    When "Ben" reconnects
    Then "Ben" sees "one", "two", "three" in that order within 30 seconds
    And "Aisha" sees each message as "delivered"
    And the main server no longer holds those messages

  @unit @FR-020 @US1-7
  Scenario: Messages composed offline are queued and sent automatically
    Given "Aisha" has no connectivity
    When "Aisha" sends "later" to "Ben"
    Then "Aisha" sees the message as "pending"
    When connectivity returns
    Then the message is sent without any action from "Aisha"
    And "Aisha" sees the message as "sent"

  @unit @FR-020
  Scenario: Pending messages survive an app restart
    Given "Aisha" has a "pending" message to "Ben"
    When the app is closed and reopened
    Then the message is still "pending"
    And it is sent when connectivity returns

  @unit @FR-019 @US1-8
  Scenario: A message that keeps failing shows "failed" with retry
    Given the server refuses "Aisha"'s message to "Ben" on every attempt
    When the retries are exhausted
    Then "Aisha" sees the message as "failed"
    When she taps "Retry"
    Then the message becomes "pending" again

  @unit @SC-004
  Scenario Outline: Delivery state only moves forward through real events
    Given an outgoing message in state "<from>"
    When "<event>" happens
    Then the message state is "<to>"

    Examples:
      | from      | event                   | to        |
      | pending   | server acknowledgement  | sent      |
      | sent      | delivery receipt        | delivered |
      | delivered | server acknowledgement  | delivered |
      | sent      | 24 hours without receipt| sent      |
      | pending   | retries exhausted       | failed    |
      | failed    | user retry              | pending   |

  @unit @FR-018
  Scenario Outline: Message length limits
    When "Aisha" composes a message of <length> characters
    Then sending is "<result>"

    Examples:
      | length | result    |
      | 0      | disabled  |
      | 1      | enabled   |
      | 4096   | enabled   |
      | 4097   | disabled  |

  @unit @FR-022
  Scenario: History is stored only on the device, encrypted, and excluded from backups
    When "Aisha" and "Ben" exchange messages
    Then the history is stored only in the encrypted store on each device
    And the encrypted stores are excluded from operating-system cloud and device backups

  @unit @edge-storage-full
  Scenario: An incoming message that cannot be stored is not acknowledged
    Given "Ben"'s device storage is full
    When "Aisha" sends "hello" to "Ben"
    Then "Ben"'s device sends no delivery receipt
    And "Ben" is told a message could not be saved
    And "Aisha" does not see the message as "delivered"

  @unit @R8
  Scenario: Messages resume after the other person restores their identity
    Given "Ben" restored his identity on a new device
    When "Aisha" sends "welcome back" to "Ben"
    Then "Ben" sees "welcome back"
    And "Aisha" saw no identity-change warning
