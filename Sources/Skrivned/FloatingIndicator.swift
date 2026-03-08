import AppKit

class FloatingIndicator {
    private var window: NSWindow?
    private var orbView: OrbView?
    private var pulseTimer: Timer?
    private var pulseAlpha: CGFloat = 1.0
    private var pulseDirection: CGFloat = -1.0

    func show(color: NSColor = .systemRed) {
        if window != nil {
            // Already showing — just change color
            changeColor(color)
            return
        }
        guard let screen = NSScreen.main else { return }

        let orbSize: CGFloat = 18
        let windowSize: CGFloat = 44
        let padding: CGFloat = 10

        let screenFrame = screen.frame
        let origin = NSPoint(
            x: screenFrame.maxX - windowSize - padding,
            y: screenFrame.maxY - windowSize - padding
        )

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: windowSize, height: windowSize)),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.isReleasedWhenClosed = false

        let view = OrbView(frame: NSRect(x: 0, y: 0, width: windowSize, height: windowSize))
        view.orbSize = orbSize
        view.orbColor = color
        win.contentView = view
        win.orderFrontRegardless()

        self.window = win
        self.orbView = view
        startPulse()
    }

    func changeColor(_ color: NSColor) {
        orbView?.orbColor = color
        orbView?.needsDisplay = true
    }

    func hide() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        window?.close()
        window = nil
        orbView = nil
    }

    private func startPulse() {
        pulseAlpha = 1.0
        pulseDirection = -1.0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let orbView = self.orbView else { return }
            self.pulseAlpha += self.pulseDirection * 0.015
            if self.pulseAlpha <= 0.3 {
                self.pulseDirection = 1.0
            } else if self.pulseAlpha >= 1.0 {
                self.pulseDirection = -1.0
            }
            orbView.glowAlpha = self.pulseAlpha
            orbView.needsDisplay = true
        }
    }
}

private class OrbView: NSView {
    var glowAlpha: CGFloat = 1.0
    var orbSize: CGFloat = 18
    var orbColor: NSColor = .systemRed

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = orbSize / 2

        // Glow
        ctx.setShadow(
            offset: .zero,
            blur: 14,
            color: orbColor.withAlphaComponent(glowAlpha * 0.7).cgColor
        )

        // Orb
        ctx.setFillColor(orbColor.withAlphaComponent(glowAlpha).cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()
    }
}
