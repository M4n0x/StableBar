import SwiftUI

struct SetupTourView: View {
    @Bindable var session: SetupSession
    let screen: NSScreen
    let finish: () -> Void
    let skip: () -> Void
    @State private var phase: Phase
    @State private var wallpaper: CGImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase { case dim, logo, flight, tour }

    private static let pages = [
        ("Start from a preset.", "Your bar changes as you choose. Presets add widgets and never remove yours."),
        ("Give it your style.", "Flip through themes with ← and →. Keep current leaves your theme as it is."),
        ("Choose where it sits.", "Below the menu bar keeps macOS menus visible. The top edge suits a menu bar that hides itself."),
        ("Try your bar.", "It's live: click a widget to open it, or right-click the bar for more. Nothing is saved until you finish.")
    ]

    init(session: SetupSession, screen: NSScreen, intro: Bool, finish: @escaping () -> Void, skip: @escaping () -> Void) {
        _session = Bindable(session)
        self.screen = screen
        self.finish = finish
        self.skip = skip
        _phase = State(initialValue: intro ? .dim : .tour)
    }

    private var barFrame: CGRect {
        let display = BarDisplay(screen: screen)
        guard let configuration = session.store.configuration else { return .zero }
        return CGRect(x: 0, y: configuration.onScreen(ScreenKind(display)).bar.offset,
                      width: screen.frame.width, height: configuration.barGeometry(for: display).layoutHeight)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let bar = barFrame
            ZStack {
                Color.black.opacity(0.5)
                Group {
                    if let wallpaper {
                        Image(decorative: wallpaper, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    }
                    RadialGradient(colors: [.black.opacity(0.3), .black.opacity(0.75)], center: .center,
                                   startRadius: size.height * 0.15, endRadius: size.width * 0.7)
                }
                .opacity(phase == .dim ? 0 : 1)
                EllipticalGradient(colors: [.white.opacity(0.22), Color.accentColor.opacity(0.12), .clear])
                    .frame(width: size.width * 0.8, height: max(bar.height * 6, 180))
                    .scaleEffect(phase == .flight ? 1.25 : 1)
                    .position(x: size.width / 2, y: bar.midY)
                    .opacity(phase == .flight || phase == .tour ? 1 : 0)
                if phase == .logo || phase == .flight {
                    logo(size: size, bar: bar)
                        .transition(.blurFade.combined(with: .scale(scale: 0.92)))
                }
                if phase == .tour {
                    pointer
                        .position(x: size.width / 2, y: bar.maxY + 30)
                        .transition(.opacity)
                    tour(size: size)
                        .transition(.blurFade)
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .task {
            let url = NSWorkspace.shared.desktopImageURL(for: screen)
            wallpaper = await Task.detached {
                guard let url, let image = CIImage(contentsOf: url) else { return nil }
                let scale = 320 / image.extent.width
                let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: small.extent)
                return CIContext().createCGImage(blurred, from: blurred.extent)
            }.value
        }
        .task {
            guard phase == .dim else { return }
            if reduceMotion {
                phase = .tour
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.smooth(duration: 0.9)) { phase = .logo }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.smooth(duration: 0.8)) { phase = .flight }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.smooth(duration: 0.6)) { phase = .tour }
        }
    }

    private func logo(size: CGSize, bar: CGRect) -> some View {
        let flying = phase == .flight
        return ZStack {
            Text("A native, configurable bar for your Mac.")
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .opacity(flying ? 0 : 1)
                .position(x: size.width / 2, y: size.height * 0.42 + 76)
            SetupBadge()
                .scaleEffect(flying ? 0.32 : 1)
                .opacity(flying ? 0 : 1)
                .position(x: size.width / 2, y: flying ? bar.midY : size.height * 0.42)
        }
    }

    private var pointer: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up")
            Text(session.step == 3 ? "Try it on your bar" : "Live on your bar")
                .contentTransition(.opacity)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
        .phaseAnimator(reduceMotion ? [0] : [0, -5]) { content, offset in
            content.offset(y: offset)
        } animation: { _ in .easeInOut(duration: 1) }
    }

    private func tour(size: CGSize) -> some View {
        let page = Self.pages[session.step]
        return VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 12) {
                    Text("\(session.step + 1) / \(Self.pages.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(page.0).font(.system(size: 34, weight: .semibold)).tracking(-0.5)
                    Text(page.1)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }
                .id(session.step)
                .transition(.blurFade)
            }
            ZStack(alignment: .top) {
                Group {
                    switch session.step {
                    case 0: presets
                    case 1: themes
                    case 2: placement
                    default: hints
                    }
                }
                .id(session.step)
                .transition(.blurFade.animation(.smooth(duration: 0.5).delay(0.1)))
            }
            .padding(.top, 44)
            if let error = session.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 560)
                    .padding(.top, 24)
            }
            Spacer(minLength: 24)
            footer
        }
        .foregroundStyle(.white)
        .padding(.top, size.height * 0.24)
        .padding(.bottom, 44)
        .frame(width: size.width, height: size.height)
    }

    private var presets: some View {
        HStack(spacing: 12) {
            ForEach(SetupPreferences.Preset.allCases, id: \.self) { preset in
                let selected = session.preferences == preset.preferences(sets: session.sets)
                SetupTile(selected: selected) {
                    session.preferences = selected ? SetupPreferences() : preset.preferences(sets: session.sets)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: preset.symbol).font(.system(size: 20)).frame(height: 26)
                        Text(preset.title).font(.system(size: 15, weight: .semibold))
                        Text(preset.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(width: 168, height: 156, alignment: .topLeading)
                }
            }
        }
    }

    private var themes: some View {
        let options: [(SetupPreferences.Theme, String)] = [(.current, "Keep current"), (.builtIn, "Built-in")]
            + session.themes.map { (.package(id: $0.manifest.id, version: $0.isBundled ? nil : $0.manifest.version), $0.title) }
        let index = options.firstIndex { $0.0 == session.preferences.theme } ?? 0
        return VStack(spacing: 32) {
            HStack(spacing: 24) {
                roundButton("chevron.left", label: "Previous theme") {
                    session.preferences.theme = options[(index + options.count - 1) % options.count].0
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                VStack(spacing: 6) {
                    ZStack {
                        Text(options[index].1)
                            .font(.system(size: 28, weight: .semibold))
                            .id(index)
                            .transition(.blurFade)
                    }
                    Text(index == 0 ? "Now: \(session.currentTheme)" : "\(index) of \(options.count - 1)")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                }
                .frame(width: 320)
                .animation(.smooth(duration: 0.3), value: index)
                roundButton("chevron.right", label: "Next theme") {
                    session.preferences.theme = options[(index + 1) % options.count].0
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            HStack(spacing: 12) {
                Text("Appearance").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                SettingsSegments(selection: $session.preferences.appearance,
                                 options: SetupPreferences.Appearance.allCases.map { ($0, $0.rawValue) }, stretches: false)
            }
        }
    }

    private var placement: some View {
        VStack(spacing: 32) {
            HStack(spacing: 16) {
                placementTile(.top, title: "Top edge", detail: "Covers the menu bar area.")
                placementTile(.belowMenuBar, title: "Below menu bar", detail: "Keeps macOS menus visible.")
            }
            if session.base?.widgets.contains(where: { if case .clock = $0.content { true } else { false } }) == true {
                HStack(spacing: 12) {
                    Text("Clock").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    SettingsSegments(selection: $session.preferences.clock,
                                     options: SetupPreferences.Clock.allCases.map { ($0, $0.rawValue) }, stretches: false)
                }
            }
        }
    }

    private func placementTile(_ placement: SetupPreferences.Placement, title: String, detail: String) -> some View {
        SetupTile(selected: session.placement == placement) {
            session.preferences.placement = placement
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 3) {
                    if placement == .belowMenuBar {
                        Rectangle().fill(.white.opacity(0.4)).frame(height: 6)
                    }
                    RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.8)).frame(height: 10)
                        .padding(.horizontal, 4)
                    Spacer()
                }
                .frame(width: 232, height: 124)
                .background { Wallpaper(screen: screen) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            .padding(14)
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 20) {
            hint("cursorarrow.click", "Click a widget", "Opens its details and actions.")
            hint("contextualmenu.and.cursorarrow", "Right-click the bar", "Edit Bar in Place, Try Themes and Settings.")
            hint("menubar.rectangle", "Use the menu-bar icon", "Opens Settings and this guide again.")
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1)))
    }

    private func hint(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Button("Continue") {
                if session.step == Self.pages.count - 1 { finish() }
                else { withAnimation(.smooth(duration: 0.5)) { session.step += 1 } }
            }
            .buttonStyle(SetupButtonStyle())
            .keyboardShortcut(.defaultAction)
            HStack(spacing: 20) {
                if session.step > 0 {
                    Button("Back") { withAnimation(.smooth(duration: 0.5)) { session.step -= 1 } }
                }
                Button("Skip setup", action: skip).keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 6) {
                ForEach(Self.pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(index == session.step ? 0.9 : 0.25))
                        .frame(width: index == session.step ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy, value: session.step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(session.step + 1) of \(Self.pages.count)")
        }
    }
}

private struct SetupBadge: View {
    var body: some View {
        TimelineView(.animation) { context in
            let gradient = AngularGradient(colors: [.cyan, .blue, .purple, .pink, .orange, .cyan], center: .center,
                                           angle: .degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90))
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                Text("StableBar").font(.system(size: 28, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .frame(height: 68)
            .background(.black, in: Capsule())
            .overlay(Capsule().strokeBorder(gradient, lineWidth: 2))
            .background(Capsule().fill(gradient).blur(radius: 24).opacity(0.8))
        }
    }
}

private struct SetupTile<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .background(.white.opacity(selected ? 0.12 : hovering ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(selected ? 0.75 : 0.1), lineWidth: selected ? 1.5 : 1))
                .shadow(color: .white.opacity(selected ? 0.18 : 0), radius: 16)
                .scaleEffect(hovering && !selected ? 1.02 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
        .animation(.snappy(duration: 0.25), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SetupButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, 28)
            .frame(minHeight: 40)
            .background(prominent ? Color.white : Color.white.opacity(0.1), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

private struct Blur: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: Blur(radius: 10), identity: Blur(radius: 0)).combined(with: .opacity)
    }
}
