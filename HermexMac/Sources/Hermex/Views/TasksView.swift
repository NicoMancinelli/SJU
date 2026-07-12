import SwiftUI

struct TasksView: View {
    let client: APIClient

    @State private var jobs: [CronJob] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading && jobs.isEmpty {
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
                jobList
            }
        }
        .navigationTitle("Tasks")
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

    private var jobList: some View {
        List {
            if let actionError {
                Text(actionError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            ForEach(jobs) { job in
                CronJobRow(job: job) { action in
                    Task { await perform(action, on: job) }
                }
            }
        }
        .overlay {
            if jobs.isEmpty && !isLoading {
                Text("No scheduled tasks")
                    .foregroundStyle(.secondary)
            }
        }
    }

    enum JobAction {
        case run
        case pause
        case resume
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.crons()
            jobs = response.jobs ?? []
            loadError = nil
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func perform(_ action: JobAction, on job: CronJob) async {
        guard let jobID = job.jobId else { return }
        do {
            let response: CronMutationResponse
            switch action {
            case .run:
                response = try await client.runCron(jobID: jobID)
            case .pause:
                response = try await client.pauseCron(jobID: jobID)
            case .resume:
                response = try await client.resumeCron(jobID: jobID)
            }
            if response.ok == false, let error = response.error {
                actionError = error
            } else {
                actionError = nil
            }
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        await load()
    }
}

private struct CronJobRow: View {
    let job: CronJob
    let act: (TasksView.JobAction) -> Void

    private var isPaused: Bool {
        job.enabled == false || job.state?.lowercased() == "paused"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.displayName)
                    .fontWeight(.medium)
                if isPaused {
                    Text("Paused")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer()
                Button {
                    act(.run)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .help("Run now")
                Button {
                    act(isPaused ? .resume : .pause)
                } label: {
                    Image(systemName: isPaused ? "arrow.clockwise.circle" : "pause.circle")
                }
                .buttonStyle(.plain)
                .help(isPaused ? "Resume schedule" : "Pause schedule")
            }
            if let schedule = job.scheduleDisplay, !schedule.isEmpty {
                Text(schedule)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let prompt = job.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                if let next = job.nextRunAt, next > 0 {
                    Label {
                        Text(Date(timeIntervalSince1970: next), style: .relative)
                    } icon: {
                        Image(systemName: "clock")
                    }
                }
                if let status = job.lastStatus, !status.isEmpty {
                    Text("Last: \(status)")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            if let lastError = job.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
