@connections @US1
Feature: Connect in person by mutual QR scan
  As two people who are together
  We want to scan each other's QR codes
  So that we are connected as verified contacts

  Background:
    Given "Aisha" and "Ben" each have a registered identity
    And they are in the same place

  @integration @FR-008 @US1-4 @SC-007
  Scenario: Mutual QR scan creates verified contacts on both sides
    When "Aisha" scans "Ben"'s QR code
    And "Ben" scans "Aisha"'s QR code
    Then "Aisha" sees "Ben" as a verified contact
    And "Ben" sees "Aisha" as a verified contact
    And each sees the other's display name
    And the main server never received either display name in readable form

  @unit @R9
  Scenario: A one-sided scan asks the other person to scan too
    When "Aisha" scans "Ben"'s QR code
    And "Ben" has not scanned "Aisha"'s QR code
    Then "Aisha" is asked to have "Ben" scan her code too
    And no verified contact exists yet on either side

  @widget @FR-039
  Scenario: The QR screens are protected
    When "Aisha" opens her QR code
    Then the screen is protected from screenshots and app-switcher previews

  @unit @edge-own-code
  Scenario: Scanning my own QR code is refused
    When "Aisha" scans her own QR code
    Then no connection is made
    And she sees that she scanned her own code

  @unit @edge-expired-qr
  Scenario: An expired QR code is refused
    Given "Ben"'s QR code was generated more than 10 minutes ago
    When "Aisha" scans it
    Then no connection is made
    And she sees that "Ben" needs to refresh his code

  @unit @edge-already-connected
  Scenario: Connecting again with an existing contact does not duplicate them
    Given "Aisha" and "Ben" are already connected
    When they scan each other's QR codes again
    Then "Aisha" still has exactly one contact for "Ben"
    And she is told they are already connected

  @unit @R9 @US2
  Scenario: A prekey bundle that doesn't match the scanned identity is rejected
    Given "Aisha" scanned "Ben"'s QR code
    When the server returns a bundle for "Ben" with a different identity
    Then the bundle is not used
    And no session with that identity is created

  @unit @edge-prekeys-exhausted
  Scenario: Messaging still starts when one-time prekeys are exhausted
    Given "Ben" has no one-time prekeys left on the server
    When "Aisha" and "Ben" connect by QR
    Then the connection succeeds
    And "Ben"'s device replenishes its one-time prekeys

  @widget @platform-linux
  Scenario: Linux cannot scan but can show its code and use links
    Given the platform is Linux
    When "Aisha" opens Connect
    Then scanning a QR code is unavailable with an explanation
    And she can show her QR code or create a link
