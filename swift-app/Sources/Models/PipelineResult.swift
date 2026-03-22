import Foundation

struct PipelineResult: Sendable {
    let success: Bool
    let projectName: String
    let title: String
    let slideCount: Int
    let url: String
    let fixesApplied: Int
    let fixesSkipped: Int
    let verification: VerificationResult?
    let error: String?
}

struct VerificationResult: Sendable {
    let success: Bool
    let url: String
    let mainJsVerified: Bool
    let indexHtmlVerified: Bool
    let fixes: [FixVerification]
    let totalFixesFound: Int
    let totalFixesMissing: Int
    let error: String?
}

struct FixVerification: Identifiable, Sendable {
    var id: Int { fixNumber }
    let fixNumber: Int
    let name: String
    let found: Bool
    let pattern: String
}
