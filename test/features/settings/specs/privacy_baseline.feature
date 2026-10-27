@settings @baseline
Feature: Privacy, accessibility, language, and appearance baseline
  As any DaChat user
  I want the app to leak nothing to third parties, protect sensitive screens, and work for everyone
  So that privacy and usability hold across every screen in this release

  @integration @FR-040 @SC-011
  Scenario: No egress to any third-party operator
    Given network traffic is captured for a full test session covering every user story
    Then every connection goes only to the main server, or to Apple's push service on iOS
    And no traffic carries message content, behavioural analytics, or crash telemetry

  @unit @FR-041 @C5
  Scenario: Logs never contain sensitive data
    Given every log line is captured during a full test session covering every user story
    Then no log line contains message content, display names, recovery-phrase words, or code words
    And no log line contains identity keys, account addresses, contact identifiers, or session references

  @unit @FR-041 @C3
  Scenario: Failures never carry sensitive data
    Then every failure type carries only an opaque error code

  @widget @FR-039
  Scenario Outline: Sensitive screens are protected from screenshots and previews
    When I open the "<screen>" screen
    Then the screen is protected from screenshots and app-switcher previews

    Examples:
      | screen          |
      | my QR code      |
      | QR scanner      |
      | safety code     |
      | recovery phrase |
      | restore         |

  @widget @FR-039 @platform-linux
  Scenario: Linux discloses that screenshots can't be prevented
    Given the platform is Linux
    When I open the "recovery phrase" screen
    Then I am told this device cannot prevent screenshots

  @widget @FR-042
  Scenario: Every user-facing string is localizable
    Then every screen in this feature renders only strings from the English localization file

  @widget @FR-043 @SC-012
  Scenario Outline: Light and dark themes follow the device
    Given the device appearance is "<mode>"
    When I open every screen in this feature
    Then each screen renders in the "<mode>" theme using only theme colours

    Examples:
      | mode  |
      | light |
      | dark  |

  @widget @FR-044 @SC-012
  Scenario: Every control has a screen-reader label
    When I open every screen in this feature
    Then every interactive element and non-decorative image has a screen-reader label
    And each screen can be completed using only a screen reader
