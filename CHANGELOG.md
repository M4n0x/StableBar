# Changelog

## [0.5.0](https://github.com/Seb-GRAF/StableBar/compare/v0.4.0...v0.5.0) (2026-10-21)

### Features

* add a calendar provider for the next meeting and today's agenda ([451c30a](https://github.com/Seb-GRAF/StableBar/commit/451c30a7a48e2db3aabf56cd4717963d13963b55))
* add a states map to every style ([a4ae6f2](https://github.com/Seb-GRAF/StableBar/commit/a4ae6f249093ef8d372eb6b20cee36ec3ce8a4a1))
* add an equalizer block that bounces while its source is on ([#141](https://github.com/Seb-GRAF/StableBar/issues/141)) ([8e855ee](https://github.com/Seb-GRAF/StableBar/commit/8e855eed93a0350553d7f59e52dbb0cda3ef2cbf))
* add an open state for the widget whose popup shows ([8eb69f4](https://github.com/Seb-GRAF/StableBar/commit/8eb69f443bc456351a5e310feefaac3492613852))
* add Menu Bar, Island, Minimal and Terminal themes that restyle the whole bar ([570ab73](https://github.com/Seb-GRAF/StableBar/commit/570ab733b484ba1cd39aa936bc673abfe12432e3))
* add rules that set data states from provider values and fields ([7c9c70e](https://github.com/Seb-GRAF/StableBar/commit/7c9c70e7c1c40f14545d3b346c08518db9c57022))
* add Tonhalle Line theme and presentation examples ([74449e5](https://github.com/Seb-GRAF/StableBar/commit/74449e59d7b8143229ca735809626021f4ded7c6))
* add widget packages that run no commands ([63efa16](https://github.com/Seb-GRAF/StableBar/commit/63efa165f216500da59a7d766a4f798de4e9f1d7))
* animate changed text and symbols with transitions ([9379e1a](https://github.com/Seb-GRAF/StableBar/commit/9379e1a057848ccc808249505028c15635d082cc))
* animate the active app widget to fit the app's name ([0a00e3f](https://github.com/Seb-GRAF/StableBar/commit/0a00e3f490e6b14c07921090a67f6c3991d196f2))
* ask before enabling an update that adds commands, hosts or permissions ([b623d76](https://github.com/Seb-GRAF/StableBar/commit/b623d76c0577574c27f8272c038b6c7361b6cac1))
* browse and install packages from the store ([b739dfc](https://github.com/Seb-GRAF/StableBar/commit/b739dfcaa58f247fac6338861079fcb972650f46))
* check for and install updates in the app, on a stable or beta track ([f852a25](https://github.com/Seb-GRAF/StableBar/commit/f852a25b87b9864c2b2c2315cff361a653162110))
* customize StableBar without editing the configuration file ([#103](https://github.com/Seb-GRAF/StableBar/issues/103)) ([915e46b](https://github.com/Seb-GRAF/StableBar/commit/915e46b39301de8c4305149f1d5576d54106aa30))
* draw widgets, popups and the bar with Liquid Glass ([7f2310f](https://github.com/Seb-GRAF/StableBar/commit/7f2310fd945801cf08b5c5e3b231d22803516854))
* edit every property the bundled themes set in Customize ([d1fe47c](https://github.com/Seb-GRAF/StableBar/commit/d1fe47c539610aa90dc51be37b85c317355b491d))
* fade or roll widgets in and out when their output hides them ([664d856](https://github.com/Seb-GRAF/StableBar/commit/664d85694787dff99dcffcf09c6c08d39111ef87))
* give clock layouts the time and show every widget's text in Diagnostics ([8dde579](https://github.com/Seb-GRAF/StableBar/commit/8dde579aa132b35fb1d0f04dc4b0fab696ad7f74))
* give colors light and dark values and ship the built-in look and three themes ([5d7c90c](https://github.com/Seb-GRAF/StableBar/commit/5d7c90c0b1875cd84adf98f55c8dd69b334b9393))
* give each screen setup its own bar ([d71a203](https://github.com/Seb-GRAF/StableBar/commit/d71a203f56700405b2776a9307b106082a293a2b))
* keep notification banners clear of the bar ([56872dc](https://github.com/Seb-GRAF/StableBar/commit/56872dc8862dadf4a1e907b95541043599f02ecc))
* keep one Customize item in the bar's menus and move their other actions to General ([2484317](https://github.com/Seb-GRAF/StableBar/commit/2484317eaf21ffb12332d694902bd587f31a0921))
* keep package secrets in the Keychain ([bc29768](https://github.com/Seb-GRAF/StableBar/commit/bc29768bc2eb84b1fdcd4653eaa4ed62072ad0ff))
* keep windows clear of the bar with Accessibility ([d18f156](https://github.com/Seb-GRAF/StableBar/commit/d18f156db9563e60a6c007be04cf9fb0c750a80e))
* let script and provider output set a data state ([0581fa0](https://github.com/Seb-GRAF/StableBar/commit/0581fa06a62c639e7bcf53a1744fe8d1eb73f9e5))
* list the permissions that enabled data sources need in setup ([8e21d1d](https://github.com/Seb-GRAF/StableBar/commit/8e21d1dedd50b7f9894a06060b92194602a269c6))
* merge profiles by name across configuration layers ([7f0f2ed](https://github.com/Seb-GRAF/StableBar/commit/7f0f2ed6113d650c5d5ff717122cc3d7ae1568f6))
* offer presets in setup instead of choosing widget sets ([6473009](https://github.com/Seb-GRAF/StableBar/commit/647300926f86ef01bbe75220430d230f7e7b716a))
* offer sets of built-in widgets in setup ([be2d9fc](https://github.com/Seb-GRAF/StableBar/commit/be2d9fce3dc7a1bdcabc68790c84561732bd0af0))
* open popups on hover and add themed tooltips ([0ba0814](https://github.com/Seb-GRAF/StableBar/commit/0ba081427d7616ff2af218395e582626dd3ed690))
* open URLs and apps from widgets without a shell ([8338ff9](https://github.com/Seb-GRAF/StableBar/commit/8338ff92775bc605ffd9b706659fe425f13ccd1a))
* organize Customize around the bar's look and show where each style comes from ([be1ca77](https://github.com/Seb-GRAF/StableBar/commit/be1ca77920fa44460c98a1f4291d5248eac46d7d))
* pick a theme from installed theme packages ([b600218](https://github.com/Seb-GRAF/StableBar/commit/b60021867f316573ef6bf95e3b58f61625259cfe))
* preview widget sets live on cards and place them beside the app and clock ([fc1a3ff](https://github.com/Seb-GRAF/StableBar/commit/fc1a3ffd18a6d975b8fcd31e26f42abff67fef9a))
* register data source types in one table and show each widget's source in Diagnostics ([45b9f3a](https://github.com/Seb-GRAF/StableBar/commit/45b9f3adbe6c072eaa4ab9628ab695ef2eedffe2))
* remove a saved package secret from the Packages tab ([ac51e7c](https://github.com/Seb-GRAF/StableBar/commit/ac51e7cccd60df63d6a4e2a9775d4159ef7ab2d0))
* replace bundled themes with the community collection ([04b0077](https://github.com/Seb-GRAF/StableBar/commit/04b0077f5f2868853a5f578cbcacea737086102c))
* send power source changes to subscribed scripts ([054d9ae](https://github.com/Seb-GRAF/StableBar/commit/054d9ae522f2ced8406cf4790c163cd0509297b3))
* set the bar's background in Customize ([bff824e](https://github.com/Seb-GRAF/StableBar/commit/bff824e91edfdbe7665de46602225ae36f717888))
* share theme presentation across widgets and bar layout ([7db7ffe](https://github.com/Seb-GRAF/StableBar/commit/7db7ffe6c3c9154bef34a450257056d4e1d8dc39))
* ship a sketchybar-app-font glyph set and match app name prefixes ([b23a4b0](https://github.com/Seb-GRAF/StableBar/commit/b23a4b05166d36aca51a5bf93c6cd3e3145cddcd))
* show and focus individual workspace windows ([85dc0a8](https://github.com/Seb-GRAF/StableBar/commit/85dc0a86b619df97e7a02a80cb29aadc3af860b0))
* show skipped releases in a compact update popup ([5319a29](https://github.com/Seb-GRAF/StableBar/commit/5319a2958e7d92a3fb2ff3b1bb3e36f2c50dfa09))
* show temporary output for a set time ([38eb9f9](https://github.com/Seb-GRAF/StableBar/commit/38eb9f921160001e88a6a5a1450ca9717bd5509d))
* show the app version in an About tab ([a0d94fc](https://github.com/Seb-GRAF/StableBar/commit/a0d94fc5f3260a07e14fbe048e4411321a679d56))
* show the frontmost app's menus in an app menu widget ([45400f8](https://github.com/Seb-GRAF/StableBar/commit/45400f88d9866f6075dbabdb436f606ec5420542))
* show what a package needs in its review ([1740483](https://github.com/Seb-GRAF/StableBar/commit/1740483d119c9a92a57e96309b6c306822499aff))
* simplify configuration and onboarding ([03d527b](https://github.com/Seb-GRAF/StableBar/commit/03d527bba53177e1c2e639e7f004dda025671493))
* uninstall installed package versions ([67e641f](https://github.com/Seb-GRAF/StableBar/commit/67e641faf8eee2f61f2fa910dc55c84a48b01868))
* uninstall installed package versions ([#44](https://github.com/Seb-GRAF/StableBar/issues/44)) ([6c49753](https://github.com/Seb-GRAF/StableBar/commit/6c497538878e7769a3533d8035b3011ff5c71c0b))
* update audio widgets and scripts as soon as the volume or output device changes ([05a0e62](https://github.com/Seb-GRAF/StableBar/commit/05a0e621e4ea9a2cd7d92d3dbc4aa0b7438695c5))
* update battery widgets when macOS reports a power change ([1245d3b](https://github.com/Seb-GRAF/StableBar/commit/1245d3b998c38096f695fefc0ff994364721f38b))

### Bug Fixes

* accept uppercase URL schemes and say widgets packages contain no commands ([90e95a5](https://github.com/Seb-GRAF/StableBar/commit/90e95a5d2ba15218bc5c5655350fb0a72fb11441))
* align workspace height and expose vertical padding ([#60](https://github.com/Seb-GRAF/StableBar/issues/60)) ([88198ca](https://github.com/Seb-GRAF/StableBar/commit/88198ca6a70fbc5268de2cb268067a026dc5fd10))
* allow calendar access in Developer ID releases ([1104e93](https://github.com/Seb-GRAF/StableBar/commit/1104e93b6d9347b12d5268d2300c16a96388c9e6))
* allow negative workspace underline offsets ([a172616](https://github.com/Seb-GRAF/StableBar/commit/a172616ae8f8bd12f823b0c32213974a769f1eec))
* allow package secrets only in the environments of a package's own widgets and providers ([6f7e5b9](https://github.com/Seb-GRAF/StableBar/commit/6f7e5b9cc2318293a46abdb051847dfad787a9a4))
* check for the latest release before downloading ([2acbd83](https://github.com/Seb-GRAF/StableBar/commit/2acbd834ea37ef355bbbf8eabd90b149fbd81abf))
* check for updates every four minutes ([1362d62](https://github.com/Seb-GRAF/StableBar/commit/1362d622d3436fdeaf1edf9688da733b71f69b3f))
* draw Blueprint's workspace underline on the widget's bottom border ([948b7dc](https://github.com/Seb-GRAF/StableBar/commit/948b7dc4cc0edef608df26adbedf41b2c0334e36))
* give Blueprint's widgets room in a full-height frame ([077bd53](https://github.com/Seb-GRAF/StableBar/commit/077bd53898589e3c2ae41b912f19ac1bfb82acda))
* give icon-only widgets the height of a line of text ([9a8e8ac](https://github.com/Seb-GRAF/StableBar/commit/9a8e8aca9eddb93433fa241f626b942c4da57837))
* identify local app builds as development ([83a0b4b](https://github.com/Seb-GRAF/StableBar/commit/83a0b4baebd0e5e8ece97646212449b3e1c46309))
* ignore unchanged settings selections ([7ca7324](https://github.com/Seb-GRAF/StableBar/commit/7ca7324c1e93b905385c77f6ca5f7a9178f7be33))
* keep a clicked popup open when glass draws behind its widget ([2569727](https://github.com/Seb-GRAF/StableBar/commit/2569727565bd805a19496ea47f30de5864cb227a))
* keep colors that setup and the starter configuration wrote from hiding a theme ([c6de0a8](https://github.com/Seb-GRAF/StableBar/commit/c6de0a8ed574dca4fa799bf3c7da5e64f8c22c8f))
* keep native workspace icons steady on hover ([8b2b543](https://github.com/Seb-GRAF/StableBar/commit/8b2b54353b216a70abeda6e7af1892ac5e390cd7))
* keep new beta releases in order on GitHub ([ae454b6](https://github.com/Seb-GRAF/StableBar/commit/ae454b625d79145879bc7b7f7bf59c4ac18beb31))
* keep notification clearance from freezing the bar ([546c908](https://github.com/Seb-GRAF/StableBar/commit/546c9082c23f00083b58f281fb0617f96402b013))
* keep popup content at full size while opening ([470b7da](https://github.com/Seb-GRAF/StableBar/commit/470b7da92acdccef149d64e977c53e393ad6aca3))
* keep the bar running when a package's widget and its popup are removed together ([a46a180](https://github.com/Seb-GRAF/StableBar/commit/a46a18071a1187cd7932d2301da036b4565b6190))
* keep the store's errors and unknown kinds from blocking local packages ([9424aaa](https://github.com/Seb-GRAF/StableBar/commit/9424aaa50e56a25d8c31f4c243415a3731060f83))
* keep zoomed windows below the bar ([eb15873](https://github.com/Seb-GRAF/StableBar/commit/eb158730c5efced629b7936f7843da4662087cd6))
* list commands that packages read from fields in their review ([9a50ddf](https://github.com/Seb-GRAF/StableBar/commit/9a50ddf77d25eb8a1cc64abbdd8cfa01c27bd319))
* make the whole popup block clickable ([d84a9b2](https://github.com/Seb-GRAF/StableBar/commit/d84a9b218ce318c5aff3ec2cfabea0c1aba13cfe))
* make the whole widget tile clickable ([3f0f3ac](https://github.com/Seb-GRAF/StableBar/commit/3f0f3acec7f7cecf56802490c1991e8ab1fc956b))
* make the whole widget tile clickable ([#46](https://github.com/Seb-GRAF/StableBar/issues/46)) ([2f36fd6](https://github.com/Seb-GRAF/StableBar/commit/2f36fd66e36833d191dfd644814e280df206006e))
* match update icons to the active theme ([e38f7ff](https://github.com/Seb-GRAF/StableBar/commit/e38f7ff3dcf37a85d7120d97b44505f06270b38e))
* move neighboring widgets when app menus expand ([6263d6f](https://github.com/Seb-GRAF/StableBar/commit/6263d6f640f48c5ed30834228b1592421f3fc445))
* preserve older themes as custom after updates ([a70201e](https://github.com/Seb-GRAF/StableBar/commit/a70201ec3e2d1b30c7db57a83f2b4a04ec90f93b))
* recover app menus after temporary read failures ([1a19cea](https://github.com/Seb-GRAF/StableBar/commit/1a19ceaf0c5cce0915bd28d557e228fbd6a26b45))
* reject contradictory width limits inside states ([026afd4](https://github.com/Seb-GRAF/StableBar/commit/026afd432bcdc373fbb2f3f27adadcbbb3c8d36f))
* render workspace icons at each display resolution ([12c477c](https://github.com/Seb-GRAF/StableBar/commit/12c477cd83aa0ea0790933ba087d202176533db4))
* save only edited package secrets and never lose the saved one ([6a4ff00](https://github.com/Seb-GRAF/StableBar/commit/6a4ff00a02eb98746b47ee8a1808925453bcd503))
* show a store package's source and mark installed store entries ([39f00a6](https://github.com/Seb-GRAF/StableBar/commit/39f00a6fb442cad8976f55d86fb65a8d893ea5f3))
* show the review of the package selected last ([6d5703c](https://github.com/Seb-GRAF/StableBar/commit/6d5703caaecbeb7427f02d938c0cc271d0adbf26))
* show updates sooner and resize the update popup ([618f575](https://github.com/Seb-GRAF/StableBar/commit/618f57542c3d38179a797fe03f7a135ebb2b6d03))
* take removed widgets off the bar while editing it ([#106](https://github.com/Seb-GRAF/StableBar/issues/106)) ([594aa34](https://github.com/Seb-GRAF/StableBar/commit/594aa34e3b70ce9a7d781f2fdd2c42cc8ba80a9a))
* tell Settings and in-place bar editing apart in the menus ([39e8156](https://github.com/Seb-GRAF/StableBar/commit/39e815623cf5dfc7bef0e7a7bfc5fa7523077328)), closes [#131](https://github.com/Seb-GRAF/StableBar/issues/131)
* treat an empty data state name as no state ([557d267](https://github.com/Seb-GRAF/StableBar/commit/557d267243beefe2d425572c009392e196ed018c))
* use widget hover colors for app menus ([f3b0e7d](https://github.com/Seb-GRAF/StableBar/commit/f3b0e7d50f70974d500c4404a4cb3e20219c5108))

### Performance Improvements

* apply only changed script output so repeated updates redraw nothing ([f7e0d0c](https://github.com/Seb-GRAF/StableBar/commit/f7e0d0c0e21742bc02ecfd7c160e5ac51d49bb22))
* build layout blocks without type erasure and keep the measuring copy still ([e39ac94](https://github.com/Seb-GRAF/StableBar/commit/e39ac9482e213508915c96caffcea2eac94d5dcd))
* resolve widget styles in the store so one update redraws only its widgets ([86f8935](https://github.com/Seb-GRAF/StableBar/commit/86f8935e2456f261300f8fbda737bd011205409b))

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
