// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "ExerciseCore",
  platforms: [.iOS(.v17), .macOS(.v13), .watchOS(.v10)],
  products: [.library(name: "ExerciseCore", targets: ["ExerciseCore"])],
  targets: [
    .target(name: "ExerciseCore"),
    .testTarget(
      name: "ExerciseCoreTests", dependencies: ["ExerciseCore"],
      resources: [.copy("Fixtures")]),
  ]
)
