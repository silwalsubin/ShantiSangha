import SwiftUI

/// Full-screen wrapper around `ConnectionAttachmentsView`. Pushed from the
/// Connection profile via the "Media & Files" tile so the profile stays
/// compact and attachments get room to breathe — the inline rendering grew
/// taller than the rest of the profile combined once a connection had a
/// handful of items.
struct ConnectionAttachmentsScreen: View {
    let connectionId: UUID

    var body: some View {
        ScrollView {
            ConnectionAttachmentsView(connectionId: connectionId)
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, SacredSpacing.l)
        }
        .background(SacredBackground().ignoresSafeArea())
        .navigationTitle("Media & Files")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }
}
