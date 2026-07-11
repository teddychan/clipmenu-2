import Testing
import SwiftUI
import ViewInspector
@testable import ClipMenu

// Smoke test: confirms the ViewInspector test dependency builds and inspects a
// SwiftUI view tree under this toolchain (Swift 6.2 / macOS 26). If this fails to
// compile or run, the SwiftUI-body coverage plan is not viable as-is.
@MainActor
@Suite struct ViewInspectorSmokeTests {

    private struct Sample: View {
        let label: String
        var body: some View {
            VStack {
                Text(label)
                Button("Tap") {}
            }
        }
    }

    @Test func inspectsTextAndButton() throws {
        let view = Sample(label: "hello")
        let text = try view.inspect().vStack().text(0).string()
        #expect(text == "hello")
        let button = try view.inspect().vStack().button(1).labelView().text().string()
        #expect(button == "Tap")
    }
}
