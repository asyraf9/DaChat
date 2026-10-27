@identity @US1
Feature: Create an identity without any identifier
  As a new person installing DaChat
  I want my device to create my identity on the main server in seconds
  So that I can message privately without giving an invite, phone, email, username, or password

  Background:
    Given a fresh install of DaChat
    And the main server is reachable

  @integration @FR-001 @FR-002 @FR-025 @SC-009
  Scenario: Identity is created and registered with no identifier and no phrase step
    When I open the app and tap "Get started"
    Then I am never asked for an invite, phone number, email, username, or password
    And I am never asked for a server address
    And I am not shown or asked to save a recovery phrase
    And my identity is registered on the main server
    And a recovery phrase already exists on this device

  @widget @FR-005 @US1-2
  Scenario: Setup explains what the server can and cannot observe
    When I reach the end of setup
    Then I see that the server cannot read my messages or my display name
    And I see that the server can see which identities exchange messages, when, and roughly how large they are
    And I can only finish setup after this explanation has been shown

  @widget @FR-003
  Scenario Outline: Key protection is disclosed honestly
    Given this device's key protection is "<level>"
    When I reach the end of setup
    Then the key protection notice is "<notice>"

    Examples:
      | level            | notice                  |
      | hardwareStrongBox| hardware-backed          |
      | hardwareTee      | hardware-backed          |
      | secureEnclave    | hardware-backed          |
      | osKeyring        | weaker on this device    |
      | passphrase       | weaker on this device    |

  @widget @FR-024
  Scenario: iOS discloses push-timing exposure
    Given the platform is iOS
    When I reach the end of setup
    Then I see that Apple's push service can observe when messages arrive but not their content

  @unit @FR-006 @US1-3
  Scenario: Display name is stored locally and never sent to the server in readable form
    When I set my display name to "Aisha"
    Then my display name is saved on this device
    And no request to the main server contains "Aisha"

  @unit @FR-006
  Scenario Outline: Display name validation
    When I set my display name to <input>
    Then the display name is "<result>"

    Examples:
      | input                          | result   |
      | "Aisha"                        | accepted |
      | "  Aisha  "                    | accepted |
      | an empty string                | rejected |
      | only whitespace                | rejected |
      | 64 characters                  | accepted |
      | 65 characters                  | rejected |
      | text containing a control char | rejected |

  @unit @edge-offline @R19
  Scenario: Creating an identity while offline finishes when connectivity returns
    Given the main server is not reachable
    When I open the app and tap "Get started"
    Then my identity keys are created on this device
    And I am told setup will finish when I am back online
    And nothing is published to the main server
    And showing my QR code and creating links are unavailable
    When connectivity returns
    Then my identity is registered on the main server
    And showing my QR code and creating links become available

  @unit @FR-007
  Scenario: There is no way to look anyone up
    Then the app offers no search, directory, or lookup of other users
    And the main server API exposes no endpoint that lists or searches identities
