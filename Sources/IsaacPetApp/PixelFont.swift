import AppKit
import CoreText

/// Loads the bundled Fusion Pixel font (SIL OFL 1.1) for the game-style UI.
/// The TTF ships in the bundle's Fonts folder and is registered per process on
/// first use; Menlo stays as the fallback so text keeps working if that fails.
@MainActor
enum PixelFont {
    /// Speech text renders at 12pt — the font's native 12px design grid, which keeps
    /// every glyph pixel-aligned on Retina instead of interpolating it.
    static let speechSize: CGFloat = 12
    /// Headings render at 24pt — an exact 2x of the design grid.
    static let titleSize: CGFloat = 24

    private static let resource = "fusion-pixel-12px-proportional-zh_hans"
    private static var registration: RegistrationState = .notAttempted
    private static var cachedFonts: [CGFloat: NSFont] = [:]

    private enum RegistrationState: Equatable {
        case notAttempted
        case succeeded(postScriptName: String?)
        case failed
    }

    static var speech: NSFont { font(ofSize: speechSize) }
    static var title: NSFont { font(ofSize: titleSize) }

    static func font(ofSize size: CGFloat) -> NSFont {
        if let cached = cachedFonts[size] { return cached }
        let font = resolveFont(ofSize: size)
        cachedFonts[size] = font
        return font
    }

    private static func resolveFont(ofSize size: CGFloat) -> NSFont {
        if registration == .notAttempted {
            registration = registerBundledFont()
        }
        if case let .succeeded(postScriptName) = registration,
           let name = postScriptName,
           let font = NSFont(name: name, size: size) {
            return font
        }
        return NSFont(name: "Menlo-Bold", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func registerBundledFont() -> RegistrationState {
        guard let url = Bundle.main.url(
            forResource: resource,
            withExtension: "ttf",
            subdirectory: "Fonts"
        ) else {
            return .failed
        }
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) else {
            return .failed
        }
        let descriptors = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as NSArray?) as? [CTFontDescriptor]
        let postScriptName = descriptors?.compactMap { descriptor in
            CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        }.first
        return .succeeded(postScriptName: postScriptName)
    }
}
