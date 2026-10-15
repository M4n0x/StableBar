import AppKit

struct BarDisplay {
    let id: Int
    let isBuiltIn: Bool
    let isMain: Bool
    let notch: ClosedRange<CGFloat>?

    init(id: Int, isBuiltIn: Bool, isMain: Bool, notch: ClosedRange<CGFloat>?) {
        self.id = id
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.notch = notch
    }

    init(screen: NSScreen) {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
        self.id = NSScreen.screens.firstIndex(of: screen)! + 1
        isBuiltIn = CGDisplayIsBuiltin(id) != 0
        isMain = id == CGMainDisplayID()
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = (left.maxX - screen.frame.minX)...(right.minX - screen.frame.minX)
        } else {
            notch = nil
        }
    }
}

enum DisplaySelection: Decodable, Equatable, Sendable {
    case all, active, main, builtIn, external, notched, unnotched
    case ids([Int])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let ids = try? value.decode([Int].self) {
            self = .ids(ids)
            return
        }
        switch try value.decode(String.self) {
        case "all": self = .all
        case "active": self = .active
        case "main": self = .main
        case "builtIn": self = .builtIn
        case "external": self = .external
        case "notched": self = .notched
        case "unnotched": self = .unnotched
        default: throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown display selection.")
        }
    }

    func includes(_ display: BarDisplay, activeID: Int) -> Bool {
        switch self {
        case .all: true
        case .active: display.id == activeID
        case .main: display.isMain
        case .builtIn: display.isBuiltIn
        case .external: !display.isBuiltIn
        case .notched: display.notch != nil
        case .unnotched: display.notch == nil
        case let .ids(ids): ids.contains(display.id)
        }
    }
}

struct BarLayout {
    let inset: CGFloat
    let spacing: CGFloat
    let notchSpacing: CGFloat
    let notch: ClosedRange<CGFloat>?

    func origins(width: CGFloat, sizes: [CGFloat]) -> [CGFloat] {
        var origins: [CGFloat] = [inset, 0, (width - sizes[2]) / 2, 0, width - inset - sizes[4]]
        if let notch {
            origins[1] = notch.lowerBound - notchSpacing - sizes[1]
            origins[3] = notch.upperBound + notchSpacing
        } else {
            let visible = (1...3).filter { sizes[$0] > 0 }
            let total = visible.reduce(CGFloat.zero) { $0 + sizes[$1] } + CGFloat(max(visible.count - 1, 0)) * spacing
            var x = (width - total) / 2
            for index in visible {
                origins[index] = x
                x += sizes[index] + spacing
            }
        }
        return origins
    }
}
