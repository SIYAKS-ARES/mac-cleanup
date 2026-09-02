import Analysis
import Testing

struct AboutCopyTests {
    @Test func creditsStateUnitsNetworkAndClosedChatDatabases() {
        let credits = AboutCopy.credits
        #expect(credits.contains("1024"))
        #expect(credits.contains("KiB"))
        #expect(credits.contains("No network"))
        #expect(credits.contains("ChatStorage"))
        #expect(credits.contains("Axolotl"))
        #expect(credits.contains("enc-key"))
        #expect(credits.contains("Not a WhatsApp extractor"))
        #expect(credits.contains("not 1000"))
        #expect(credits.contains("MIT License"))
        #expect(credits.contains("SIYAKS-ARES"))
        #expect(credits.contains("GRDB.swift"))
    }
}
