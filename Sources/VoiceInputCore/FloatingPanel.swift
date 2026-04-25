import AppKit

public final class FloatingTranscriptionPanel: NSPanel {
    private let waveform = WaveformView(frame: NSRect(x: 0, y: 0, width: 44, height: 32))
    private let label = NSTextField(labelWithString: "Listening…")
    private var widthConstraint: NSLayoutConstraint?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hasShadow = true
        ignoresMouseEvents = true
        setupUI()
    }

    private func setupUI() {
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 28
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [waveform, label])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingHead
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = label.widthAnchor.constraint(equalToConstant: 160)
        widthConstraint?.isActive = true

        contentView = NSView()
        contentView?.addSubview(blur)
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            blur.topAnchor.constraint(equalTo: contentView!.topAnchor),
            blur.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.topAnchor.constraint(equalTo: blur.topAnchor),
            stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 44),
            waveform.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    public func show(text: String = "Listening…") {
        updateText(text)
        positionAtBottomCenter()
        alphaValue = 0
        setFrame(frame.insetBy(dx: 24, dy: 6), display: true)
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
            self.animator().setFrame(self.targetFrame(), display: true)
        }
    }

    public func hideAnimated() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
            self.animator().setFrame(self.frame.insetBy(dx: 18, dy: 5), display: true)
        } completionHandler: {
            self.orderOut(nil)
        }
    }

    public func updateText(_ text: String) {
        label.stringValue = text.isEmpty ? "Listening…" : text
        let measured = min(560, max(160, (text as NSString).size(withAttributes: [.font: label.font as Any]).width + 8))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            widthConstraint?.animator().constant = measured
            layoutIfNeeded()
        }
        setFrame(targetFrame(labelWidth: measured), display: true, animate: true)
    }

    public func updateRMS(_ rms: Float) {
        waveform.update(level: CGFloat(rms))
    }

    private func positionAtBottomCenter() {
        setFrame(targetFrame(), display: true)
    }

    private func targetFrame(labelWidth: CGFloat? = nil) -> NSRect {
        let lw = labelWidth ?? widthConstraint?.constant ?? 160
        let w = 18 + 44 + 12 + lw + 18
        let h: CGFloat = 56
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return NSRect(x: screen.midX - w / 2, y: screen.minY + 42, width: w, height: h)
    }
}

public final class WaveformView: NSView {
    private var displayed: CGFloat = 0.05
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]

    public func update(level: CGFloat) {
        let clamped = min(1, max(0.03, level))
        let attack: CGFloat = 0.40
        let release: CGFloat = 0.15
        displayed += (clamped - displayed) * (clamped > displayed ? attack : release)
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.92).setFill()
        let barWidth: CGFloat = 5
        let gap: CGFloat = 4
        let total = CGFloat(weights.count) * barWidth + CGFloat(weights.count - 1) * gap
        let startX = (bounds.width - total) / 2
        for (idx, weight) in weights.enumerated() {
            let jitter = CGFloat.random(in: -0.04...0.04)
            let normalized = min(1, max(0.08, displayed * weight + jitter))
            let height = max(8, normalized * bounds.height)
            let x = startX + CGFloat(idx) * (barWidth + gap)
            let rect = NSRect(x: x, y: bounds.midY - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth/2, yRadius: barWidth/2).fill()
        }
    }
}
