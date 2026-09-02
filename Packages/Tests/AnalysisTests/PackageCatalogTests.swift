import XCTest
@testable import Analysis

final class PackageCatalogTests: XCTestCase {
    func testModuleNamesAreUnique() {
        let names = PackageCatalog.modules.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(
            names,
            ["Filesystem", "Index", "Classification", "Identity", "Actions", "Hints", "Analysis"]
        )
        XCTAssertFalse(names.contains { $0.contains("DumpVerify") })
    }

    func testEveryLocalDependencyResolvesOrIsExternal() {
        let known = Set(PackageCatalog.modules.map(\.name)).union(["GRDB"])
        for module in PackageCatalog.modules {
            for dependency in module.dependencies {
                XCTAssertTrue(known.contains(dependency), "Unknown dependency \(dependency) in \(module.name)")
            }
        }
    }

    func testAnalysisDependsOnEveryOtherLocalModuleItOrchestrates() {
        let analysis = PackageCatalog.module(named: "Analysis")
        XCTAssertNotNil(analysis)
        XCTAssertEqual(
            analysis?.dependencies,
            ["Filesystem", "Index", "Classification", "Identity", "Actions", "Hints"]
        )
    }

    func testActionsDependsOnClassificationAsInPackageManifest() {
        XCTAssertEqual(
            PackageCatalog.module(named: "Actions")?.dependencies,
            ["Classification"]
        )
    }

    func testModulesDescribeThemselves() {
        for module in PackageCatalog.modules {
            XCTAssertFalse(module.role.isEmpty)
            XCTAssertFalse(module.detail.isEmpty)
            XCTAssertFalse(module.dependencyLine.isEmpty)
        }
    }
}
