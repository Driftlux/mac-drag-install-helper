import DMGInstallCore

struct PayloadLocatorTests {
    func findsSingleAppPayload() throws {
        let volume = try TemporaryVolume()
        try volume.createDirectory("Example.app")

        let payload = try PayloadLocator().locatePayload(in: volume.url)

        try expect(payload == .app(volume.url.appending(path: "Example.app")))
    }

    func findsSinglePkgPayload() throws {
        let volume = try TemporaryVolume()
        try volume.createFile("Example.pkg")

        let payload = try PayloadLocator().locatePayload(in: volume.url)

        try expect(payload == .pkg(volume.url.appending(path: "Example.pkg")))
    }

    func prefersAppOverPkgAndChoosesDeterministically() throws {
        let volume = try TemporaryVolume()
        try volume.createFile("Zeta.pkg")
        try volume.createDirectory("Beta.app")
        try volume.createDirectory("Alpha.app")

        let payload = try PayloadLocator().locatePayload(in: volume.url)

        try expect(payload == .app(volume.url.appending(path: "Alpha.app")))
    }

    func returnsNilWhenNoPayloadExists() throws {
        let volume = try TemporaryVolume()
        try volume.createFile("Read Me.txt")

        let payload = try PayloadLocator().locatePayload(in: volume.url)

        try expect(payload == nil)
    }
}
