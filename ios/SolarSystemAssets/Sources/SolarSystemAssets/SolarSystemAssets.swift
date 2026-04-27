import Foundation

/// Marker for the SolarSystemAssets RealityKit content package.
/// The visible value lives in the `.rkassets` bundle alongside this
/// file — RCP authors materials/scenes there and Xcode embeds them
/// in the app at build time. Loaded at runtime via
/// `ShaderGraphMaterial(named:from:in:)` against this module's bundle.
public enum SolarSystemAssets {
    /// The bundle that contains the `.rkassets` resources. Pass to
    /// `ShaderGraphMaterial(named:from:in:)` as the `in:` parameter.
    public static let bundle = Bundle.module
}
