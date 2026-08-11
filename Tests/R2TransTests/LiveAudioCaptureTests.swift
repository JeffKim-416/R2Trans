import Foundation
import XCTest
@testable import R2Trans

final class LiveAudioCaptureTests: XCTestCase {
    func testMixerCombinesConcurrentSourcesOnOneFrame() {
        let microphone = pcmData([1_000, -1_000, 20_000])
        let systemAudio = pcmData([500, -500, 20_000])

        let mixed = PCM16AudioMixer.mix(
            microphone: microphone,
            systemAudio: systemAudio,
            frameSampleCount: 3
        )

        XCTAssertEqual(pcmSamples(mixed), [1_500, -1_500, Int16.max])
    }

    func testMixerPreservesAvailableSourceAndPadsSilence() {
        let microphone = pcmData([123, -456])

        let mixed = PCM16AudioMixer.mix(
            microphone: microphone,
            systemAudio: Data(),
            frameSampleCount: 4
        )

        XCTAssertEqual(pcmSamples(mixed), [123, -456, 0, 0])
    }

    func testMixerSaturatesNegativeOverflow() {
        let mixed = PCM16AudioMixer.mix(
            microphone: pcmData([-20_000]),
            systemAudio: pcmData([-20_000]),
            frameSampleCount: 1
        )

        XCTAssertEqual(pcmSamples(mixed), [Int16.min])
    }

    private func pcmData(_ samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }

    private func pcmSamples(_ data: Data) -> [Int16] {
        data.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Int16.self))
        }
    }
}
