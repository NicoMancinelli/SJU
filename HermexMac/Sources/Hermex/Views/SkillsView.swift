import SwiftUI

struct SkillsView: View {
    let client: APIClient

    @State private var skills: [SkillSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var filter = ""

    private var filteredSkills: [SkillSummary] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return skills }
        return skills.filter { skill in
            (skill.name ?? "").localizedCaseInsensitiveContains(query)
                || (skill.description ?? "").localizedCaseInsensitiveContains(query)
                || (skill.category ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if isLoading && skills.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                errorView(loadError)
            } else {
                skillsList
            }
        }
        .navigationTitle("Skills")
        .safeAreaInset(edge: .top) {
            TextField("Filter skills", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
        }
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

    private var skillsList: some View {
        List {
            ForEach(groupNames, id: \.self) { group in
                Section(group) {
                    ForEach(filteredSkills.filter { ($0.category ?? "Other") == group }) { skill in
                        SkillRow(skill: skill) { enabled in
                            Task { await toggle(skill, enabled: enabled) }
                        }
                    }
                }
            }
        }
        .overlay {
            if filteredSkills.isEmpty && !isLoading {
                Text(skills.isEmpty ? "No skills installed" : "No matches")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var groupNames: [String] {
        var seen = Set<String>()
        return filteredSkills.compactMap { skill in
            let group = skill.category ?? "Other"
            return seen.insert(group).inserted ? group : nil
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            Button("Retry") {
                Task { await load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.skills()
            skills = response.skills ?? []
            loadError = nil
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggle(_ skill: SkillSummary, enabled: Bool) async {
        guard let name = skill.name else { return }
        _ = try? await client.toggleSkill(name: name, enabled: enabled)
        await load()
    }
}

private struct SkillRow: View {
    let skill: SkillSummary
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name ?? "Unnamed skill")
                    .fontWeight(.medium)
                if let description = skill.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                if let tags = skill.tags, !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { skill.disabled != true },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 3)
    }
}
