# Changelog

## [0.4.0](https://github.com/Seb-GRAF/StableBar/compare/v0.3.0...v0.4.0) (2026-10-15)

### Features

* add yabai workspaces and profile editing ([5c30c63](https://github.com/Seb-GRAF/StableBar/commit/5c30c63df6d7924156005931030f079668ca0396))

## [0.3.0](https://github.com/Seb-GRAF/StableBar/compare/v0.2.0...v0.3.0) (2026-10-15)

### Features

* open Customize from the bar's right-click menu ([361f2e8](https://github.com/Seb-GRAF/StableBar/commit/361f2e8c45478b9f46293e33b27e188e137539c5))
* scale the bar separately on built-in and external displays ([c0b6007](https://github.com/Seb-GRAF/StableBar/commit/c0b600725b032b4f4466de993915972781323f5c))

### Bug Fixes

* hide workspace widgets on displays without workspaces and let the row grow ([59dd4d2](https://github.com/Seb-GRAF/StableBar/commit/59dd4d2c1290de897bfedeb483af615ffb18dfbc))
* reject unknown display types and non-positive display scales ([b6d0bbc](https://github.com/Seb-GRAF/StableBar/commit/b6d0bbc2b3a3f3ca734982e033854edbec0fe681))

## [0.2.0](https://github.com/Seb-GRAF/StableBar/compare/v0.1.1...v0.2.0) (2026-10-15)

### Features

* add one-line system, network, battery and audio widgets ([7b39bd8](https://github.com/Seb-GRAF/StableBar/commit/7b39bd83c8e25916edd918f1b6ee21866231fa07))
* edit the live bar and add widget types and bar settings to the editor ([58a7262](https://github.com/Seb-GRAF/StableBar/commit/58a7262cfbeff6e87b88cb22be0ef3c2a8a005ac))
* emit an aerospaceMode event when the AeroSpace mode changes ([54f5441](https://github.com/Seb-GRAF/StableBar/commit/54f5441bd18a082eaf9552e0f70086c219adbf85))
* follow the system light or dark mode by default ([f2b94ab](https://github.com/Seb-GRAF/StableBar/commit/f2b94ab9fbadd37aec4e83885ee18e544d52c785))
* reject unknown configuration properties and publish a JSON schema ([5239970](https://github.com/Seb-GRAF/StableBar/commit/523997091bd65d89e0fd8e69cdcdebbbab612193))
* size popups to their content when no height is set ([e73b2a4](https://github.com/Seb-GRAF/StableBar/commit/e73b2a46b6b6fb9ae884323b6fc2d2efa3724aeb))

### Bug Fixes

* explain in setup and the README how to keep windows clear of the bar ([2ba8fb0](https://github.com/Seb-GRAF/StableBar/commit/2ba8fb0184361132a46ea5bcd2db33cf0b7d2a17))
* find aerospace on the login shell PATH ([ebd9416](https://github.com/Seb-GRAF/StableBar/commit/ebd9416cbf2d5a9ab1a265670d456057611c86a4))
* keep the layout of untouched configuration when saving edits ([a71aacf](https://github.com/Seb-GRAF/StableBar/commit/a71aacf87fb5739cbb50355f420915656184c3f5))
* keep trigger and notification data from replacing login shell variables ([a75eec9](https://github.com/Seb-GRAF/StableBar/commit/a75eec956b1c7c6e60cafb95bdc4ccb3fa62b455))
* refresh the clock once a minute unless its format shows seconds ([21c144b](https://github.com/Seb-GRAF/StableBar/commit/21c144b7019679fdddbea1f054e2e7d416499c5f))
* resolve package image paths from the origin file instead of its label ([55cc4f1](https://github.com/Seb-GRAF/StableBar/commit/55cc4f1881fb9486b37d8840d86bdcc18869a0ca))
* show action errors on their widget and open Customize from the configuration error ([bac4a01](https://github.com/Seb-GRAF/StableBar/commit/bac4a0123ff19e21406bcf0266db65166644d3fc))

### Performance Improvements

* read the login shell environment once instead of per command ([602f83b](https://github.com/Seb-GRAF/StableBar/commit/602f83b375480ab38fe085cfb46f7fff2f77a598))
* reload the configuration on app switches only when a profile matches apps ([39f17de](https://github.com/Seb-GRAF/StableBar/commit/39f17de06234b9fc3a95967511c53134f12e230c))

## [0.1.1](https://github.com/Seb-GRAF/StableBar/compare/v0.1.0...v0.1.1) (2026-10-15)

### Bug Fixes

* build popup sizing with Swift 6.2 ([afeadcd](https://github.com/Seb-GRAF/StableBar/commit/afeadcda000212954cf002d4764b24cb092899de))
