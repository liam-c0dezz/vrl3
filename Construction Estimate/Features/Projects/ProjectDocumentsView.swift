import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
final class ProjectDocumentStore {
    var documents: [ProjectDocument] = []
    var isLoading = false
    var isUploading = false
    var lastError: String?

    func refresh(projectID: UUID) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            documents = try await ProjectDocumentRepository.load(projectID: projectID)
            lastError = nil
        } catch {
            lastError = SafeErrorMessages.data(error, action: "document refresh")
        }
    }

    @discardableResult
    func upload(_ url: URL, projectID: UUID, invoiceID: UUID? = nil, category: String = "document") async -> Bool {
        guard !isUploading else { return false }
        isUploading = true
        defer { isUploading = false }
        do {
            try await ProjectDocumentRepository.upload(
                fileURL: url,
                projectID: projectID,
                invoiceID: invoiceID,
                category: category
            )
            await refresh(projectID: projectID)
            return true
        } catch {
            lastError = SafeErrorMessages.data(error, action: "document upload")
            return false
        }
    }

    func delete(_ document: ProjectDocument, projectID: UUID) async {
        do {
            try await ProjectDocumentRepository.delete(document)
            documents.removeAll { $0.id == document.id }
            lastError = nil
        } catch {
            lastError = SafeErrorMessages.data(error, action: "document deletion")
            await refresh(projectID: projectID)
        }
    }
}

struct ProjectDocumentsView: View {
    let projectID: UUID?

    @State private var store = ProjectDocumentStore()
    @State private var showFileImporter = false
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 16) {
            if let projectID {
                if !hasLoaded || (store.documents.isEmpty && store.isLoading) {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 56)
                } else if store.documents.isEmpty {
                    emptyState
                } else {
                    documentHeader
                    documentList(projectID: projectID)
                }

                if let error = store.lastError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer().frame(height: 60)
                    Text("Save this project first")
                        .font(.system(size: 20, weight: .bold))
                    Text("Documents are stored securely inside a specific project.")
                        .font(.system(size: 15))
                        .foregroundColor(AppGray.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .task(id: projectID) {
            if let projectID {
                hasLoaded = false
                await store.refresh(projectID: projectID)
                hasLoaded = true
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard let projectID,
                  case let .success(urls) = result,
                  let url = urls.first else {
                if case let .failure(error) = result {
                    store.lastError = SafeErrorMessages.data(error, action: "file selection")
                }
                return
            }
            Task { await store.upload(url, projectID: projectID) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Text("No documents yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppGray.ink)
            Text("Attach photos, permits, contracts, and files\nto keep this project organized.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AppGray.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            HapticButton {
                showFileImporter = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add document")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(minWidth: 180)
                .background(AppGray.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private var documentHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Documents")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Text("Photos, permits, contracts,\nand project files")
                    .font(.system(size: 15))
                    .foregroundColor(AppGray.secondary)
            }
            Spacer()
            addButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 21)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func documentList(projectID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.documents) { document in
                HStack(spacing: 12) {
                    Image(systemName: icon(for: document.mime_type))
                        .font(.system(size: 18))
                        .foregroundColor(AppBrand.accent)
                        .frame(width: 38, height: 38)
                        .background(AppGray.bgPale)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.name)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if let size = document.size_bytes {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.system(size: 12))
                                .foregroundColor(AppGray.secondary)
                        }
                    }

                    Spacer()

                    HapticButton(role: .destructive) {
                        Task { await store.delete(document, projectID: projectID) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppGray.border, lineWidth: 1)
                )
            }
        }
    }

    private var addButton: some View {
        HapticButton {
            showFileImporter = true
        } label: {
            HStack(spacing: 6) {
                if store.isUploading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(store.isUploading ? "Uploading" : "Add document")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(AppGray.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(store.isUploading)
    }

    private func icon(for mimeType: String?) -> String {
        guard let mimeType else { return "doc.fill" }
        if mimeType.hasPrefix("image/") { return "photo.fill" }
        if mimeType == "application/pdf" { return "doc.richtext.fill" }
        return "doc.fill"
    }
}
