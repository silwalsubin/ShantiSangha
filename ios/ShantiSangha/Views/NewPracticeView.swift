import SwiftUI

/// Create a new recurring practice. After the OneTime split, this only
/// creates daily practices — one-time things now live as Reminders.
struct NewPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String?) async -> Void

    @State private var title = ""
    @State private var deeperWhy = ""
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What would you like to practice?")
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)

                    TextField("Meditate, exercise, read...", text: $title)
                        .textFieldStyle(.plain)
                        .font(.sacredText)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Why does this matter?")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                    TextEditor(text: $deeperWhy)
                        .font(.sacredText)
                        .foregroundColor(.sacredText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))
                    Text("Optional. This helps the app remember the intention beneath the habit.")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }

                SacredPrimaryButton(
                    "Start this practice",
                    style: .commit,
                    isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty,
                    isLoading: saving
                ) {
                    saving = true
                    Task {
                        await onCreate(
                            title.trimmingCharacters(in: .whitespaces),
                            deeperWhy.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .sacredBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
