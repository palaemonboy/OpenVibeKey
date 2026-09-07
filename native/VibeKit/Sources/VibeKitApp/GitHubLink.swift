import SwiftUI

/// 项目入口；矢量图标跟随按钮前景色适配浅色与深色主题。
struct GitHubLink: View {
    @ObservedObject private var language = AppLanguage.shared
    private let repositoryURL = URL(string: "https://github.com/palaemonboy/OpenVibeKey")!

    var body: some View {
        Link(destination: repositoryURL) {
            GitHubMark()
                .fill(.primary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(GhostButtonStyle())
        .help(L("在 GitHub 上查看 OpenVibeKey"))
        .accessibilityLabel(L("打开 OpenVibeKey 的 GitHub 仓库"))
    }
}

private struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        // GitHub mark 的 24 × 24 坐标路径。
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 0))
        path.addCurve(to: CGPoint(x: 0, y: 12), control1: CGPoint(x: 5.37, y: 0), control2: CGPoint(x: 0, y: 5.37))
        path.addCurve(to: CGPoint(x: 8.205, y: 23.385), control1: CGPoint(x: 0, y: 17.31), control2: CGPoint(x: 3.435, y: 21.795))
        path.addCurve(to: CGPoint(x: 9.025, y: 22.81), control1: CGPoint(x: 8.805, y: 23.49), control2: CGPoint(x: 9.025, y: 23.13))
        path.addLine(to: CGPoint(x: 9.01, y: 20.575))
        path.addCurve(to: CGPoint(x: 4.97, y: 18.98), control1: CGPoint(x: 5.672, y: 21.3), control2: CGPoint(x: 4.968, y: 18.965))
        path.addCurve(to: CGPoint(x: 3.635, y: 17.225), control1: CGPoint(x: 4.43, y: 17.61), control2: CGPoint(x: 3.635, y: 17.245))
        path.addCurve(to: CGPoint(x: 3.72, y: 16.495), control1: CGPoint(x: 2.545, y: 16.48), control2: CGPoint(x: 3.72, y: 16.495))
        path.addCurve(to: CGPoint(x: 5.56, y: 17.73), control1: CGPoint(x: 4.925, y: 16.58), control2: CGPoint(x: 5.56, y: 17.73))
        path.addCurve(to: CGPoint(x: 9.05, y: 19.095), control1: CGPoint(x: 6.63, y: 19.565), control2: CGPoint(x: 8.37, y: 19.035))
        path.addCurve(to: CGPoint(x: 9.81, y: 17.49), control1: CGPoint(x: 9.16, y: 18.32), control2: CGPoint(x: 9.47, y: 17.79))
        path.addCurve(to: CGPoint(x: 4.345, y: 11.56), control1: CGPoint(x: 7.145, y: 17.19), control2: CGPoint(x: 4.345, y: 16.155))
        path.addCurve(to: CGPoint(x: 5.58, y: 8.34), control1: CGPoint(x: 4.345, y: 10.25), control2: CGPoint(x: 4.81, y: 9.18))
        path.addCurve(to: CGPoint(x: 5.695, y: 5.165), control1: CGPoint(x: 5.46, y: 8.035), control2: CGPoint(x: 5.045, y: 6.81))
        path.addCurve(to: CGPoint(x: 8.995, y: 6.395), control1: CGPoint(x: 5.695, y: 5.165), control2: CGPoint(x: 6.7, y: 4.845))
        path.addCurve(to: CGPoint(x: 12, y: 5.99), control1: CGPoint(x: 9.955, y: 6.128), control2: CGPoint(x: 10.98, y: 5.995))
        path.addCurve(to: CGPoint(x: 15.005, y: 6.395), control1: CGPoint(x: 13.02, y: 5.995), control2: CGPoint(x: 14.045, y: 6.128))
        path.addCurve(to: CGPoint(x: 18.305, y: 5.165), control1: CGPoint(x: 17.3, y: 4.845), control2: CGPoint(x: 18.305, y: 5.165))
        path.addCurve(to: CGPoint(x: 18.42, y: 8.34), control1: CGPoint(x: 18.955, y: 6.81), control2: CGPoint(x: 18.54, y: 8.035))
        path.addCurve(to: CGPoint(x: 19.655, y: 11.56), control1: CGPoint(x: 19.19, y: 9.18), control2: CGPoint(x: 19.655, y: 10.25))
        path.addCurve(to: CGPoint(x: 14.175, y: 17.485), control1: CGPoint(x: 19.655, y: 16.17), control2: CGPoint(x: 16.85, y: 17.18))
        path.addCurve(to: CGPoint(x: 14.99, y: 19.705), control1: CGPoint(x: 14.605, y: 17.855), control2: CGPoint(x: 14.99, y: 18.585))
        path.addLine(to: CGPoint(x: 14.975, y: 22.81))
        path.addCurve(to: CGPoint(x: 15.8, y: 23.385), control1: CGPoint(x: 14.975, y: 23.13), control2: CGPoint(x: 15.19, y: 23.495))
        path.addCurve(to: CGPoint(x: 24, y: 12), control1: CGPoint(x: 20.565, y: 21.79), control2: CGPoint(x: 24, y: 17.31))
        path.addCurve(to: CGPoint(x: 12, y: 0), control1: CGPoint(x: 24, y: 5.37), control2: CGPoint(x: 18.63, y: 0))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
