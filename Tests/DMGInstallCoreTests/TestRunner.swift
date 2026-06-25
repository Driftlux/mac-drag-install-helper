@main
enum TestRunner {
    static func main() async throws {
        let payloadTests = PayloadLocatorTests()
        try payloadTests.findsSingleAppPayload()
        try payloadTests.findsSinglePkgPayload()
        try payloadTests.prefersAppOverPkgAndChoosesDeterministically()
        try payloadTests.returnsNilWhenNoPayloadExists()

        let installerTests = DMGInstallerTests()
        try await installerTests.rejectsNonDMGFiles()
        try await installerTests.reportsMountFailure()
        try await installerTests.copiesAppPayloadAndRunsQuarantineRemoval()
        try await installerTests.asksBeforeReplacingExistingApp()
        try await installerTests.keepsBothWhenExistingAppConflicts()
        try await installerTests.reportsPkgInstallFailure()

        print("All 10 DMGInstallCore tests passed.")
    }
}
