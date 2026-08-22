import Testing

@testable import NexusUI

@Suite("Design")
struct DesignTests {
    @Test("Reduce Motion suppresses animation at the call site")
    func reduceMotion() {
        #expect(Design.animation(Design.reveal, reduceMotion: true) == nil)
        #expect(Design.animation(Design.reveal, reduceMotion: false) != nil)
    }
}
