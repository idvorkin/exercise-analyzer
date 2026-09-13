// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Where a model's ops are scheduled (CPU, GPU, Neural Engine), from Core ML's compute plan: the same assignment
//  Xcode's performance report shows, so the session log can say where each model runs (#44).

#if canImport(CoreML)
  import CoreML
  import Foundation

  public enum ModelPlan {
    /// Ops per device for the model at `compiledModelURL` under `computeUnits`, plus the total; empty when the
    /// OS is too old for compute plans (iOS 17.4, macOS 14.4, watchOS 10.4) or the plan cannot be loaded.
    public static func summary(compiledModelURL: URL, computeUnits: MLComputeUnits = .all) async -> [String: Int] {
      guard #available(iOS 17.4, macOS 14.4, watchOS 10.4, *) else { return [:] }
      return await load(compiledModelURL: compiledModelURL, computeUnits: computeUnits)
    }

    @available(iOS 17.4, macOS 14.4, watchOS 10.4, *)
    private static func load(compiledModelURL: URL, computeUnits: MLComputeUnits) async -> [String: Int] {
      let configuration = MLModelConfiguration()
      configuration.computeUnits = computeUnits
      guard let plan = try? await MLComputePlan.load(contentsOf: compiledModelURL, configuration: configuration),
        case .program(let program) = plan.modelStructure, let main = program.functions["main"]
      else { return [:] }
      var counts: [String: Int] = ["ops": 0]
      func visit(_ block: MLModelStructure.Program.Block) {
        for operation in block.operations {
          counts["ops", default: 0] += 1
          let device = plan.deviceUsage(for: operation)?.preferred
          let key: String
          switch device {
          case .cpu: key = "cpu"
          case .gpu: key = "gpu"
          case .neuralEngine: key = "ane"
          default: key = "unassigned"
          }
          counts[key, default: 0] += 1
          for inner in operation.blocks { visit(inner) }
        }
      }
      visit(main.block)
      return counts
    }
  }
#endif
