import SwiftUI

/// Shared chrome for any "edit one thing" sheet — NavigationStack +
/// inline title + Cancel toolbar + sacred background + presentation
/// detent. Extracted from the personal account-edit sheet on Home so
/// the per-Connection nickname / notes / avatar / future editors all
/// inherit the same look without each call site replicating the
/// boilerplate.
///
/// The body content is responsible for its own padding-INSIDE rules
/// (text fields, TextEditors, buttons); the shell only adds the outer
/// horizontal + top padding so every sheet feels alike.
struct SacredFormSheet<Content: View>: View {
    let title: String
    let detent: PresentationDetent
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        detent: PresentationDetent,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detent = detent
        self.onCancel = onCancel
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
                .padding(.horizontal, SacredSpacing.l)
                .padding(.top, SacredSpacing.l)
                .frame(maxHeight: .infinity, alignment: .top)
                .sacredBackground()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                            .foregroundColor(.sacredMuted)
                    }
                }
        }
        .presentationDetents([detent])
    }
}
