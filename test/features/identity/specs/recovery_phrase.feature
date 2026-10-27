@identity @US3
Feature: Secure and restore my identity with a recovery phrase
  As a DaChat user
  I want to save a recovery phrase and restore my identity from it on a new device
  So that losing my phone doesn't force every contact to re-verify me

  @unit @FR-025 @US3-1
  Scenario: A phrase exists after setup without being viewed
    Given I have just completed setup
    Then a 24-word recovery phrase exists for my identity
    And I was not required to view it

  @unit @FR-026 @US3-2 @R20
  Scenario Outline: The "Secure your account" nudge schedule
    Given I completed setup at "<setup>"
    And my phrase is "<phrase>"
    And reminders are "<reminders>"
    When I launch the app at "<launch>"
    Then the "Secure your account" nudge is "<shown>"

    Examples:
      | setup            | phrase      | reminders | launch           | shown   |
      | 2026-11-01 09:00 | unsaved     | on        | 2026-11-01 20:00 | hidden  |
      | 2026-11-01 09:00 | unsaved     | on        | 2026-11-02 09:00 | shown   |
      | 2026-11-01 09:00 | unsaved     | off       | 2026-11-05 09:00 | hidden  |
      | 2026-11-01 09:00 | confirmed   | on        | 2026-11-05 09:00 | hidden  |

  @unit @FR-026 @US3-2 @R20
  Scenario: A dismissed nudge comes back after seven days
    Given the nudge was dismissed at "2026-11-02 09:00"
    And my phrase is unsaved and reminders are on
    When I launch the app at "2026-11-08 09:00"
    Then the "Secure your account" nudge is hidden
    When I launch the app at "2026-11-09 09:00"
    Then the "Secure your account" nudge is shown

  @widget @FR-028
  Scenario: The nudge states that history is never restored
    When the "Secure your account" nudge is shown
    Then it states that message history is never restored

  @widget @FR-026 @FR-039 @US3-3
  Scenario: Viewing the phrase requires confirming three random words
    When I open my recovery phrase
    Then the screen is protected from screenshots and app-switcher previews
    And I see 24 words
    When I tap "I've written it down"
    Then I am asked to enter 3 randomly chosen words by position
    When I enter all 3 correctly
    Then my phrase is marked as saved
    And the nudge no longer appears

  @widget @FR-026
  Scenario: A wrong confirmation word does not mark the phrase as saved
    Given I am confirming my recovery phrase
    When I enter one of the 3 words incorrectly
    Then my phrase is not marked as saved
    And I can try again or view the phrase again

  @integration @FR-027 @FR-045 @SC-008 @US3-4
  Scenario: Restoring on a fresh install brings back the identity, contacts, trust, and blocks
    Given my identity has contacts "Ben" verified via QR and "Chen" not verified via link
    And I have blocked "Dara"
    And my contact backup is up to date
    And I recorded my recovery phrase
    When I erase the device, reinstall DaChat, choose "Restore", and enter my phrase
    Then my identity is the same as before
    And "Ben" is restored as verified
    And "Chen" is restored as not verified
    And "Dara" is restored as blocked
    And I am told message history cannot be restored
    And no previous messages are shown
    And "Ben" sees no identity change and no warning
    And messages flow between me and "Ben" without re-connecting

  @widget @US3-5
  Scenario Outline: A wrong or incomplete phrase restores nothing and can be corrected
    Given I am on the restore screen
    When I enter a phrase that is "<problem>"
    Then nothing is restored
    And I see "<hint>"
    And the words I typed are kept so I can correct them

    Examples:
      | problem               | hint                                   |
      | 23 words long         | The phrase must be 24 words             |
      | has an unknown word 7 | Word 7 isn't a recovery phrase word     |
      | fails the checksum    | This phrase isn't valid. Check each word |

  @integration @edge-backup-missing
  Scenario: Restore without a readable contact backup recovers the identity only
    Given my contact backup is missing on the server
    When I restore my identity with a correct phrase
    Then my identity is the same as before
    And I am told my contacts must be re-connected
    And my former contacts see no identity change

  @integration @edge-backup-stale
  Scenario: Restore from an out-of-date backup warns that recent changes may be missing
    Given I connected with "Eve" while my backup could not sync
    When I restore my identity with a correct phrase on a new device
    Then the last synced contact list is restored
    And I am told recent changes may be missing

  @unit @FR-031 @edge-interrupted
  Scenario: An interrupted restore never leaves a usable partial identity
    Given a restore was interrupted after registration but before commit
    When I launch the app again
    Then no identity is usable
    And I am back at the restore screen with no partial data kept
