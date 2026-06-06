//
//  SlideGestureHandler.swift
//  Wurstfinger
//
//  Gesture handler for keys with slide behavior (space, delete).
//  Reports continuous drag deltas during the gesture, and classifies
//  taps/swipes at the end.
//

import SwiftUI

/// Phase of a slide gesture lifecycle.
enum SlidePhase {
    /// First drag movement detected beyond activation threshold.
    case began
    /// Continuous drag update with horizontal delta since last report.
    case changed(deltaX: CGFloat)
    /// Drag ended while sliding.
    case ended
    /// Drag ended without exceeding the slide activation threshold → tap.
    case tap
}

/// Gesture handler for keys with `slideType != .none`.
///
/// Unlike `KeyGestureRecognizer` (which classifies the full gesture at the
/// end), this modifier reports continuous drag deltas for cursor movement
/// and progressive deletion. If the drag never exceeds the activation
/// threshold, the gesture is classified as a tap.
struct SlideGestureHandler: ViewModifier {
    let slideType: SlideType
    let onSlide: (SlidePhase) -> Void
    let onGestureRecognized: (GestureClassification) -> Void
    let onTouchDown: () -> Void
    let aspectRatio: CGFloat
    @Binding var isActive: Bool

    @State private var positions = RingBuffer<CGPoint>(
        capacity: KeyboardConstants.Gesture.positionBufferSize
    )
    @State private var dragStarted = false
    @State private var isSliding = false
    @State private var lastTranslationX: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !dragStarted {
                            dragStarted = true
                            onTouchDown()
                        }

                        let currentX = value.translation.width
                        let point = CGPoint(
                            x: currentX,
                            y: value.translation.height
                        )
                        if positions.isEmpty {
                            positions.append(.zero)
                        }
                        positions.append(point)

                        if !isSliding {
                            let threshold = activationThreshold
                            if abs(currentX) >= threshold {
                                isSliding = true
                                isActive = true
                                lastTranslationX = currentX
                                onSlide(.began)
                                return
                            }
                        }

                        if isSliding {
                            let deltaX = currentX - lastTranslationX
                            lastTranslationX = currentX
                            onSlide(.changed(deltaX: deltaX))
                        }

                        isActive = true
                    }
                    .onEnded { value in
                        defer { reset() }
                        if isSliding {
                            onSlide(.ended)
                            positions.append(
                                CGPoint(
                                    x: value.translation.width,
                                    y: value.translation.height
                                )
                            )
                            let classification = KeyGestureRecognizer.classify(
                                positions: positions.elements,
                                aspectRatio: aspectRatio
                            )
                            if classification.isReturn {
                                onGestureRecognized(classification)
                            }
                        } else {
                            onSlide(.tap)
                        }
                    }
            )
    }

    private var activationThreshold: CGFloat {
        switch slideType {
        case .moveCursor:
            KeyboardConstants.SpaceGestures.dragActivationThreshold
        case .delete:
            KeyboardConstants.DeleteGestures.slideActivationThreshold
        case .none:
            .infinity
        }
    }

    private func reset() {
        positions.removeAll()
        dragStarted = false
        isSliding = false
        lastTranslationX = 0
        isActive = false
    }
}
