import SwiftUI

/// Colors for the dark, hardware-inspired look: matte panels, inset "LCD" wells and an amber accent.
enum Theme {
    static let background = Color(hex: 0x131518)
    static let sidebar = Color(hex: 0x181A1E)
    static let panel = Color(hex: 0x1D2024)
    static let panelHeader = Color(hex: 0x252930)
    static let well = Color(hex: 0x0D0F11)
    static let control = Color(hex: 0x2B3037)
    static let controlHighlight = Color(hex: 0x383E46)

    static let stroke = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.16)

    static let text = Color(hex: 0xE6E8EB)
    static let textDim = Color(hex: 0x9AA1AA)
    static let textFaint = Color(hex: 0x636A73)

    static let accent = Color(hex: 0xFFB020)
    static let accentDark = Color(hex: 0x1A1203)
    static let lcd = Color(hex: 0xFFC247)
    static let ledGreen = Color(hex: 0x4CD964)
    static let ledRed = Color(hex: 0xFF5A4D)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private let controlRadius: CGFloat = 5

// MARK: - Labels and readouts

/// Small uppercase caption above a control, like the silkscreen on a hardware panel.
struct ParamLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textDim)
    }
}

/// A control with its label stacked above it.
struct Param<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ParamLabel(label)
            content
        }
    }
}

/// Amber monospaced text on a dark inset, like a small LCD window.
struct LCDReadout: View {
    let text: String
    var size: CGFloat = 12
    var minWidth: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.lcd)
            .shadow(color: Theme.lcd.opacity(0.35), radius: 3)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(minWidth: minWidth, minHeight: 26)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: controlRadius - 1))
            .overlay(RoundedRectangle(cornerRadius: controlRadius - 1).strokeBorder(Theme.stroke))
    }
}

/// A colored status lamp.
struct LED: View {
    let isOn: Bool
    var color: Color = Theme.accent

    var body: some View {
        Circle()
            .fill(isOn ? color : Theme.well)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(isOn ? color.opacity(0.4) : Theme.strokeStrong, lineWidth: 1))
            .shadow(color: isOn ? color.opacity(0.8) : .clear, radius: 4)
    }
}

// MARK: - Panel

struct DAWPanel<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent)
                    .frame(width: 3, height: 11)
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.text.opacity(0.85))
                Spacer()
                accessory
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Theme.panelHeader)

            Rectangle().fill(Theme.stroke).frame(height: 1)

            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

extension DAWPanel where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Controls

private struct DisabledDimming: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : 0.38)
    }
}

extension View {
    fileprivate func dimWhenDisabled() -> some View { modifier(DisabledDimming()) }
}

/// A dropdown that shows its current value in an LCD-style field.
struct DAWSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var width: CGFloat? = nil

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.label ?? "—")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.lcd)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: controlRadius))
            .overlay(RoundedRectangle(cornerRadius: controlRadius).strokeBorder(Theme.strokeStrong))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .dimWhenDisabled()
    }
}

/// A row of mutually exclusive buttons; the selected one lights up in amber.
struct DAWSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selected ? Theme.accentDark : Theme.textDim)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: controlRadius - 1)
                                .fill(selected ? Theme.accent : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: controlRadius))
        .overlay(RoundedRectangle(cornerRadius: controlRadius).strokeBorder(Theme.strokeStrong))
        .dimWhenDisabled()
    }
}

/// A latching button with a status LED, used for on/off options.
struct DAWToggle: View {
    let title: String
    @Binding var isOn: Bool
    var ledColor: Color = Theme.accent

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                LED(isOn: isOn, color: ledColor)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isOn ? Theme.text : Theme.textDim)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: controlRadius)
                    .fill(isOn ? Theme.controlHighlight : Theme.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: controlRadius)
                    .strokeBorder(isOn ? ledColor.opacity(0.45) : Theme.stroke)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dimWhenDisabled()
    }
}

/// An LCD value flanked by minus and plus buttons.
struct DAWStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let display: String
    var minWidth: CGFloat = 64

    var body: some View {
        HStack(spacing: 4) {
            stepButton("minus", delta: -step)
            LCDReadout(text: display, minWidth: minWidth)
            stepButton("plus", delta: step)
        }
        .dimWhenDisabled()
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        let target = value + delta
        return Button {
            value = min(max(target, range.lowerBound), range.upperBound)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 24, height: 26)
        }
        .buttonStyle(DAWButtonStyle())
        .disabled(!range.contains(target))
    }
}

/// Raised matte button for ordinary actions; `.primary` is the amber call to action.
struct DAWButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, stop }

    var kind: Kind = .normal

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .frame(minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: controlRadius)
                        .fill(fill.opacity(configuration.isPressed ? 0.75 : 1))
                )
                .overlay(RoundedRectangle(cornerRadius: controlRadius).strokeBorder(Theme.stroke))
                .shadow(color: glow, radius: 8)
                .opacity(isEnabled ? 1 : 0.38)
                .contentShape(Rectangle())
        }

        private var foreground: Color {
            switch kind {
            case .normal: return Theme.text
            case .primary: return Theme.accentDark
            case .stop: return .white
            }
        }

        private var fill: Color {
            switch kind {
            case .normal: return Theme.control
            case .primary: return Theme.accent
            case .stop: return Theme.ledRed
            }
        }

        private var glow: Color {
            switch kind {
            case .normal: return .clear
            case .primary: return Theme.accent.opacity(0.35)
            case .stop: return Theme.ledRed.opacity(0.4)
            }
        }
    }
}

/// Dark inset text field for searching.
struct DAWSearchFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
            configuration
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: controlRadius))
        .overlay(RoundedRectangle(cornerRadius: controlRadius).strokeBorder(Theme.strokeStrong))
    }
}
