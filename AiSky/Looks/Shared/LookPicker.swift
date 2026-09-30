import AiSkyKit
import SwiftUI

/// Settings' look picker: six small previews drawn from each look's own tokens, names under
/// them and a check on the current one.
struct LookPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
            ForEach(Look.allCases) { look in
                let selected = look == model.look
                Button {
                    model.setLook(look)
                } label: {
                    VStack(spacing: 8) {
                        LookPreview(tokens: LookTokens.tokens(for: look))
                            .aspectRatio(0.72, contentMode: .fit)
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, t.controlTint ?? Palette.color(hex: 0x0A84FF))
                                        .padding(5)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(selected ? (t.controlTint ?? t.ink) : t.line, lineWidth: selected ? 2 : 1)
                            }
                        Text(look.displayName)
                            .font(t.look == .liquid ? .footnote.weight(.semibold) : t.font(.textStrong, 13))
                            .foregroundStyle(selected ? t.ink : t.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(look.displayName). \(look.summary)")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .sensoryFeedback(.selection, trigger: model.look)
    }
}

/// A miniature of a look: its page, a hint of its hero and one card, in its own colors and type.
struct LookPreview: View {
    let tokens: LookTokens

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .topLeading) {
                background
                content(width: w)
                    .padding(w * 0.09)
            }
            .frame(width: w, height: proxy.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, tokens.colorScheme)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var background: some View {
        if tokens.usesSky {
            LinearGradient(colors: [0x2B5EA8, 0x4F86C9, 0x8DB5DF].map { Palette.color(hex: $0) }, startPoint: .top, endPoint: .bottom)
        } else {
            tokens.background
        }
    }

    @ViewBuilder
    private func content(width w: CGFloat) -> some View {
        switch tokens.look {
        case .liquid: liquid(w)
        case .obsidian: obsidian(w)
        case .instrument: instrument(w)
        case .editorial: editorial(w)
        case .horizon: horizon(w)
        case .chroma: chroma(w)
        }
    }

    private func bars(_ count: Int, color: Color, height: CGFloat, spacing: CGFloat = 1.5, radius: CGFloat = 1) -> some View {
        let shape: [CGFloat] = [0.1, 0.1, 0.2, 0.35, 0.5, 0.7, 0.85, 0.75, 1, 0.9, 0.7, 0.55, 0.35, 0.2, 0.1]
        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: radius)
                    .fill(color)
                    .frame(height: max(1.5, height * shape[index % shape.count]))
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func liquid(_ w: CGFloat) -> some View {
        VStack(spacing: w * 0.05) {
            Text("64°")
                .font(.system(size: w * 0.3, weight: .thin))
                .foregroundStyle(.white)
                .padding(.leading, w * 0.06)
            RoundedRectangle(cornerRadius: w * 0.1, style: .continuous)
                .fill(Color.white.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: w * 0.1, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                .overlay(bars(9, color: .white.opacity(0.7), height: w * 0.14).padding(w * 0.06), alignment: .bottom)
                .frame(height: w * 0.32)
            RoundedRectangle(cornerRadius: w * 0.1, style: .continuous)
                .fill(Color.white.opacity(0.22))
                .frame(height: w * 0.2)
        }
        .frame(maxWidth: .infinity)
    }

    private func obsidian(_ w: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: w * 0.05) {
            HStack(alignment: .top, spacing: 1) {
                Text("64")
                    .font(tokens.display.font(w * 0.38, fixed: true))
                    .tracking(-w * 0.02)
                Text("°")
                    .font(tokens.display.font(w * 0.16, fixed: true))
                    .foregroundStyle(tokens.rain)
            }
            .foregroundStyle(tokens.ink)
            .frame(height: w * 0.36)
            Rectangle().fill(tokens.line).frame(height: 0.8)
            Capsule().fill(tokens.ink2).frame(width: w * 0.5, height: 1.5)
            Capsule().fill(tokens.rain).frame(width: w * 0.36, height: 1.5)
            Rectangle().fill(tokens.line).frame(height: 0.8)
            MiniCurve().stroke(tokens.rain, lineWidth: 1)
                .frame(height: w * 0.16)
        }
    }

    private func instrument(_ w: CGFloat) -> some View {
        VStack(spacing: w * 0.06) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(tokens.track, style: StrokeStyle(lineWidth: w * 0.045, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0.35, to: 0.6)
                    .stroke(tokens.ink, style: StrokeStyle(lineWidth: w * 0.045, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Capsule()
                    .fill(tokens.now)
                    .frame(width: w * 0.02, height: w * 0.13)
                    .offset(y: -w * 0.24)
                    .rotationEffect(.degrees(27))
                Text("64")
                    .font(tokens.display.font(w * 0.2, fixed: true))
                    .foregroundStyle(tokens.ink)
            }
            .frame(width: w * 0.58, height: w * 0.58)
            RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                .fill(tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: w * 0.07, style: .continuous).strokeBorder(tokens.line, lineWidth: 0.8))
                .overlay(bars(10, color: tokens.rain, height: w * 0.12).padding(w * 0.05), alignment: .bottom)
                .frame(height: w * 0.24)
        }
        .frame(maxWidth: .infinity)
    }

    private func editorial(_ w: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: w * 0.04) {
            Rectangle().fill(tokens.rule).frame(height: 0.8)
            Text("Rain arrives in eighteen minutes.")
                .font(tokens.headline.font(w * 0.105, fixed: true))
                .foregroundStyle(tokens.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("64°")
                .font(tokens.display.font(w * 0.3, fixed: true))
                .foregroundStyle(tokens.ink)
                .frame(height: w * 0.3)
            Rectangle().fill(tokens.line).frame(height: 0.8)
            bars(12, color: tokens.rain, height: w * 0.12, spacing: 1.5, radius: 0)
            Rectangle().fill(tokens.rule).frame(height: 0.8)
        }
    }

    private func horizon(_ w: CGFloat) -> some View {
        HStack(alignment: .top, spacing: w * 0.08) {
            VStack(spacing: 0) {
                ForEach([0xAAB8CC, 0x7FB8FF, 0x4F8FF7, 0x7FB8FF, 0x4A4F7E, 0x2E3C78, 0x1B2552], id: \.self) { hex in
                    Palette.color(hex: UInt32(hex)).frame(height: w * 0.12)
                }
            }
            .frame(width: w * 0.06)
            .clipShape(Capsule())
            VStack(alignment: .leading, spacing: w * 0.04) {
                Text("64°")
                    .font(tokens.display.font(w * 0.28, fixed: true))
                    .foregroundStyle(tokens.ink)
                MiniCurve(vertical: true)
                    .stroke(tokens.ink, lineWidth: 1.2)
                    .frame(height: w * 0.5)
            }
        }
    }

    private func chroma(_ w: CGFloat) -> some View {
        VStack(spacing: w * 0.05) {
            VStack(alignment: .leading, spacing: 0) {
                Text("64°")
                    .font(tokens.display.font(w * 0.3, fixed: true))
                    .foregroundStyle(ChromaPalette.cream)
                    .padding(.horizontal, w * 0.07)
                    .padding(.top, w * 0.04)
                Spacer(minLength: 0)
                RetroStripe(band: w * 0.03)
            }
            .frame(height: w * 0.52)
            .background(ChromaPalette.navy)
            .clipShape(RoundedRectangle(cornerRadius: w * 0.1, style: .continuous))
            RoundedRectangle(cornerRadius: w * 0.09, style: .continuous)
                .fill(ChromaPalette.cobalt)
                .overlay(bars(9, color: ChromaPalette.cream, height: w * 0.1).padding(w * 0.05), alignment: .bottom)
                .frame(height: w * 0.22)
            HStack(spacing: w * 0.03) {
                ForEach([ChromaPalette.mustard, ChromaPalette.green, ChromaPalette.navy], id: \.self) { color in
                    RoundedRectangle(cornerRadius: w * 0.06, style: .continuous).fill(color)
                }
            }
            .frame(height: w * 0.2)
        }
    }
}

/// A small wavy line for previews.
private struct MiniCurve: Shape {
    var vertical = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGFloat] = [0.9, 0.85, 0.6, 0.3, 0.15, 0.3, 0.5, 0.75, 0.9]
        for (index, value) in points.enumerated() {
            let t = CGFloat(index) / CGFloat(points.count - 1)
            let point = vertical
                ? CGPoint(x: rect.minX + value * rect.width, y: rect.minY + t * rect.height)
                : CGPoint(x: rect.minX + t * rect.width, y: rect.minY + value * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
