import Foundation
import Observation
import os
import SwiftUI
import Testing
@testable import StableBar

private func scriptOutput(_ json: String) throws -> ScriptOutput {
    try ScriptOutput.read(Data(json.utf8))
}

@Test @MainActor func anUpdateThatRepeatsTheOutputInvalidatesNothing() async throws {
    let script = ScriptWidget()
    let repeated = try scriptOutput(#"{"text":"40%","icon":"cpu","fields":{"load":"low"},"menu":[{"title":"Open"}]}"#)
    try script.accept(repeated)
    var updates = 0
    script.onUpdate = { updates += 1 }
    try await confirmation("Nothing a view reads changes", expectedCount: 0) { changed in
        withObservationTracking { _ = script.output; _ = script.error; _ = script.samples } onChange: { changed() }
        try script.accept(repeated)
    }
    #expect(updates == 0)
    script.error = "Offline"
    try script.accept(repeated)
    #expect(script.error == nil)
    #expect(updates == 1)
    try await confirmation("A changed output invalidates the widget", expectedCount: 1) { changed in
        withObservationTracking { _ = script.output } onChange: { changed() }
        try script.accept(scriptOutput(#"{"text":"41%","icon":"cpu","fields":{"load":"low"},"menu":[{"title":"Open"}]}"#))
    }
    #expect(updates == 2)
}

@Test @MainActor func repeatedValuesStillAddGraphSamples() async throws {
    let script = ScriptWidget()
    let reading = ScriptOutput(text: "50%", value: 0.5)
    try script.accept(reading)
    try script.accept(reading)
    #expect(script.samples == [0.5, 0.5])
    for _ in 0..<70 { try script.accept(reading) }
    #expect(script.samples == Array(repeating: 0.5, count: 60))
    try await confirmation("A full history of equal samples stays as it is", expectedCount: 0) { changed in
        withObservationTracking { _ = script.samples } onChange: { changed() }
        try script.accept(reading)
    }
}

@Test @MainActor func aRepeatedReadingAddsOneGraphSampleAndInvalidatesNothingElse() async throws {
    let script = ScriptWidget()
    let reading = ScriptOutput(text: "50%", value: 0.5)
    try script.accept(reading)
    var updates = 0
    script.onUpdate = { updates += 1 }
    try await confirmation("The history gains a sample", expectedCount: 1) { sampled in
        try await confirmation("The output and the error stay as they are", expectedCount: 0) { changed in
            withObservationTracking { _ = script.samples } onChange: { sampled() }
            withObservationTracking { _ = script.output; _ = script.error } onChange: { changed() }
            try script.accept(reading)
        }
    }
    #expect(script.samples == [0.5, 0.5])
    #expect(updates == 0)
}

@Test @MainActor func theGraphHistoryKeepsTheNewestSixtySamples() throws {
    let script = ScriptWidget()
    for index in 0..<70 { try script.accept(ScriptOutput(text: "reading", value: Double(index) / 100)) }
    #expect(script.samples == (10..<70).map { Double($0) / 100 })
}

@Test func outputsCompareEveryField() throws {
    let base = try scriptOutput(#"{"text":"A","menu":[{"title":"One"}],"series":{"cpu":[0.1]}}"#)
    #expect(base == (try scriptOutput(#"{"text":"A","menu":[{"title":"One"}],"series":{"cpu":[0.1]}}"#)))
    #expect(base != (try scriptOutput(#"{"text":"A","menu":[{"title":"Two"}],"series":{"cpu":[0.1]}}"#)))
    #expect(base != (try scriptOutput(#"{"text":"A","menu":[{"title":"One"}],"series":{"cpu":[0.2]}}"#)))
    #expect(base != (try scriptOutput(#"{"text":"A","menu":[{"title":"One"}],"series":{"cpu":[0.1]},"state":"warning"}"#)))
}

@MainActor
private final class FakeSource: DataSource {
    private(set) var started = 0
    private(set) var stopped = 0
    private(set) var refreshes: [String] = []
    private(set) var emit: (@Sendable (SourceUpdate) -> Void)?

    func start(emit: @escaping @Sendable (SourceUpdate) -> Void) {
        started += 1
        self.emit = emit
    }

    func refresh(event: ScriptEvent) {
        refreshes.append(event.sender)
    }

    func stop() {
        stopped += 1
        emit = nil
    }
}

/// Makes a new `FakeSource` each time the runner asks for one, and keeps them in order.
@MainActor
private final class FakeSources {
    private(set) var made: [FakeSource] = []

    func make() -> FakeSource {
        let source = FakeSource()
        made.append(source)
        return source
    }
}

/// Waits up to two seconds for `condition`, then requires it.
@MainActor
private func awaitCondition(_ condition: () -> Bool) async throws {
    for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    try #require(condition())
}

@Test @MainActor func aBurstOfUpdatesReachesTheWidgetAsItsNewestValue() async throws {
    let sources = FakeSources()
    let script = ScriptWidget()
    defer { script.stop() }
    script.start(schedule: SourceSchedule(interval: nil, continuous: true)) { sources.make() }
    try await awaitCondition { sources.made.first?.emit != nil }
    let source = try #require(sources.made.first)
    #expect(source.refreshes == ["startup"])
    let emit = try #require(source.emit)
    for index in 1...50 { emit(.output(.success(ScriptOutput(text: "\(index)", value: Double(index) / 100)))) }
    try await awaitCondition { script.output.text == "50" }
    #expect(script.samples.count <= 2)
    #expect(script.samples.last == 0.5)
    await Task.detached {
        for index in 51...100 { emit(.output(.success(ScriptOutput(text: "\(index)")))) }
    }.value
    try await awaitCondition { script.output.text == "100" }
    #expect(script.diagnostics.executionCount == 1)
    #expect(script.diagnostics.running)
}

@Test @MainActor func suspendingStopsTheSourceAndIgnoresItsLateUpdates() async throws {
    let sources = FakeSources()
    let script = ScriptWidget()
    defer { script.stop() }
    script.start(schedule: SourceSchedule(interval: nil, continuous: true)) { sources.make() }
    try await awaitCondition { sources.made.first?.emit != nil }
    let first = try #require(sources.made.first)
    let emit = try #require(first.emit)
    emit(.output(.success(ScriptOutput(text: "live", value: 0.4))))
    try await awaitCondition { script.output.text == "live" }
    script.suspend()
    #expect(first.stopped == 1)
    #expect(!script.diagnostics.running)
    emit(.output(.success(ScriptOutput(text: "late"))))
    try await Task.sleep(for: .milliseconds(50))
    #expect(script.output.text == "live")
    script.resume()
    try await awaitCondition { sources.made.count == 2 && sources.made[1].emit != nil }
    #expect(sources.made[1].refreshes == ["resume"])
    #expect(first.started == 1)
    #expect(script.samples == [0.4])
}

@Test @MainActor func anUpdateDeliveredAsTheWidgetSuspendsIsNotApplied() async throws {
    let sources = FakeSources()
    let script = ScriptWidget()
    defer { script.stop() }
    script.start(schedule: SourceSchedule(interval: nil, continuous: true)) { sources.make() }
    try await awaitCondition { sources.made.first?.emit != nil }
    let source = try #require(sources.made.first)
    source.emit?(.output(.success(ScriptOutput(text: "stale", value: 0.9))))
    script.suspend()
    try await Task.sleep(for: .milliseconds(50))
    #expect(script.output.text == "…")
    #expect(script.samples.isEmpty)
    #expect(script.diagnostics.lastUpdated == nil)
}

@Test @MainActor func aFailedRunRetriesWithBackoffAndARefreshRestartsAContinuousSource() async throws {
    let sources = FakeSources()
    let script = ScriptWidget()
    defer { script.stop() }
    script.start(schedule: SourceSchedule(interval: 0.05, continuous: true)) { sources.make() }
    try await awaitCondition { sources.made.first?.emit != nil }
    let first = try #require(sources.made.first)
    first.emit?(.output(.success(ScriptOutput(text: "Ready"))))
    try await awaitCondition { script.output.text == "Ready" }
    first.emit?(.output(.failure(CommandFailure(message: "Disconnected."))))
    try await awaitCondition { script.error == "Disconnected." }
    #expect(script.output.text == "Ready")
    #expect(script.diagnostics.nextDelay == 1)
    #expect(first.stopped == 1)
    script.refresh(ScriptEvent(sender: "manual"))
    try await awaitCondition { sources.made.count == 2 && sources.made[1].refreshes == ["manual"] }
    #expect(script.diagnostics.restartCount == 1)
    #expect(script.diagnostics.nextDelay == nil)
}

@Test @MainActor func aCommandWhoseOutputDoesNotDecodeStillRecordsItsProcess() async throws {
    let script = ScriptWidget()
    defer { script.stop() }
    script.start(command: "printf '{broken'; printf warning >&2", interval: nil)
    try await awaitCondition { script.error != nil }
    #expect(script.diagnostics.lastStdout == "{broken")
    #expect(script.diagnostics.lastStderr == "warning")
    #expect(script.diagnostics.failureCount == 1)
    #expect(script.output.text == "…")
}

@Test @MainActor func aRepeatedFailureReportsOnceUntilItsMessageChanges() async throws {
    let sources = FakeSources()
    let script = ScriptWidget()
    defer { script.stop() }
    var updates = 0
    script.onUpdate = { updates += 1 }
    script.start(schedule: SourceSchedule(interval: nil)) { sources.make() }
    try await awaitCondition { sources.made.first?.emit != nil }
    let source = try #require(sources.made.first)
    source.emit?(.output(.failure(CommandFailure(message: "Offline"))))
    try await awaitCondition { script.diagnostics.failureCount == 1 }
    #expect(script.error == "Offline")
    #expect(updates == 1)
    try await confirmation("A repeated failure changes nothing a view reads", expectedCount: 0) { changed in
        withObservationTracking { _ = script.error; _ = script.output } onChange: { changed() }
        script.refresh(ScriptEvent(sender: "again"))
        try await awaitCondition { source.started == 2 }
        source.emit?(.output(.failure(CommandFailure(message: "Offline"))))
        try await awaitCondition { script.diagnostics.failureCount == 2 }
    }
    #expect(updates == 1)
    #expect(script.diagnostics.consecutiveFailures == 2)
    script.refresh(ScriptEvent(sender: "later"))
    try await awaitCondition { source.started == 3 }
    source.emit?(.output(.failure(CommandFailure(message: "Still offline"))))
    try await awaitCondition { script.diagnostics.failureCount == 3 }
    #expect(script.error == "Still offline")
    #expect(updates == 2)
}
