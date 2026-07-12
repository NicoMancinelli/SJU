import SwiftUI

struct MemoryView: View {
    let client: APIClient

    @State private var memory: MemoryResponse?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading && memory == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                VStack(spacing: 8) {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Button("Retry") {
                        Task { await load() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                sections
            }
        }
        .navigationTitle("Memory")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
    }

    private var sections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                memorySection("Agent Memory", text: memory?.memory)
                memorySection("User Profile", text: memory?.user)
                memorySection("Soul", text: memory?.soul)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func memorySection(_ title: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.separator)
                    )
            } else {
                Text("Empty")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            memory = try await client.memory()
            loadError = nil
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
