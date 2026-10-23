import Foundation
import Testing
@testable import StableBar

@Test func equalizerMistakesNameTheirProblem() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "equalizer.json")
    var loader = ConfigurationLoader()
    for height in ["0", "-4"] {
        let json = #"{"widgets":[{"id":"music","type":"text","text":"A","position":"left","layout":{"type":"equalizer","height":\#(height)}}]}"#
        let error = #expect(throws: (any Error).self) { try loader.load(url, data: Data(json.utf8)) }
        #expect(error.map(errorMessage) == "widgets.music: layout.height: An equalizer's height must be greater than zero.")
    }
    let transition = #"{"widgets":[{"id":"music","type":"text","text":"A","position":"left","layout":{"type":"equalizer","transition":"fade"}}]}"#
    let error = #expect(throws: (any Error).self) { try loader.load(url, data: Data(transition.utf8)) }
    #expect(error.map(errorMessage) == "widgets.music: layout.transition: Transitions apply to text, field and symbol blocks.")
}

@Test func equalizerBarsBounceApartWhilePlayingAndSettleWhenNot() {
    let playing = Equalizer(playing: true, height: 12)
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let moments = (0..<120).map { start.addingTimeInterval(Double($0) / 30) }
    for index in 0..<4 {
        let heights = moments.map { playing.fraction(index, at: $0, still: false) }
        #expect(heights.allSatisfy { $0 >= Equalizer.settled - 1e-9 && $0 <= 1 + 1e-9 }, "bar \(index)")
        #expect(heights.max()! - heights.min()! > 0.4, "bar \(index) bounces")
        #expect(playing.fraction(index, at: start, still: true) == Equalizer.still[index])
        #expect(Equalizer(playing: false, height: 12).fraction(index, at: start, still: false) == Equalizer.settled)
    }
    let together = Set((0..<4).map { (playing.fraction($0, at: start, still: false) * 100).rounded() })
    #expect(together.count == 4, "No two bars move together")
}
