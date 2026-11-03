#if DEBUG
import Foundation
import Observation
import SwiftUI
import UIKit

private struct AcceptanceJob: Decodable {
    let id: String
    let prompt: String
    let imageResource: String?
}

private struct AcceptanceJobs: Decodable {
    let expectedGenerator: String
    let qualification: [AcceptanceJob]
    let repeats: [AcceptanceJob]
    let diagnostics: [AcceptanceJob]?
}

@MainActor @Observable
private final class AcceptanceBatch {
    var isRunning = false
    var status = "Ready for synthetic QA jobs."
    var completed = 0
    var total = 0
    var exportURL: URL?
    private var task: Task<Void, Never>?

    func cancel() { task?.cancel() }

    func run(projectID: UUID, repeats: Bool, diagnostics: Bool = false) {
        guard !isRunning else { return }
        isRunning = true
        completed = 0
        exportURL = nil
        task = Task {
            defer { isRunning = false }
            let batchID = UUID().uuidString
            let phase = diagnostics ? "diagnostics" : (repeats ? "repeats" : "qualification")
            let file = URL.documentsDirectory.appending(path: "EstimatorAcceptance-\(phase).json")
            var results: [[String: Any]] = []
            var expectedGenerator = ""
            let persist: (String) throws -> Void = { state in
                let document: [String: Any] = [
                    "batchID": batchID, "phase": phase, "state": state,
                    "expectedGenerator": expectedGenerator,
                    "updatedAt": ISO8601DateFormatter().string(from: Date()),
                    "results": results
                ]
                let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: file, options: .atomic)
                self.exportURL = file
            }
            do {
                guard let url = Bundle.main.url(forResource: "EstimatorAcceptanceJobs", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let jobs = try JSONDecoder().decode(AcceptanceJobs.self, from: Data(contentsOf: url))
                expectedGenerator = jobs.expectedGenerator
                let queue = diagnostics ? (jobs.diagnostics ?? []) : (repeats ? jobs.repeats : jobs.qualification)
                total = queue.count
                try persist("running")
                let model = ChatViewModel(projectID: projectID)
                for job in queue {
                    try Task.checkCancellation()
                    let sessionID = UUID()
                    status = "\(completed + 1)/\(total): \(job.id)"
                    let startedAt = Date()
                    do {
                        var imageData: Data?
                        if let resource = job.imageResource {
                            guard let imageURL = Bundle.main.url(forResource: resource, withExtension: "png") else { throw CocoaError(.fileNoSuchFile) }
                            // Xcode may optimize bundle PNGs to Apple's CgBI format.
                            // Decode and re-encode before sending standard PNG bytes to the API.
                            let bundledData = try Data(contentsOf: imageURL)
                            guard let encoded = UIImage(data: bundledData)?.pngData(),
                                  encoded.count >= 16,
                                  String(data: encoded.subdata(in: 12..<16), encoding: .ascii) == "IHDR" else {
                                throw CocoaError(.fileReadCorruptFile)
                            }
                            imageData = encoded
                        }
                        let (data, httpStatus, requestID) = try await model.acceptanceRequest(scope: job.prompt, sessionID: sessionID, imageData: imageData)
                        let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                        let report = response["residential_estimate"] as? [String: Any]
                        let wrongVersion = report != nil && report?["generator"] as? String != expectedGenerator
                        let failed = httpStatus >= 400 || report == nil || wrongVersion
                        var result: [String: Any] = [
                            "id": job.id, "prompt": job.prompt, "sessionID": sessionID.uuidString,
                            "requestID": requestID.uuidString, "httpStatus": httpStatus,
                            "startedAt": ISO8601DateFormatter().string(from: startedAt),
                            "elapsedSeconds": Date().timeIntervalSince(startedAt),
                            "failed": failed, "response": response
                        ]
                        if let imageResource = job.imageResource { result["imageResource"] = imageResource }
                        if let report { result["report"] = report }
                        results.append(result)
                        completed += 1
                        try persist("running")
                        if failed {
                            status = "Stopped at \(job.id): request failed or deployed version changed."
                            try persist("failed")
                            return
                        }
                        if !diagnostics && report?["status"] as? String != "provisional_priced_scope" {
                            status = "Stopped at \(job.id): incomplete priced scope requires review."
                            try persist("incomplete_scope")
                            return
                        }
                    } catch {
                        results.append(["id": job.id, "prompt": job.prompt, "sessionID": sessionID.uuidString,
                                        "failed": true, "error": String(describing: error),
                                        "errorDescription": error.localizedDescription,
                                        "consentStatus": String(describing: AIConsentStore.shared.status),
                                        "startedAt": ISO8601DateFormatter().string(from: startedAt),
                                        "elapsedSeconds": Date().timeIntervalSince(startedAt)])
                        completed += 1
                        throw error
                    }
                }
                status = "\(completed) responses saved. Independent accuracy audit required."
                try persist("completed")
            } catch {
                status = Task.isCancelled ? "Cancelled; recorded results preserved." : "Stopped: \(error.localizedDescription)"
                try? persist(Task.isCancelled ? "cancelled" : "failed")
            }
        }
    }
}

struct EstimatorAcceptanceRunnerView: View {
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var batch = AcceptanceBatch()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L("Development-only estimator QA"))
                    Text(L("Uses the current project, AI consent and authenticated estimator. Creates synthetic estimate drafts; sends no client quotes or invoices."))
                        .font(.footnote)
                    Text(L("Reference prices are not bundled or sent. Received responses still require an independent audit."))
                        .font(.footnote)
                }
                Section(L("Batch status")) {
                    Text(batch.status)
                    if batch.isRunning {
                        ProgressView(value: Double(batch.completed), total: Double(max(batch.total, 1)))
                        Button(L("Cancel batch"), role: .destructive) { batch.cancel() }
                    } else {
                        Button(L("Run remaining qualification jobs")) { batch.run(projectID: projectID, repeats: false) }
                        Button(L("Run repeats after qualification audit")) { batch.run(projectID: projectID, repeats: true) }
                        Button(L("Run whole-project diagnostics")) { batch.run(projectID: projectID, repeats: false, diagnostics: true) }
                    }
                    if let file = batch.exportURL {
                        ShareLink("Export recorded responses", item: file)
                    }
                }
            }
            .navigationTitle(L("Estimator QA"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Done")) { dismiss() }.disabled(batch.isRunning)
                }
            }
            .interactiveDismissDisabled(batch.isRunning)
        }
    }
}

struct EstimatorAcceptanceProjectPickerView: View {
    @State private var projects = ProjectStore.shared
    @State private var selectedProject: Project?

    var body: some View {
        List {
            Section {
                Text(L("Choose the existing QA project. Synthetic jobs will be recorded there."))
                    .font(.footnote)
                ForEach(projects.projects) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        VStack(alignment: .leading) {
                            Text(project.title)
                            Text(project.projectNumber).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(L("QA project"))
        .sheet(item: $selectedProject) { project in
            EstimatorAcceptanceRunnerView(projectID: project.id)
        }
    }
}
#endif
