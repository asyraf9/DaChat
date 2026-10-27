@identity @US3
Feature: One active device, and removing DaChat from a device
  As a DaChat user
  I want my identity active on one device at a time and fully erasable from a device
  So that a lost or replaced device cannot keep acting as me

  @integration @FR-029 @US3-6
  Scenario: Restoring on device B signs out and erases device A
    Given my identity is active on device "A"
    And device "A" is offline
    When I restore my identity on device "B"
    Then device "B" is the single active device
    When device "A" next connects
    Then device "A" explains that my identity is now active on another device
    And device "A" erases its identity, history, connections, and block list

  @widget @FR-030 @US3-7
  Scenario: Removing DaChat requires a warning and a typed confirmation
    Given I am on the "Remove from this device" screen
    Then I am warned that without my recovery phrase my identity cannot be recovered
    And the remove button is disabled
    When I type the confirmation word shown on screen
    Then the remove button is enabled

  @integration @FR-030
  Scenario: Removal erases everything local but keeps the server contact backup
    Given I have contacts, messages, and a blocked contact
    When I confirm removal
    Then the identity, history, connections, and block list are gone from this device
    And the app returns to the welcome screen
    And my encrypted contact backup still exists on the server
    And restoring with my phrase later recovers my contacts

  @unit @FR-031 @edge-interrupted
  Scenario: An interrupted removal completes on next launch
    Given a removal was interrupted after the hardware key was deleted
    When I launch the app again
    Then the removal finishes before any screen is shown
    And the app shows the welcome screen

  @unit @C20
  Scenario: Removal clears decrypted content from every open screen state
    Given a conversation with decrypted messages is open
    When my identity is removed from this device
    Then every screen state holding messages, names, or contacts is cleared and closed

  @integration @edge-no-phrase
  Scenario: A lost device without a saved phrase cannot be recovered
    Given I never saved my recovery phrase
    When I install DaChat on a new device and create a new identity
    Then my contacts see a new identity, not my old one
