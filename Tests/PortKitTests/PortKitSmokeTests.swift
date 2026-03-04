import Testing
@testable import PortKit

@Test func portKitReturnsHelloMessage() {
    #expect(PortKit().hello() == "Hello from PortKit")
}
