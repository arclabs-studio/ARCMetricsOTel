import Foundation

/// The device facts that go on the Resource.
struct DeviceInfo: Equatable {
    /// `os.name`.
    let osName: String

    /// `os.version`, as `major.minor.patch`.
    let osVersion: String

    /// `device.model.identifier`, for example `iPhone17,1`.
    let modelIdentifier: String

    /// The running device.
    ///
    /// - Parameters:
    ///   - environment: The process environment. On a simulator its `SIMULATOR_MODEL_IDENTIFIER`
    ///     names the simulated device, because the hardware identifier is the host's (`arm64`).
    ///   - operatingSystemVersion: The OS version.
    ///   - machine: The hardware identifier (`utsname.machine`).
    static func current(environment: [String: String],
                        operatingSystemVersion version: OperatingSystemVersion,
                        machine: () -> String) -> DeviceInfo {
        DeviceInfo(osName: "iOS",
                   osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                   modelIdentifier: environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine())
    }

    /// `utsname.machine`.
    static func hardwareMachine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            // The machine id is ASCII; repairing decoding never fails, so there is no nil branch to handle.
            // swiftlint:disable:next optional_data_string_conversion
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
