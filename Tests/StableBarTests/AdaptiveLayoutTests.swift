import Foundation
import Testing
@testable import StableBar

@Test func adaptiveLayoutKeepsHighPriorityWidgetsAndReservesOverflowSpace() {
    let planner = AdaptiveBarPlanner(inset: 10, spacing: 8, notchSpacing: 16, notch: nil)
    let plan = planner.plan(width: 300, items: [
        BarLayoutItem(id: "workspaces", position: .left, width: 150, priority: 10),
        BarLayoutItem(id: "weather", position: .right, width: 100),
        BarLayoutItem(id: "clock", position: .right, width: 80, priority: 20)
    ])
    #expect(plan.overflow == ["weather"])
    #expect(plan.overflowX == 260)
    #expect(plan.placements["workspaces"] == BarPlacement(x: 10, width: 150))
    #expect(plan.placements["clock"] == BarPlacement(x: 172, width: 80))
}

@Test func adaptiveLayoutMovesTheCenterWithinFreeSpaceBeforeOverflowing() {
    let planner = AdaptiveBarPlanner(inset: 10, spacing: 8, notchSpacing: 16, notch: nil)
    let plan = planner.plan(width: 600, items: [
        BarLayoutItem(id: "left", position: .left, width: 290),
        BarLayoutItem(id: "center", position: .center, width: 150),
        BarLayoutItem(id: "right", position: .right, width: 90)
    ])
    #expect(plan.overflow.isEmpty)
    #expect(plan.placements["center"] == BarPlacement(x: 308, width: 150))
    #expect(plan.placements["right"] == BarPlacement(x: 500, width: 90))
}

@Test func adaptiveLayoutCollapsesOnlyTheCrowdedNotchSegment() {
    let planner = AdaptiveBarPlanner(inset: 10, spacing: 8, notchSpacing: 20, notch: 400...600)
    let plan = planner.plan(width: 1000, items: [
        BarLayoutItem(id: "left", position: .left, width: 200, priority: 10),
        BarLayoutItem(id: "music", position: .notchLeft, width: 250),
        BarLayoutItem(id: "center", position: .center, width: 120),
        BarLayoutItem(id: "clock", position: .right, width: 80)
    ])
    #expect(plan.overflow == ["music"])
    #expect(plan.placements["left"] == BarPlacement(x: 10, width: 200))
    #expect(plan.placements["center"]!.x >= 620)
    #expect(plan.placements["clock"]!.x + 80 == 952)
    #expect(plan.overflowX == 960)
}

@Test func namedGroupsCollapseAsAUnitAndKeepOriginalMemberOrder() throws {
    let config = try JSONDecoder().decode(Configuration.self, from: Data(#"""
    {"groups":{"stats":{"style":{}}},"widgets":[
      {"id":"cpu","type":"text","text":"CPU","position":"right","group":"stats"},
      {"id":"clock","type":"clock","position":"right","priority":10},
      {"id":"ram","type":"text","text":"RAM","position":"right","group":"stats"}
    ]}
    """#.utf8))
    let units = BarUnit.make(widgets: config.widgets, groups: config.groups)
    #expect(units.map(\.id) == ["group:stats", "widget:clock"])
    #expect(units[0].widgets.map(\.id) == ["cpu", "ram"])
    let plan = AdaptiveBarPlanner(inset: 10, spacing: 8, notchSpacing: 16, notch: nil).plan(width: 200, items: units.map {
        BarLayoutItem(id: $0.id, position: $0.position, width: 120, priority: $0.priority, canOverflow: $0.canOverflow)
    })
    #expect(plan.overflow == ["group:stats"])
    #expect(plan.placements["widget:clock"] != nil)
}

@Test func neverOverflowWidgetsRemainReachableOnVeryNarrowDisplays() {
    let plan = AdaptiveBarPlanner(inset: 10, spacing: 8, notchSpacing: 16, notch: nil).plan(width: 100, items: [
        BarLayoutItem(id: "required", position: .left, width: 200, canOverflow: false),
        BarLayoutItem(id: "optional", position: .right, width: 50)
    ])
    #expect(plan.overflow == ["optional"])
    #expect(plan.placements["required"] == BarPlacement(x: 10, width: 42))
    #expect(plan.overflowX == 60)
}

@Test func equalPriorityOverflowOrderIsDeterministicAndSpacersUseRemainingWidth() {
    let planner = AdaptiveBarPlanner(inset: 10, spacing: 8, notchSpacing: 16, notch: nil)
    let compact = planner.plan(width: 200, items: [
        BarLayoutItem(id: "first", position: .left, width: 100),
        BarLayoutItem(id: "last", position: .right, width: 100)
    ])
    #expect(compact.overflow == ["last"])
    let roomy = planner.plan(width: 500, items: [
        BarLayoutItem(id: "first", position: .left, width: 100),
        BarLayoutItem(id: "space", position: .left, width: 10, isSpacer: true),
        BarLayoutItem(id: "last", position: .right, width: 100)
    ])
    #expect(roomy.placements["space"] == BarPlacement(x: 118, width: 264))
    #expect(roomy.placements["last"] == BarPlacement(x: 390, width: 100))
    #expect(roomy.overflow.isEmpty)
}

@Test func popupSearchMatchesTextWithoutSearchingUndeclaredActionFields() {
    let rows = [
        ["name": "Café player", "command": "open music"],
        ["name": "Terminal", "command": "echo cafe"],
        ["name": "Music", "command": "open player"]
    ]
    #expect(searchPopupRows(rows, query: "CAFE", fields: ["name"]) == [rows[0]])
    #expect(searchPopupRows(rows, query: "", fields: ["name"]) == rows)
    #expect(searchPopupRows(rows, query: "PLAYER", fields: nil) == [rows[0], rows[2]])
}

@Test func inheritedWidthConstraintsAreCheckedAfterWidgetOverrides() throws {
    let data = Data(#"""
    {"defaults":{"minWidth":200},"widgets":[
      {"id":"title","type":"text","text":"Title","position":"left","style":{"maxWidth":100}}
    ]}
    """#.utf8)
    #expect(throws: CommandFailure.self) { try JSONDecoder().decode(Configuration.self, from: data) }
    let overridden = Data(#"""
    {"defaults":{"minWidth":200},"widgets":[
      {"id":"title","type":"text","text":"Title","position":"left","style":{"minWidth":80,"maxWidth":100}}
    ]}
    """#.utf8)
    let config = try JSONDecoder().decode(Configuration.self, from: overridden)
    #expect(config.widgets[0].style.inheriting(config.defaults).minWidth == 80)
    let negative = Data(#"""
    {"defaults":{"maxWidth":-1},"widgets":[
      {"id":"title","type":"text","text":"Title","position":"left"}
    ]}
    """#.utf8)
    #expect(throws: CommandFailure.self) { try JSONDecoder().decode(Configuration.self, from: negative) }
}
