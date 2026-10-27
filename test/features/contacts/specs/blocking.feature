@contacts @US4
Feature: Block and unblock a contact
  As a DaChat user
  I want to block a contact so they can't reach me
  So that I can cut contact without them being told and without affecting anyone else

  Background:
    Given "Aisha" is connected with "Ben" and "Chen"

  @integration @FR-034 @SC-010 @US4-1
  Scenario: Messages from a blocked contact are never shown or notified
    When "Aisha" blocks "Ben"
    And "Ben" sends "Aisha" a message
    Then the message does not appear on "Aisha"'s device
    And "Aisha" receives no notification
    And no readable copy of the message is stored on "Aisha"'s device

  @unit @FR-034 @edge-mid-delivery
  Scenario: A blocked contact's message that still reaches the device is discarded before decryption
    Given "Aisha" has blocked "Ben"
    When a message from "Ben" reaches "Aisha"'s device
    Then it is discarded before it is decrypted
    And no delivery receipt is sent

  @widget @FR-035 @US4-2
  Scenario: A blocked conversation stays readable but cannot send
    Given "Aisha" has messages with "Ben"
    When "Aisha" blocks "Ben"
    And she opens the conversation with "Ben"
    Then the existing messages are still readable
    And sending is disabled
    And she sees an option to unblock "Ben"

  @integration @FR-036 @US4-3
  Scenario: The blocked person is not told
    Given "Aisha" has blocked "Ben"
    When "Ben" sends "Aisha" a message
    Then "Ben" sees the message as sent but never delivered
    And "Ben" sees no indication of being blocked

  @integration @FR-034 @US4-3
  Scenario Outline: A blocked contact cannot re-connect
    Given "Aisha" has blocked "Ben"
    When "Ben" tries to connect with "Aisha" by "<method>"
    Then nothing reaches "Aisha"
    And "Ben" sees no indication of being blocked

    Examples:
      | method                  |
      | redeeming a new link    |
      | a QR code scan          |

  @integration @FR-037 @US4-4
  Scenario: Unblocking restores new messages only
    Given "Aisha" blocked "Ben"
    And "Ben" sent "while blocked" during the block
    When "Aisha" unblocks "Ben"
    And "Ben" sends "after unblock"
    Then "Aisha" receives "after unblock"
    And "Aisha" never receives "while blocked"
    And they did not need to re-connect

  @integration @FR-038 @SC-010 @US4-5
  Scenario: Blocking one contact never affects another
    When "Aisha" blocks "Ben"
    Then "Aisha" and "Chen" can still exchange messages
    And "Chen"'s trust state and delivery states are unchanged
    When "Aisha" unblocks "Ben"
    Then nothing changes for "Chen"

  @widget @FR-033 @US4-6
  Scenario: The blocked list shows and unblocks every blocked contact
    Given "Aisha" has blocked "Ben" and "Chen"
    When she opens the blocked list in settings
    Then she sees "Ben" and "Chen"
    And she can unblock each of them

  @unit @FR-045
  Scenario: Block changes are included in the contact backup
    When "Aisha" blocks "Ben"
    Then a contact backup update is scheduled
    And the next backup records "Ben" as blocked
