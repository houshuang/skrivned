import AppKit

class FloatingIndicator {
    private var window: NSWindow?
    private var panelView: TranscriptionPanelView?
    private var pulseTimer: Timer?
    private var pulseAlpha: CGFloat = 1.0
    private var pulseDirection: CGFloat = -1.0
    private var isCollapsed = false
    var onClose: (() -> Void)?

    private let panelBottomPadding: CGFloat = 80
    private let collapsedSize: CGFloat = 28

    func show(color: NSColor = .systemRed) {
        DispatchQueue.main.async { [self] in
            if window != nil {
                panelView?.indicatorColor = color
                panelView?.setText(final: "", tentative: "")
                panelView?.needsDisplay = true
                return
            }
            guard let screen = NSScreen.main else { return }

            let panelWidth: CGFloat = min(600, screen.frame.width * 0.5)
            let panelHeight: CGFloat = 48

            let origin = NSPoint(
                x: screen.frame.midX - panelWidth / 2,
                y: screen.frame.minY + panelBottomPadding
            )

            let win = NSWindow(
                contentRect: NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating
            win.collectionBehavior = [.canJoinAllSpaces, .stationary]
            win.ignoresMouseEvents = false
            win.hasShadow = true
            win.isReleasedWhenClosed = false

            let view = TranscriptionPanelView(
                frame: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight))
            )
            view.indicatorColor = color
            view.onClicked = { [weak self] in self?.toggleCollapse() }
            view.onClose = { [weak self] in self?.onClose?() }
            win.contentView = view
            win.orderFrontRegardless()

            self.window = win
            self.panelView = view
            self.isCollapsed = false
            startPulse()
        }
    }

    func updateText(final finalText: String, tentative: String) {
        DispatchQueue.main.async { [self] in
            guard let view = panelView, let win = window else { return }
            view.setText(final: finalText, tentative: tentative)
            if !isCollapsed {
                resizeToFit(window: win, view: view)
            }
        }
    }

    func showProcessing() {
        DispatchQueue.main.async { [self] in
            panelView?.showProcessing = true
            panelView?.indicatorColor = .systemYellow
            panelView?.needsDisplay = true
        }
    }

    func changeColor(_ color: NSColor) {
        DispatchQueue.main.async { [self] in
            panelView?.indicatorColor = color
            panelView?.needsDisplay = true
        }
    }

    func hide() {
        DispatchQueue.main.async { [self] in
            pulseTimer?.invalidate()
            pulseTimer = nil
            window?.close()
            window = nil
            panelView = nil
        }
    }

    private func toggleCollapse() {
        guard let win = window, let view = panelView else { return }
        isCollapsed.toggle()
        view.isCollapsed = isCollapsed

        guard let screen = NSScreen.main else { return }

        if isCollapsed {
            let origin = NSPoint(
                x: screen.frame.midX - collapsedSize / 2,
                y: screen.frame.minY + panelBottomPadding
            )
            win.setFrame(
                NSRect(origin: origin, size: NSSize(width: collapsedSize, height: collapsedSize)),
                display: true
            )
        } else {
            let panelWidth: CGFloat = min(600, screen.frame.width * 0.5)
            resizeToFit(window: win, view: view, panelWidth: panelWidth)
        }
    }

    private func resizeToFit(window: NSWindow, view: TranscriptionPanelView, panelWidth: CGFloat? = nil) {
        guard let screen = NSScreen.main else { return }
        let width = panelWidth ?? window.frame.width
        let needed = view.desiredHeight()
        let clamped = min(max(needed, 48), 300)

        if abs(window.frame.height - clamped) > 1 || abs(window.frame.width - width) > 1 {
            let origin = NSPoint(
                x: screen.frame.midX - width / 2,
                y: screen.frame.minY + panelBottomPadding
            )
            window.setFrame(
                NSRect(origin: origin, size: NSSize(width: width, height: clamped)),
                display: true
            )
        }
    }

    private func startPulse() {
        pulseAlpha = 1.0
        pulseDirection = -1.0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let view = self.panelView else { return }
            self.pulseAlpha += self.pulseDirection * 0.015
            if self.pulseAlpha <= 0.3 {
                self.pulseDirection = 1.0
            } else if self.pulseAlpha >= 1.0 {
                self.pulseDirection = -1.0
            }
            view.indicatorAlpha = self.pulseAlpha
            view.needsDisplay = true
        }
    }
}

private class TranscriptionPanelView: NSView {
    var indicatorColor: NSColor = .systemRed
    var indicatorAlpha: CGFloat = 1.0
    var showProcessing = false
    var isCollapsed = false
    var onClicked: (() -> Void)?
    var onClose: (() -> Void)?

    private var finalText = ""
    private var tentativeText = ""

    private let padding: CGFloat = 14
    private let dotSize: CGFloat = 10
    private let dotTextGap: CGFloat = 10
    private let fontSize: CGFloat = 14

    func setText(final: String, tentative: String) {
        finalText = final
        tentativeText = tentative
        showProcessing = false
        needsDisplay = true
    }

    private var closeButtonRect: NSRect {
        let size: CGFloat = 24
        return NSRect(x: bounds.width - size - 6, y: bounds.height - size - 6, width: size, height: size)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !isCollapsed && closeButtonRect.contains(point) {
            onClose?()
        } else {
            onClicked?()
        }
    }

    func desiredHeight() -> CGFloat {
        let textWidth = bounds.width - padding * 2 - dotSize - dotTextGap - 30
        guard textWidth > 0 else { return 48 }

        let displayText = combinedDisplayText()
        if displayText.isEmpty { return 48 }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize)
        ]
        let boundingRect = (displayText as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return max(48, boundingRect.height + padding * 2)
    }

    private func combinedDisplayText() -> String {
        if showProcessing { return "Processing..." }
        var text = finalText
        if !tentativeText.isEmpty {
            text += tentativeText
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        if isCollapsed {
            // Collapsed: small circular background with centered dot
            let bgPath = NSBezierPath(ovalIn: bounds)
            NSColor.black.withAlphaComponent(0.82).setFill()
            bgPath.fill()

            let dotRect = NSRect(
                x: (bounds.width - dotSize) / 2,
                y: (bounds.height - dotSize) / 2,
                width: dotSize,
                height: dotSize
            )
            let dotPath = NSBezierPath(ovalIn: dotRect)
            ctx.setShadow(
                offset: .zero,
                blur: 8,
                color: indicatorColor.withAlphaComponent(indicatorAlpha * 0.6).cgColor
            )
            indicatorColor.withAlphaComponent(indicatorAlpha).setFill()
            dotPath.fill()
            return
        }

        // Background: rounded dark translucent rect
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.82).setFill()
        bgPath.fill()

        // Pulsing indicator dot
        let dotY = bounds.height - padding - dotSize
        let dotRect = NSRect(x: padding, y: dotY, width: dotSize, height: dotSize)
        let dotPath = NSBezierPath(ovalIn: dotRect)

        ctx.setShadow(
            offset: .zero,
            blur: 8,
            color: indicatorColor.withAlphaComponent(indicatorAlpha * 0.6).cgColor
        )
        indicatorColor.withAlphaComponent(indicatorAlpha).setFill()
        dotPath.fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        // Text
        let displayText = combinedDisplayText()
        guard !displayText.isEmpty else { return }

        let textX = padding + dotSize + dotTextGap
        let textWidth = bounds.width - textX - padding - 30

        // Build attributed string: final text white, tentative gray
        let attributed = NSMutableAttributedString()
        let trimmedFinal = finalText.trimmingCharacters(in: .init(charactersIn: " "))

        if !trimmedFinal.isEmpty {
            attributed.append(NSAttributedString(string: trimmedFinal, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.white,
            ]))
        }
        if !tentativeText.isEmpty && !showProcessing {
            attributed.append(NSAttributedString(string: tentativeText, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.white.withAlphaComponent(0.45),
            ]))
        }
        if showProcessing {
            attributed.append(NSAttributedString(string: "Processing...", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.systemYellow.withAlphaComponent(0.9),
            ]))
        }

        let textRect = NSRect(x: textX, y: padding - 2, width: textWidth, height: bounds.height - padding * 2 + 4)
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        // Close button (×)
        let cbRect = closeButtonRect
        let xInset: CGFloat = 7
        let xPath = NSBezierPath()
        xPath.move(to: NSPoint(x: cbRect.minX + xInset, y: cbRect.minY + xInset))
        xPath.line(to: NSPoint(x: cbRect.maxX - xInset, y: cbRect.maxY - xInset))
        xPath.move(to: NSPoint(x: cbRect.maxX - xInset, y: cbRect.minY + xInset))
        xPath.line(to: NSPoint(x: cbRect.minX + xInset, y: cbRect.maxY - xInset))
        xPath.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.5).setStroke()
        xPath.stroke()
    }
}
