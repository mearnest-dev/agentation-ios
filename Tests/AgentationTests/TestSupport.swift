import Foundation
@testable import Agentation

func makeAnnotation(
    id: String = "a1",
    comment: String = "corners should be 16",
    intent: Intent? = .style,
    timestamp: TimeInterval = 1_800_000_000,
    isArea: Bool = false
) -> Annotation {
    Annotation(
        id: id,
        comment: comment,
        intent: intent,
        timestamp: timestamp,
        screen: "CheckoutView",
        element: isArea ? "Area" : "Button",
        elementPath: "UIHostingController<CheckoutView> > PaymentSummaryCard > Button \"Pay $42.00\"",
        viewClass: nil,
        viewControllers: ["UIHostingController<CheckoutView>"],
        accessibilityIdentifier: isArea ? nil : "checkout.payButton",
        accessibilityLabel: isArea ? nil : "Pay $42.00",
        agentationTag: "PaymentSummaryCard",
        sourceLocation: "Demo/CheckoutView.swift:42",
        text: isArea ? nil : "Pay $42.00",
        nearbyText: ["Total", "$42.00"],
        containedTags: isArea ? ["ShippingOptions"] : [],
        style: nil,
        boundingBox: Rect(x: 16, y: 712, width: 361, height: 50),
        x: 50,
        y: 712,
        isArea: isArea,
        screenshotPath: "/tmp/agentation/annotation-a1.png",
        url: "ios-sim://dev.example.app/CheckoutView",
        serverId: nil
    )
}
