import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("DeviceInfo", .tags(.unit)) struct DeviceInfoTests {
    private func makeSUT(environment: [String: String],
                         version: OperatingSystemVersion = OperatingSystemVersion(majorVersion: 27,
                                                                                  minorVersion: 0,
                                                                                  patchVersion: 1),
                         machine: String) -> DeviceInfo {
        DeviceInfo.current(environment: environment, operatingSystemVersion: version, machine: { machine })
    }

    @Test("On a simulator the model comes from SIMULATOR_MODEL_IDENTIFIER, not the host's arm64")
    func simulatorBranch() {
        let info = makeSUT(environment: ["SIMULATOR_MODEL_IDENTIFIER": "iPhone17,1"], machine: "arm64")

        #expect(info.modelIdentifier == "iPhone17,1")
    }

    @Test("On a device the model is the hardware machine identifier") func deviceBranch() {
        let info = makeSUT(environment: [:], machine: "iPhone16,2")

        #expect(info.modelIdentifier == "iPhone16,2")
    }

    @Test("The OS is iOS with a major.minor.patch version") func osFacts() {
        let info = makeSUT(environment: [:], machine: "iPhone16,2")
        let older = makeSUT(environment: [:],
                            version: OperatingSystemVersion(majorVersion: 18, minorVersion: 4, patchVersion: 0),
                            machine: "iPhone16,2")

        #expect(info.osName == "iOS")
        #expect(info.osVersion == "27.0.1")
        #expect(older.osVersion == "18.4.0")
    }

    @Test("The hardware machine is a non-empty string without NUL terminators") func hardwareMachine() {
        let machine = DeviceInfo.hardwareMachine()

        #expect(!machine.isEmpty)
        #expect(!machine.contains("\0"))
    }
}
