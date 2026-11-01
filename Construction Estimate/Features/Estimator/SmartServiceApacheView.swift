import SwiftUI
import Supabase
import PhotosUI

private struct ApacheEstimate: Decodable {
    struct Item: Decodable {
        let catalog_id: String
        let description: String
        let quantity: Double
        let unit: String
        let unit_price: Double
        let total: Double
        let quality: String
    }
    struct Unresolved: Decodable { let work: String; let status: String }
    let items: [Item]
    let unresolved: [Unresolved]
    let subtotal: Double
    let markup_amount: Double
    let total: Double
    let status: String
}

struct SmartServiceApacheView: View {
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var scope = ""
    @State private var markup = "0"
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var loadingPhoto = false
    @State private var busy = false
    @State private var result: ApacheEstimate?
    @State private var message: String?
    @State private var consent = AIConsentStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Scope of work") {
                    TextEditor(text: $scope).frame(minHeight: 140)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(photoData == nil ? "Add photo" : "Change photo", systemImage: "photo")
                    }
                    if photoData != nil { Button("Remove photo") { photoData = nil; selectedPhoto = nil } }
                    HStack { Text("Markup (%)"); TextField("0", text: $markup).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
                if !consent.isGranted {
                    Section { Text("Enable AI features in Settings before generating an estimate.") }
                }
                Section {
                    Button { Task { await generate() } } label: {
                        if busy { HStack { ProgressView(); Text("Preparing estimate…") } }
                        else { Text("Generate with Smart Service Apache") }
                    }
                    .disabled(busy || loadingPhoto || !consent.isGranted || scope.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    if let message { Text(message).foregroundStyle(.red) }
                }
                if let result {
                    Section("Estimate preview") {
                        ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.description)
                                Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(item.unit) × \(item.unit_price.formatted(.currency(code: "USD")))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(item.total, format: .currency(code: "USD"))
                                Text("Match confidence: \(item.quality)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Subtotal", value: result.subtotal.formatted(.currency(code: "USD")))
                        LabeledContent("Markup", value: result.markup_amount.formatted(.currency(code: "USD")))
                        LabeledContent(result.status == "partial" ? "Priced work total" : "Total", value: result.total.formatted(.currency(code: "USD")))
                        Text("Review the proposed work and estimated quantities before quoting. This preview is not saved as a project estimate.").font(.caption)
                    }
                    if !result.unresolved.isEmpty {
                        Section("Work needing review") {
                            ForEach(Array(result.unresolved.enumerated()), id: \.offset) { _, item in Text(item.work) }
                        }
                    }
                }
            }
            .navigationTitle("Smart Service Apache")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await consent.refresh() }
            .onChange(of: selectedPhoto) { _, photo in
                Task {
                    loadingPhoto = true
                    defer { loadingPhoto = false }
                    do {
                        guard let data = try await photo?.loadTransferable(type: Data.self), let image = UIImage(data: data),
                              let jpeg = image.jpegData(compressionQuality: 0.6), jpeg.count <= 2_900_000 else {
                            photoData = nil; message = "Choose a smaller photo."; return
                        }
                        photoData = jpeg; message = nil
                    } catch { message = "Photo could not be loaded." }
                }
            }
        }
    }

    @MainActor private func generate() async {
        guard let percent = Double(markup), percent.isFinite, (0...100).contains(percent) else { message = "Enter a markup from 0 to 100."; return }
        busy = true; message = nil; result = nil
        defer { busy = false }
        do {
            let session = try await supabase.auth.session
            var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("functions/v1/smart-service-apache"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let photos = photoData.map { ["data:image/jpeg;base64," + $0.base64EncodedString()] } ?? []
            request.httpBody = try JSONSerialization.data(withJSONObject: ["operation": "estimate", "request_id": UUID().uuidString, "project_id": projectID.uuidString, "scope": scope, "photos": photos, "markup_percent": percent])
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 370; config.timeoutIntervalForResource = 380
            let client = URLSession(configuration: config)
            defer { client.finishTasksAndInvalidate() }
            let (data, response) = try await client.data(for: request)
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = object["error"] as? String {
                message = error == "consent_required" ? "Enable AI features in Settings." : "The estimate could not finish. Please try again."; return
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { message = "The estimate could not finish. Please try again."; return }
            result = try JSONDecoder().decode(ApacheEstimate.self, from: data)
        } catch { message = "The estimate could not finish. Please try again." }
    }
}
