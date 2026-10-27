@connections @US2
Feature: Connect remotely with a single-use link
  As a DaChat user who can't meet someone in person
  I want to send a single-use, expiring, revocable link
  So that we can connect, optionally confirming identity with a code word

  Background:
    Given "Aisha" and "Ben" each have a registered identity

  @widget @FR-011 @US2-1
  Scenario: Without a saved default, the creator must choose about ID confirmation
    Given "Aisha" has no saved default for ID confirmation
    When she starts creating a link
    Then no link is generated until she explicitly chooses "Require ID confirmation" yes or no

  @unit @FR-011 @R1.7a
  Scenario: Out-of-the-box connection defaults
    Given "Aisha" has never changed her connection preferences
    Then QR is suggested first
    And link ID confirmation is off by default
    And the confirmation type is code word

  @widget @FR-011
  Scenario: A saved default skips the yes/no question
    Given "Aisha" saved "always require ID confirmation" as her default
    When she starts creating a link
    Then she is asked only for the code word

  @widget @FR-009 @US2-2
  Scenario: The creator sees the link's rules and can revoke it
    When "Aisha" creates a link without ID confirmation
    Then she sees that it can be used once
    And she sees that it expires 24 hours after creation
    And she can revoke it

  @integration @FR-009 @FR-013 @US2-3
  Scenario: Redeeming a link connects as not verified
    Given "Aisha" created a link without ID confirmation
    When "Ben" opens the link and taps "Confirm"
    Then "Aisha" and "Ben" are connected
    And each sees the other's display name
    And each sees the other as not verified

  @widget @FR-009
  Scenario: Nothing happens until the recipient taps to confirm
    Given "Aisha" created a link
    When "Ben" opens the link but does not tap "Confirm"
    Then no connection is made
    And the link is still usable

  @integration @FR-010 @SC-005 @US2-4
  Scenario Outline: Used, expired, and revoked links are refused
    Given "Aisha" created a link
    And the link is "<state>"
    When "Ben" opens the link and taps "Confirm"
    Then no connection is made
    And "Ben" sees "<explanation>"

    Examples:
      | state                     | explanation                                  |
      | already used by "Chen"    | This link has already been used              |
      | older than 24 hours       | This link has expired                         |
      | revoked by "Aisha"        | This link was cancelled by the person who made it |

  @integration @SC-005 @edge-concurrent
  Scenario: Two people redeem the same link at once
    Given "Aisha" created a link
    When "Ben" and "Chen" confirm the link at the same moment
    Then exactly one of them is connected to "Aisha"
    And the other sees "This link has already been used"

  @integration @FR-012 @US2-5
  Scenario: The correct code word connects as verified
    Given "Aisha" created a link requiring the code word "harbour"
    When "Ben" opens the link, taps "Confirm", and enters "harbour"
    Then "Aisha" and "Ben" are connected as verified

  @integration @FR-012 @US2-5
  Scenario: Three wrong code words consume the link and connect nobody
    Given "Aisha" created a link requiring the code word "harbour"
    When "Ben" enters "harbor", "habour", and "harbours"
    Then no connection is made
    And the link can never be used again
    And "Ben" sees that the link is no longer valid

  @unit @R9
  Scenario: The code word is never sent to the server
    Given "Aisha" created a link requiring the code word "harbour"
    When "Ben" enters "harbour"
    Then no request to the main server contains "harbour"

  @unit @edge-own-link
  Scenario: Opening my own link is refused
    When "Aisha" opens her own link
    Then no connection is made
    And she sees that this is her own link

  @integration @edge-no-app
  Scenario: A link opened without the app installed guides installation
    Given "Ben" does not have DaChat installed
    When "Ben" opens "Aisha"'s link in a browser
    Then he sees how to install DaChat
    And the link stays valid until it expires
    And the server never receives the part of the link after "#"
