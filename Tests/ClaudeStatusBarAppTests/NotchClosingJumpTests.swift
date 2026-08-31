// Tests/ClaudeStatusBarAppTests/NotchClosingJumpTests.swift
import Testing
import CoreGraphics
@testable import ClaudeStatusBarApp

/// Reprodukce nahlášené vady: při zavírání panel na dva snímky uskočil doleva o svoji
/// vlastní šířku a zase zpátky.
///
/// Naměřeno z nahrávky (800px široký gif, top-center panel se třemi prstenci): v klidu i
/// otevřený má panel střed na 392,5 px, ale ve snímcích 41-42 a 76-78 sedí na 315,5 px —
/// tedy přesně na levém okraji *rozbaleného* okna. Příčina není v geometrii, ta je správně;
/// je v tom, s jakou velikostí okna se obsah rozloží. Zavírání má tři fáze a v té prostřední
/// je obsah už sbalený, ale okno ještě velké.
private let screen = ScreenMetrics(frame: CGRect(x: 0, y: 0, width: 3360, height: 1859),
                                   topInset: 0, auxiliaryTopLeftWidth: nil)

private struct Panel {
    let layout: NotchLayout
    let openWindowSize: CGSize
    let openFrame: CGRect
    let restingFrame: CGRect
    let ringCount: Int

    init(placement: NotchPlacement, ringCount: Int = 3, edgeOffsetPercent: Double = 50) {
        self.ringCount = ringCount
        layout = NotchGeometry.layout(for: screen, placement: placement,
                                      edgeOffsetPercent: edgeOffsetPercent,
                                      ringCount: ringCount, showRingsAtRest: true)
        openWindowSize = NotchMetrics.windowSize(placement: placement,
                                                 collapsed: layout.collapsed.size,
                                                 ringCount: ringCount,
                                                 notchClearance: layout.notchClearance)
        openFrame = layout.panelFrame(expandedSize: openWindowSize)
        restingFrame = NotchGeometry.collapsedWindowFrame(layout: layout,
                                                          expandedFrame: openFrame,
                                                          windowSize: openWindowSize)
    }

    /// Kde tvar leží na obrazovce v jedné fázi přechodu.
    func shapeOnScreen(expanded: Bool, windowIsOpen: Bool) -> CGRect {
        let windowSize = NotchWindowController.contentWindowSize(
            windowIsOpen: windowIsOpen, open: openWindowSize, resting: layout.collapsed.size)
        let frames = NotchGeometry.frames(layout: layout, expanded: expanded,
                                          ringCount: ringCount, popover: nil,
                                          windowSize: windowSize)
        let origin = windowIsOpen ? openFrame.origin : restingFrame.origin
        return frames.shape.offsetBy(dx: origin.x, dy: origin.y)
    }
}

// Tohle je ta vada: prostřední fáze zavírání musí nakreslit panel tam, kde skončí.
@Test func closingPanel_doesNotJumpSideways() {
    for placement in NotchPlacement.allCases {
        for rings in [1, 3, 6] {
            let p = Panel(placement: placement, ringCount: rings)
            let midClose = p.shapeOnScreen(expanded: false, windowIsOpen: true)
            let atRest = p.shapeOnScreen(expanded: false, windowIsOpen: false)
            #expect(midClose == atRest,
                    "\(placement), \(rings) prstenců: při zavírání \(midClose), v klidu \(atRest)")
        }
    }
}

// Velikost okna pro rozložení obsahu se řídí OKNEM, ne stavem panelu. Ty dva se během
// zavírání rozcházejí a právě to je ta vada.
@Test func contentWindowSize_followsTheWindow_notThePanelState() {
    let open = CGSize(width: 316, height: 460)
    let resting = CGSize(width: 106, height: 42)
    #expect(NotchWindowController.contentWindowSize(windowIsOpen: true,
                                                    open: open, resting: resting) == open)
    #expect(NotchWindowController.contentWindowSize(windowIsOpen: false,
                                                    open: open, resting: resting) == resting)
}

// Kotva na naměřenou hodnotu: špatné párování posadí panel na levý okraj velkého okna,
// tedy o jeho vlastní šířku vedle. Kdyby někdo tu vazbu vrátil zpět, tenhle test řekne
// i o kolik to uskočí.
@Test func theOldPairing_displacedThePanelByItsOwnWidth() {
    let p = Panel(placement: .topCenter, ringCount: 3)
    let broken = NotchGeometry.frames(layout: p.layout, expanded: false, ringCount: 3,
                                      popover: nil, windowSize: p.layout.collapsed.size)
        .shape.offsetBy(dx: p.openFrame.minX, dy: p.openFrame.minY)
    let correct = p.shapeOnScreen(expanded: false, windowIsOpen: false)
    #expect(broken != correct)
    // Naměřeno 77 px na 800px gifu; v bodech je to (316 - 106) / 2 = 105.
    #expect(abs(broken.minX - correct.minX)
            == (p.openWindowSize.width - p.layout.collapsed.width) / 2)
}

// Směr rozbalení: panel musí růst PRYČ od hrany, ke které je přilepený — dolů od horní,
// doprava od levé, doleva od pravé. Kdyby se přilepená hrana hnula, panel by se při
// otevírání odlepil od okraje obrazovky a vypadalo by to, že vyskočil.
@Test func panelGrowsAwayFromTheEdgeItIsFlushWith() {
    for placement in NotchPlacement.allCases {
        for rings in [1, 3, 6] {
            let p = Panel(placement: placement, ringCount: rings)
            func shape(expanded: Bool) -> CGRect {
                NotchGeometry.frames(layout: p.layout, expanded: expanded, ringCount: rings,
                                     popover: nil, windowSize: p.openWindowSize).shape
            }
            let rest = shape(expanded: false)
            let open = shape(expanded: true)
            // Kotva nevacuity: rozbalený panel opravdu musí být větší, jinak by rovnost
            // hran níž byla splněná triviálně.
            #expect(open.width > rest.width || open.height > rest.height)

            switch placement {
            case .topCenter:
                // CoreGraphics počítá y zdola, takže horní hrana je maxY.
                #expect(rest.maxY == open.maxY, "\(placement)/\(rings): horní hrana se hnula")
            case .leftEdge:
                #expect(rest.minX == open.minX, "\(placement)/\(rings): levá hrana se hnula")
            case .rightEdge:
                #expect(rest.maxX == open.maxX, "\(placement)/\(rings): pravá hrana se hnula")
            }
        }
    }
}
