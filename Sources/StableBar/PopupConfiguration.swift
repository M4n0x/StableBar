import Foundation

struct PopupConfiguration: Decodable, Sendable {
    let height: Double
    let style: WidgetStyle
    let layout: PopupBlock
}

indirect enum PopupContent: Sendable {
    case row([PopupBlock])
    case column([PopupBlock])
    case text(String)
    case field(String)
    case graph(height: Double)
    case list(source: String, row: PopupBlock)
    case button(title: String, command: String)
    case menu
    case divider
}

struct PopupBlock: Decodable, Sendable {
    let content: PopupContent
    let style: WidgetStyle
    let alignment: PopupAlignment

    enum CodingKeys: String, CodingKey {
        case type, style, alignment, children, text, field, height, source, row, title, onClick
    }

    init(content: PopupContent) {
        self.content = content
        style = WidgetStyle()
        alignment = .leading
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        style = try values.decodeIfPresent(WidgetStyle.self, forKey: .style) ?? WidgetStyle()
        alignment = try values.decodeIfPresent(PopupAlignment.self, forKey: .alignment) ?? .leading
        switch try values.decode(String.self, forKey: .type) {
        case "row": content = .row(try values.decode([PopupBlock].self, forKey: .children))
        case "column": content = .column(try values.decode([PopupBlock].self, forKey: .children))
        case "text": content = .text(try values.decode(String.self, forKey: .text))
        case "field": content = .field(try values.decode(String.self, forKey: .field))
        case "graph": content = .graph(height: try values.decode(Double.self, forKey: .height))
        case "list":
            content = .list(source: try values.decode(String.self, forKey: .source),
                            row: try values.decode(PopupBlock.self, forKey: .row))
        case "button":
            content = .button(title: try values.decode(String.self, forKey: .title),
                              command: try values.decode(String.self, forKey: .onClick))
        case "menu": content = .menu
        case "divider": content = .divider
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: values, debugDescription: "Unknown popup block type.")
        }
    }
}

enum PopupAlignment: String, Decodable, Sendable {
    case leading, center, trailing
}
