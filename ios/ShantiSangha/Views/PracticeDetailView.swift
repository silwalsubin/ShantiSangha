import SwiftUI

/// Practice detail — recurring practice only after the OneTime split.
struct PracticeDetailView: View {
    let practiceId: String
    @Environment(\.dismiss) private var dismiss
    @State private var practice: PracticeDetail?
    @State private var activities: [PracticeActivityItem] = []
    @State private var loading = true
    @State private var historyExpanded = false
    @State private var historyLoading = false
    @State private var showWhyEditor = false
    @State private var whyText = ""
    @State private var showTitleEditor = false
    @State private var titleText = ""
    @State private var toastMessage: String?
    private let api = ApiService.shared

    private var practicePath: String { "/practices/\(practiceId)" }

    var body: some View {
        ScrollView {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let practice = practice {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        titleText = practice.title
                        showTitleEditor = true
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 28))
                                .foregroundColor(.sacredGold)
                            Text(practice.title)
                                .font(.sacredHeading)
                                .foregroundColor(.sacredText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        statCard(value: "\(practice.currentStreak ?? 0)", label: "Current Streak")
                        statCard(value: "\(practice.longestStreak ?? 0)", label: "Longest Streak")
                    }

                    // Deeper Why
                    Button {
                        whyText = practice.deeperWhy ?? ""
                        showWhyEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "leaf")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredGold)
                                Text("THE DEEPER WHY")
                                    .font(.sacredSectionLabel)
                                    .tracking(3)
                                    .foregroundColor(.sacredLabel)
                                Spacer()
                                Image(systemName: "pencil")
                                    .font(.sacredMicro)
                                    .foregroundColor(.sacredMuted)
                            }
                            if let why = practice.deeperWhy, !why.isEmpty {
                                Text("\"\(why)\"")
                                    .font(.sacredBody)
                                    .italic()
                                    .foregroundColor(.sacredText)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text("Tap to add your deeper intention...")
                                    .font(.sacredText)
                                    .foregroundColor(.sacredMuted)
                            }
                        }
                        .padding(16)
                        .luxCardChrome()
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: PracticeCalendarView(
                        practiceId: practice.id,
                        practiceTitle: practice.title,
                        practiceCreatedAt: practice.createdAt
                    )) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredGold)
                                Text("CHECK-IN CALENDAR")
                                    .font(.sacredSectionLabel)
                                    .tracking(3)
                                    .foregroundColor(.sacredLabel)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.sacredMicro)
                                    .foregroundColor(.sacredMuted)
                            }
                            Text("View, edit, or correct past entries.")
                                .font(.sacredText)
                                .foregroundColor(.sacredMuted)
                        }
                        .padding(16)
                        .luxCardChrome()
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await deletePractice() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.sacredSmall)
                            Text("Delete this practice")
                                .font(.sacredTextMedium)
                        }
                        .foregroundColor(.sacredRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredRed.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredRed.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                }
                .padding(16)
            } else {
                Text("Practice not found.")
                    .foregroundColor(.sacredTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .sacredBackground()
        .sacredToast($toastMessage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if practice != nil {
                    Menu {
                        Button {
                            Task { await markComplete() }
                        } label: {
                            Label("Complete for today", systemImage: "checkmark.circle")
                        }
                        Button {
                            Task { await skipForToday() }
                        } label: {
                            Label("Skip for today", systemImage: "moon.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.sacredText)
                            .foregroundColor(.sacredMuted)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showTitleEditor) {
            NavigationStack {
                VStack(spacing: 16) {
                    TextField("Practice name", text: $titleText)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                        .multilineTextAlignment(.center)
                        .padding(16)

                    Spacer()
                }
                .sacredBackground()
                .navigationTitle("Rename")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showTitleEditor = false }
                            .foregroundColor(.sacredMuted)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            showTitleEditor = false
                            Task { await saveTitle() }
                        }
                        .foregroundColor(.sacredGold)
                        .disabled(titleText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showWhyEditor) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What draws you to this practice? Understanding the deeper intention behind your commitments can transform discipline into devotion.")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)

                    TextEditor(text: $whyText)
                        .font(.sacredBody)
                        .foregroundColor(.sacredText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(12)
                        .luxCardChrome()

                    Spacer()
                }
                .padding(16)
                .sacredBackground()
                .navigationTitle("The Deeper Why")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showWhyEditor = false }
                            .foregroundColor(.sacredMuted)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            showWhyEditor = false
                            Task { await saveDeeperWhy() }
                        }
                        .foregroundColor(.sacredGold)
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            practice = try await api.get(practicePath)
        } catch {
            if !error.isCancellation {
                toastMessage = "Could not load this practice. Try again in a moment."
                AppLogger.shared.error("PracticeDetail", "Failed to load: \(error)")
            }
        }
        loading = false
    }

    private func markComplete() async {
        let dateStr = todayStr()
        let body: [String: Any] = ["completed": true, "date": dateStr]
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let _: EmptyResponse = try await api.postRaw("/practices/\(practiceId)/checkin", body: data)
            practice = try await api.get(practicePath)
        } catch {
            if !error.isCancellation {
                toastMessage = "Could not complete this practice. Try again."
            }
        }
    }

    private func skipForToday() async {
        let dateStr = todayStr()
        let body: [String: Any] = ["completed": false, "date": dateStr]
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            let _: EmptyResponse = try await api.postRaw("/practices/\(practiceId)/checkin", body: data)
            practice = try await api.get(practicePath)
        } catch {
            if !error.isCancellation {
                toastMessage = "Could not pause this practice for today. Try again."
            }
        }
    }

    private func deletePractice() async {
        do {
            try await api.delete("/practices/\(practiceId)")
            dismiss()
        } catch {
            if !error.isCancellation {
                toastMessage = "Could not delete this practice. Try again."
            }
        }
    }

    private func saveTitle() async {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let body: [String: String] = ["title": trimmed]
            let _: EmptyResponse = try await api.patch("/practices/\(practiceId)", body: body)
            practice = try await api.get(practicePath)
        } catch {
            if !error.isCancellation {
                toastMessage = "Could not rename this practice. Try again."
            }
        }
    }

    private func saveDeeperWhy() async {
        let trimmed = whyText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let body: [String: String] = ["deeperWhy": trimmed]
            let _: EmptyResponse = try await api.patch("/practices/\(practiceId)", body: body)
            practice = try await api.get(practicePath)
        } catch {
            if !error.isCancellation {
                toastMessage = "Could not save your deeper why. Try again."
            }
        }
    }

    private func todayStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredGold)
            Text(label)
                .font(.sacredSectionLabel)
                .tracking(2)
                .foregroundColor(.sacredMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .luxCardChrome()
    }
}
