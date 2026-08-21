import Foundation

/// One installable model. Entries are curated from mlx-community on Hugging Face
/// (checked 2026-08: model_type is supported by our pinned mlx-swift-lm and the 4-bit
/// weights fit an iPhone). `id` is the HF repo, which is also what ModelManager stores.
struct CatalogModel: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Identifiable {
        case assistant = "Assistants"
        case compact = "Small & Fast"
        case specialist = "Specialists"
        var id: String { rawValue }
    }

    let id: String
    let name: String
    let vendor: String
    let params: String
    /// Weights download size, from the HF API at curation time.
    let downloadGB: Double
    let category: Category
    let blurb: String
    /// Device RAM (GB) this model is comfortable on. 8 = any iPhone 17; 12 = Pro only.
    let minMemoryGB: Int

    var fitsStandardIPhone: Bool { minMemoryGB <= 8 }
    var sizeLabel: String {
        downloadGB < 1 ? String(format: "%.0f MB", downloadGB * 1000) : String(format: "%.1f GB", downloadGB)
    }
}

enum ModelCatalog {
    static let defaultModel = all[0]

    static func model(id: String) -> CatalogModel? {
        all.first { $0.id == id }
    }

    static func models(in category: CatalogModel.Category) -> [CatalogModel] {
        all.filter { $0.category == category }
    }

    static let all: [CatalogModel] = [
        // Assistants — the daily drivers.
        CatalogModel(
            id: "mlx-community/Qwen3-1.7B-4bit",
            name: "Qwen3 1.7B", vendor: "Alibaba Qwen", params: "1.7B", downloadGB: 0.97,
            category: .assistant,
            blurb: "The recommended default. Best speed-to-smarts balance on iPhone, strong tool calling.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            name: "Qwen3 4B Instruct", vendor: "Alibaba Qwen", params: "4B", downloadGB: 2.26,
            category: .assistant,
            blurb: "Noticeably smarter than 1.7B and still fits an 8 GB iPhone. Slower; the July 2507 refresh.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            name: "Llama 3.2 3B", vendor: "Meta", params: "3B", downloadGB: 1.81,
            category: .assistant,
            blurb: "Meta's polished small instruct model. Great conversational tone; the middle ground.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "mlx-community/Qwen3-8B-4bit",
            name: "Qwen3 8B", vendor: "Alibaba Qwen", params: "8B", downloadGB: 4.61,
            category: .assistant,
            blurb: "The most capable here, but the weights alone are 4.6 GB — 12 GB Pro devices only.",
            minMemoryGB: 12
        ),
        CatalogModel(
            id: "jtown18/Qwen3.8-4B-Distilled-4bit",
            name: "Qwen3.8 4B Distilled", vendor: "Community (Ma7ee7)", params: "4B", downloadGB: 2.1,
            category: .assistant,
            blurb: "Newest-generation Qwen3.8 distill, converted for Morse. Scored 9/9 on the tool-calling eval — the best score of any community model tested.",
            minMemoryGB: 8
        ),

        // Small & fast — instant answers, quick commands.
        CatalogModel(
            id: "mlx-community/Qwen3-0.6B-4bit",
            name: "Qwen3 0.6B", vendor: "Alibaba Qwen", params: "0.6B", downloadGB: 0.34,
            category: .compact,
            blurb: "Tiny and near-instant. Good for quick commands; don't expect deep reasoning.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            name: "Llama 3.2 1B", vendor: "Meta", params: "1B", downloadGB: 0.70,
            category: .compact,
            blurb: "The most-downloaded small MLX model. Snappy general chat in 700 MB.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "mlx-community/gemma-3-1b-it-qat-4bit",
            name: "Gemma 3 1B", vendor: "Google", params: "1B", downloadGB: 0.73,
            category: .compact,
            blurb: "Google's small Gemma, quantization-aware trained — unusually little quality loss at 4-bit.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "mlx-community/LFM2.5-1.2B-Instruct-4bit",
            name: "LFM 2.5 1.2B", vendor: "Liquid AI", params: "1.2B", downloadGB: 0.66,
            category: .compact,
            blurb: "Liquid's edge-first architecture — built for on-device latency and battery.",
            minMemoryGB: 8
        ),

        // Specialists — a different shape of smart.
        CatalogModel(
            id: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
            name: "R1 Distill 1.5B", vendor: "DeepSeek", params: "1.5B", downloadGB: 1.00,
            category: .specialist,
            blurb: "Reasoning distilled from DeepSeek-R1: thinks step-by-step before answering. Slower, more deliberate.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
            name: "Qwen Coder 3B", vendor: "Alibaba Qwen", params: "3B", downloadGB: 1.74,
            category: .specialist,
            blurb: "Tuned for code: snippets, shell one-liners, regexes, explaining errors.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "mlx-community/SmolLM3-3B-4bit",
            name: "SmolLM3 3B", vendor: "Hugging Face", params: "3B", downloadGB: 1.73,
            category: .specialist,
            blurb: "Hugging Face's fully open model — training data and recipe published. Multilingual.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "jtown18/Qwen3.8-2B-4bit",
            name: "Qwen3.8 2B", vendor: "Community (empero-ai)", params: "2B", downloadGB: 1.0,
            category: .specialist,
            blurb: "Chat only — scored 0/9 on tool calling; it converses but won't run your reminders or timers. For lab comparisons.",
            minMemoryGB: 8
        ),
        CatalogModel(
            id: "jtown18/Qwen3-4B-Abliterated-4bit",
            name: "Qwen3 4B Abliterated (uncensored)", vendor: "Community (Josiefied)", params: "4B", downloadGB: 2.26,
            category: .specialist,
            blurb: "Refusals surgically removed (abliteration), capability intact: 9/9 on the tool-calling eval. Re-hosted in five ≤525 MB shards so downloads checkpoint and resume. No safety tuning — you get what you ask for.",
            minMemoryGB: 8
        ),
    ]
}
