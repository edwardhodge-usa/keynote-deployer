import Foundation

enum StepStatus: String, Codable, Sendable {
    case pending, active, completed, skipped, error
}

struct ProcessingStep: Identifiable, Sendable {
    let id: Int
    let label: String
    var detail: String
    var status: StepStatus
    var error: String?
}

/// All 16 pipeline steps in order
extension ProcessingStep {
    static let allSteps: [ProcessingStep] = [
        ProcessingStep(id: 1, label: "Validate folder", detail: "", status: .pending),
        ProcessingStep(id: 2, label: "Read metadata", detail: "", status: .pending),
        ProcessingStep(id: 3, label: "Backup main.js", detail: "", status: .pending),
        ProcessingStep(id: 4, label: "Fix 1: zC scale", detail: "", status: .pending),
        ProcessingStep(id: 5, label: "Fix 2: Fullscreen bypass", detail: "", status: .pending),
        ProcessingStep(id: 6, label: "Fix 3: Viewport A", detail: "", status: .pending),
        ProcessingStep(id: 7, label: "Fix 4: Viewport B", detail: "", status: .pending),
        ProcessingStep(id: 8, label: "Fix 5: Resize viewport", detail: "", status: .pending),
        ProcessingStep(id: 9, label: "Fix 6: Constructor viewport", detail: "", status: .pending),
        ProcessingStep(id: 10, label: "Fix 7: Canvas DPR", detail: "", status: .pending),
        ProcessingStep(id: 11, label: "Generate index.html", detail: "", status: .pending),
        ProcessingStep(id: 12, label: "Vercel project", detail: "", status: .pending),
        ProcessingStep(id: 13, label: "Deploy", detail: "", status: .pending),
        ProcessingStep(id: 14, label: "Verify deployment", detail: "", status: .pending),
        ProcessingStep(id: 15, label: "Runtime verification", detail: "", status: .pending),
        ProcessingStep(id: 16, label: "Complete", detail: "", status: .pending),
    ]
}
