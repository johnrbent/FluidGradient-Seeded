//
//  FluidGradientView.swift
//  FluidGradientView
//
//  Created by Oskar Groth on 2021-12-23.
//

import SwiftUI
import Combine
import GameKit
 
#if os(OSX)
import AppKit
public typealias SystemColor = NSColor
public typealias SystemView = NSView
#else
import UIKit
public typealias SystemColor = UIColor
public typealias SystemView = UIView
#endif

/// A system view that presents an animated gradient with ``CoreAnimation``
public class FluidGradientView: SystemView {
    var speed: CGFloat
    
    let baseLayer = ResizableLayer()
    let highlightLayer = ResizableLayer()
    let rng = GKMersenneTwisterRandomSource()
    var cancellables = Set<AnyCancellable>()
    
    weak var delegate: FluidGradientDelegate?
    
    init(blobs: [Color] = [],
         highlights: [Color] = [],
         speed: CGFloat = 1.0,
         seed: UInt64 = 0
        ) {
        self.speed = speed
        super.init(frame: .zero)
        rng.seed = seed
     
        if let compositingFilter = CIFilter(name: "CIOverlayBlendMode") {
            highlightLayer.compositingFilter = compositingFilter
        }
        
        #if os(OSX)
        layer = ResizableLayer()
        
        wantsLayer = true
        postsFrameChangedNotifications = true
        
        layer?.delegate = self
        baseLayer.delegate = self
        highlightLayer.delegate = self
        
        self.layer?.addSublayer(baseLayer)
        self.layer?.addSublayer(highlightLayer)
        #else
        self.layer.addSublayer(baseLayer)
        self.layer.addSublayer(highlightLayer)
        #endif
        
        create(blobs, layer: baseLayer)
        create(highlights, layer: highlightLayer)
        DispatchQueue.main.async {
            self.update(speed: speed)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Create blobs and add to specified layer
    public func create(_ colors: [Color], layer: CALayer) {
        // Remove blobs at the end if colors are removed
        let count = layer.sublayers?.count ?? 0
        let removeCount = count - colors.count
        if removeCount > 0 {
            layer.sublayers?.removeLast(removeCount)
        }
        
        for (index, color) in colors.enumerated() {
            if index < count {
                if let existing = layer.sublayers?[index] as? BlobLayer {
                    existing.set(color: color)
                }
            } else {
                layer.addSublayer(BlobLayer(color: color, rng: rng))
            }
        }
    }
    
    /// Update sublayers and set speed and blur levels
    public func update(speed: CGFloat) {
        cancellables.removeAll()
        self.speed = speed
        guard speed > 0 else { return }
        
        let layers = (baseLayer.sublayers ?? []) + (highlightLayer.sublayers ?? [])
        for layer in layers {
            if let layer = layer as? BlobLayer {
                let rd = GKRandomDistribution(randomSource: rng, lowestValue: 80, highestValue: 120)
                let randomValue = rd.nextUniform()
                let publishInterval = TimeInterval(randomValue / Float(speed * 10))
                Timer.publish(every: publishInterval,
                              on: .main,
                              in: .common)
                    .autoconnect()
                    .sink { _ in
                        #if os(OSX)
                        let visible = self.window?.occlusionState.contains(.visible)
                        guard visible == true else { return }
                        #endif
                        layer.animate(speed: speed)
                    }
                    .store(in: &cancellables)
            }
        }
    }
    
    /// Compute and update new blur value
    private func updateBlur() {
        delegate?.updateBlur(min(frame.width, frame.height))
    }
    
    /// Functional methods
    #if os(OSX)
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        baseLayer.contentsScale = scale
        highlightLayer.contentsScale = scale
        
        updateBlur()
    }
    
    public override func resize(withOldSuperviewSize oldSize: NSSize) {
        updateBlur()
    }
    #else
    public override func layoutSubviews() {
        layer.frame = self.bounds
        baseLayer.frame = self.bounds
        highlightLayer.frame = self.bounds
        
        updateBlur()
    }
    #endif
}

protocol FluidGradientDelegate: AnyObject {
    func updateBlur(_ value: CGFloat)
}

#if os(OSX)
extension FluidGradientView: CALayerDelegate, NSViewLayerContentScaleDelegate {
    public func layer(_ layer: CALayer,
                      shouldInheritContentsScale newScale: CGFloat,
                      from window: NSWindow) -> Bool {
        return true
    }
}
#endif
