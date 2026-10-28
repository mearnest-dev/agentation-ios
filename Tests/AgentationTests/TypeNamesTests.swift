import XCTest
@testable import Agentation

final class TypeNamesTests: XCTestCase {
    func testHostedRootNameUnwrapsModifiedContent() {
        let name = "UIHostingController<ModifiedContent<CheckoutView, _EnvironmentKeyWritingModifier<Optional<Store>>>>"
        XCTAssertEqual(TypeNames.hostedRootName(name), "CheckoutView")
    }

    func testHostedRootNameForPlainRoot() {
        XCTAssertEqual(TypeNames.hostedRootName("UIHostingController<ContentView>"), "ContentView")
        XCTAssertEqual(TypeNames.hostedRootName("_UIHostingView<SwiftUI.AnyView>"), "AnyView")
    }

    func testHostedRootNameIgnoresOtherTypes() {
        XCTAssertNil(TypeNames.hostedRootName("CheckoutViewController"))
        XCTAssertNil(TypeNames.hostedRootName("Array<Int>"))
    }

    func testUninformativeRoots() {
        XCTAssertTrue(TypeNames.isUninformative("AnyView"))
        XCTAssertTrue(TypeNames.isUninformative("_VariadicView_Children"))
        XCTAssertFalse(TypeNames.isUninformative("CheckoutView"))
    }

    func testShortTypeName() {
        XCTAssertEqual(
            TypeNames.shortTypeName("_UIHostingView<ModifiedContent<CheckoutView, _PaddingLayout>>"),
            "UIHostingView<CheckoutView>")
        XCTAssertEqual(TypeNames.shortTypeName("MyApp.SettingsViewController"), "SettingsViewController")
    }

    func testGenericArgumentsRespectNesting() {
        let parsed = TypeNames.genericArguments(of: "Pair<A<B, C>, D>")
        XCTAssertEqual(parsed?.base, "Pair")
        XCTAssertEqual(parsed?.args, ["A<B, C>", "D"])
    }
}
