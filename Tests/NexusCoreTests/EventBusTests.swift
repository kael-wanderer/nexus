import Foundation
import Testing

@testable import NexusCore

@Suite("EventBus")
struct EventBusTests {
    @Test("A subscriber receives published events")
    func delivery() async {
        let bus = EventBus()
        let stream = bus.events()
        bus.publish(.displaysChanged)
        bus.publish(.applicationsChanged)

        var received: [NexusEvent] = []
        for await event in stream {
            received.append(event)
            if received.count == 2 { break }
        }
        #expect(received == [.displaysChanged, .applicationsChanged])
    }

    @Test("Every subscriber gets its own copy")
    func multicast() async {
        let bus = EventBus()
        let first = bus.events()
        let second = bus.events()
        #expect(bus.subscriberCount == 2)
        bus.publish(.displaysChanged)

        var iterator = first.makeAsyncIterator()
        var otherIterator = second.makeAsyncIterator()
        #expect(await iterator.next() == .displaysChanged)
        #expect(await otherIterator.next() == .displaysChanged)
    }

    @Test("A slow subscriber drops old events instead of back-pressuring the producer")
    func dropsWhenFull() async {
        let bus = EventBus()
        let stream = bus.events()
        for _ in 0..<200 { bus.publish(.displaysChanged) }
        bus.publish(.applicationsChanged)

        var count = 0
        var last: NexusEvent?
        for await event in stream {
            count += 1
            last = event
            if event == .applicationsChanged { break }
        }
        #expect(count <= 64)
        #expect(last == .applicationsChanged)
    }

    @Test("finishAll terminates live streams")
    func finish() async {
        let bus = EventBus()
        let stream = bus.events()
        bus.finishAll()
        var count = 0
        for await _ in stream { count += 1 }
        #expect(count == 0)
        #expect(bus.subscriberCount == 0)
    }
}
