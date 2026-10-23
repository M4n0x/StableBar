import Testing
@testable import StableBar

@Test(arguments: [("0.4.0", AppVersion.Channel.stable), ("1.2.3-beta.4", .beta), ("1.2.3-rc.1", .prerelease),
                  ("1.2.3+beta.4", .stable), ("1.2.3-beta.4+local", .beta)])
func appVersionTakesItsChannelFromThePrereleaseAndIgnoresBuildMetadata(version: String, channel: AppVersion.Channel) {
    #expect(AppVersion(version: version, build: nil).channel == channel)
}

@Test(arguments: [nil, ""] as [String?])
func appVersionHandlesMissingBundleMetadata(value: String?) {
    let version = AppVersion(version: value, build: value)
    #expect(version.channel == .development)
    #expect(version.version == nil)
    #expect(version.build == nil)
}
