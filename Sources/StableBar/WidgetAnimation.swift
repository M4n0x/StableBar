import SwiftUI
import QuartzCore

struct WidgetAnimation: Decodable, Equatable, Sendable {
    enum Curve: String, Decodable, Sendable {
        case linear, easeIn, easeOut, easeInOut, smooth, spring
    }

    var curve: Curve = .easeOut
    var duration: Double = 0.22

    enum CodingKeys: String, CodingKey, CaseIterable { case curve, duration }

    init(curve: Curve = .easeOut, duration: Double = 0.22) {
        self.curve = curve
        self.duration = duration
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        curve = try values.decodeIfPresent(Curve.self, forKey: .curve) ?? curve
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? duration
    }

    var value: Animation {
        switch curve {
        case .linear: .linear(duration: duration)
        case .easeIn: .easeIn(duration: duration)
        case .easeOut: .easeOut(duration: duration)
        case .easeInOut: .easeInOut(duration: duration)
        case .smooth: .smooth(duration: duration)
        case .spring: .spring(duration: duration)
        }
    }

    var timingFunction: CAMediaTimingFunction {
        let name: CAMediaTimingFunctionName = switch curve {
        case .linear: .linear
        case .easeIn: .easeIn
        case .easeOut: .easeOut
        case .easeInOut, .smooth, .spring: .easeInEaseOut
        }
        return CAMediaTimingFunction(name: name)
    }
}

struct WorkspaceConfiguration: Decodable, Sendable {
    enum Indicator: String, Decodable, Sendable {
        case background, underline, none
    }

    var indicator: Indicator?
    var indicatorStyle: WidgetStyle?
    var style: WidgetStyle?
    var focusedStyle: WidgetStyle?
    var visibleStyle: WidgetStyle?
    var emptyStyle: WidgetStyle?
    var appStyle: WidgetStyle?
    var focusedAppStyle: WidgetStyle?
    var visibleAppStyle: WidgetStyle?
    var appGlyphs: [String: String]?
    var showEmpty: Bool?
    var showApps: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case indicator, indicatorStyle, style, focusedStyle, visibleStyle, emptyStyle, appStyle, focusedAppStyle, visibleAppStyle
        case appGlyphs, showEmpty, showApps
    }

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        indicator = try values.decodeIfPresent(Indicator.self, forKey: .indicator)
        indicatorStyle = try values.decodeIfPresent(WidgetStyle.self, forKey: .indicatorStyle)
        style = try values.decodeIfPresent(WidgetStyle.self, forKey: .style)
        focusedStyle = try values.decodeIfPresent(WidgetStyle.self, forKey: .focusedStyle)
        visibleStyle = try values.decodeIfPresent(WidgetStyle.self, forKey: .visibleStyle)
        emptyStyle = try values.decodeIfPresent(WidgetStyle.self, forKey: .emptyStyle)
        appStyle = try values.decodeIfPresent(WidgetStyle.self, forKey: .appStyle)
        focusedAppStyle = try values.decodeIfPresent(WidgetStyle.self, forKey: .focusedAppStyle)
        visibleAppStyle = try values.decodeIfPresent(WidgetStyle.self, forKey: .visibleAppStyle)
        appGlyphs = try values.decodeIfPresent([String: String].self, forKey: .appGlyphs)
        showEmpty = try values.decodeIfPresent(Bool.self, forKey: .showEmpty)
        showApps = try values.decodeIfPresent(Bool.self, forKey: .showApps)
    }
}
