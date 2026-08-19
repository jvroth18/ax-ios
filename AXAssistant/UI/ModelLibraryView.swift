import SwiftUI

/// The model library: every catalog model with an honest description, grouped by what
/// it's for. Load switches to it, Get downloads it, Remove deletes its weights.
struct ModelLibraryView: View {
    let modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: CatalogModel?

    var body: some View {
        ZStack {
            W95Desktop()
            W95Window(title: "Model Library", onClose: { dismiss() }) {
                VStack(spacing: 4) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(CatalogModel.Category.allCases) { category in
                                categorySection(category)
                            }
                            Text("Models come from the mlx-community hub and run fully on-device. Weights live in the Files app and can always be re-downloaded.")
                                .font(W95.ui(11))
                                .foregroundStyle(W95.shadow)
                        }
                        .padding(8)
                    }
                    .w95Well(background: .white)
                    W95StatusBar(fields: [statusSummary, diskSummary])
                }
                .padding(4)
                .background(W95.face)
            }
            .padding(6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Remove \(pendingDelete?.name ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove weights", role: .destructive) {
                if let model = pendingDelete { modelManager.delete(model) }
                pendingDelete = nil
            }
        } message: {
            Text("You can download it again at any time.")
        }
    }

    private func categorySection(_ category: CatalogModel.Category) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.rawValue)
                .font(W95.ui(13, bold: true))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(W95.navy)
            ForEach(ModelCatalog.models(in: category)) { model in
                ModelRow(
                    model: model,
                    isCurrent: model == modelManager.choice,
                    isLoaded: isLoaded(model),
                    isDownloaded: modelManager.isDownloaded(model),
                    isBusy: isBusy,
                    downloadFraction: modelManager.downloadProgress[model.id],
                    onGet: { modelManager.download(model) },
                    onCancel: { modelManager.cancelDownload(of: model) },
                    onLoad: { Task { await modelManager.switchTo(model) } },
                    onDelete: { pendingDelete = model }
                )
            }
        }
    }

    private func isLoaded(_ model: CatalogModel) -> Bool {
        guard case .ready = modelManager.state else { return false }
        return model == modelManager.choice
    }

    private var isBusy: Bool {
        switch modelManager.state {
        case .downloading, .loading: return true
        default: return false
        }
    }

    private var statusSummary: String {
        switch modelManager.state {
        case .ready: return "Loaded: \(modelManager.choice.name)"
        case .downloading(let progress): return "Downloading… \(Int(progress * 100))%"
        case .loading: return "Loading…"
        case .failed(let why): return "Error: \(why)"
        case .idle: return "No model loaded"
        }
    }

    private var diskSummary: String {
        let installed = ModelCatalog.all.filter(modelManager.isDownloaded).count
        let gb = Double(modelManager.totalBytesOnDisk) / 1_073_741_824
        return "\(installed) installed · \(String(format: "%.1f", gb)) GB"
    }
}

private struct ModelRow: View {
    let model: CatalogModel
    let isCurrent: Bool
    let isLoaded: Bool
    let isDownloaded: Bool
    let isBusy: Bool
    let downloadFraction: Double?
    let onGet: () -> Void
    let onCancel: () -> Void
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                vendorBadge
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(W95.ui(13, bold: true))
                            .foregroundStyle(W95.text)
                        if isLoaded {
                            Text("LOADED")
                                .font(W95.mono(9, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(red: 0, green: 0.5, blue: 0))
                        }
                        if !model.fitsStandardIPhone {
                            Text("PRO ONLY")
                                .font(W95.mono(9, bold: true))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(W95.maroon)
                        }
                    }
                    Text("\(model.vendor) · \(model.params) · \(model.sizeLabel)")
                        .font(W95.ui(11))
                        .foregroundStyle(W95.shadow)
                    Text(model.blurb)
                        .font(W95.ui(12))
                        .foregroundStyle(W95.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let fraction = downloadFraction {
                HStack(spacing: 8) {
                    W95ProgressBar(value: fraction, blocks: 12)
                    Text("\(Int(fraction * 100))%")
                        .font(W95.mono(10, bold: true))
                        .foregroundStyle(W95.navy)
                    Button("✕") { onCancel() }.buttonStyle(W95ButtonStyle())
                }
            } else {
                HStack(spacing: 6) {
                    if isLoaded {
                        Button("Loaded ✓") {}.buttonStyle(W95ButtonStyle()).disabled(true)
                    } else if isDownloaded {
                        Button("Load") { onLoad() }.buttonStyle(W95ButtonStyle(bold: true)).disabled(isBusy)
                    } else {
                        Button("Get (\(model.sizeLabel))") { onGet() }
                            .buttonStyle(W95ButtonStyle(bold: true))
                    }
                    if isDownloaded {
                        Button("Remove") { onDelete() }.buttonStyle(W95ButtonStyle()).disabled(isBusy)
                    }
                    Spacer()
                }
            }
        }
        .padding(8)
        .background(isCurrent ? W95.faceLight : .white)
        .overlay(Rectangle().fill(W95.shadow.opacity(0.35)).frame(height: 1), alignment: .bottom)
    }

    private var vendorBadge: some View {
        Text(String(model.vendor.prefix(1)))
            .font(W95.ui(14, bold: true))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(badgeColor)
            .overlay(W95BevelOverlay())
    }

    private var badgeColor: Color {
        switch model.vendor {
        case "Meta": return W95.navy
        case "Google": return Color(red: 0, green: 0.5, blue: 0)
        case "DeepSeek": return Color(red: 0.3, green: 0, blue: 0.5)
        case "Liquid AI": return Color(red: 0, green: 0.45, blue: 0.55)
        case "Hugging Face": return Color(red: 0.85, green: 0.55, blue: 0)
        default: return W95.maroon  // Qwen and friends
        }
    }
}
