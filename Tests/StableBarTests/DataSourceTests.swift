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

@Test func outputsCompareEveryField() throws {
    let base = try scriptOutput(#"{"text":"A","menu":[{"title":"One"}],"series":{"cpu":[0.1]}}"#)
    #expect(base == (try scriptOutput(#"{"text":"A","menu":[{"title":"One"}],"series":{"cpu":[0.1]}}"#)))
    #expect(base != (try scriptOutput(#"{"text":"A","menu":[{"title":"Two"}],"series":{"cpu":[0.1]}}"#)))
    #expect(base != (try scriptOutput(#"{"text":"A","menu":[{"title":"One"}],"series":{"cpu":[0.2]}}"#)))
    #expect(base != (try scriptOutput(#"{"text":"A","menu":[{"title":"One"}],"series":{"cpu":[0.1]},"state":"warning"}"#)))
}
