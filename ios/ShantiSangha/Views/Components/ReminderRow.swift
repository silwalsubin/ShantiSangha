import SwiftUI
import Pow

/// Row for a single reminder. Tap to edit, swipe right to mark complete.
/// The swipe-to-complete is reserved for the carried-over list — pass
/// `allowSwipeToComplete: false` for general usage.
struct ReminderRow: View {
    let reminder: Reminder
    var allowSwipeToComplete: Bool = false
    var hideDateBadge: Bool = false
    var showDateStamp: Bool = false
    /// Person prefix prepended to the label when the reminder belongs to
    /// a connection — e.g. "Didi · Birthday". Caller passes the
    /// connection's nickname (or display name) when scoping the row to a
    /// shared surface like Home or Calendar where the same label
    /// ("Birthday") repeats across people. Leave nil on per-connection
    /// surfaces (the profile's Important Dates list) where the name is
    /// already in the header.
    var connectionLabel: String? = nil
    /// Viewer's user ID. The row uses it to subtract the viewer from the
    /// collaborator pip so people see "who else is on this" rather than
    /// their own face. Optional so previews / unauthenticated surfaces
    /// can render the row without a session.
    var currentUserId: UUID? = nil
    let onTap: () -> Void
    var onComplete: (() -> Void)? = nil
    var activeSwipeId: Binding<String?>?

    @State private var offset: CGFloat = 0
    @State private var activeSwipe: Bool = false

    private var swipeActive: Bool {
        activeSwipeId?.wrappedValue == reminder.id.uuidString
    }
    private let swipeThreshold: CGFloat = 80

    var body: some View {
        ZStack {
            if offset > 0 {
                HStack {
                    Image(systemName: "checkmark")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.white)
                    Text("Done")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredGreen))
            }

            content
                .onTapGesture {
                    if !activeSwipe { onTap() }
                }
                .offset(x: offset)
                .gesture(canSwipe ? swipeGesture : nil)
        }
    }

    private var canSwipe: Bool {
        allowSwipeToComplete && onComplete != nil && reminder.completedAt == nil
    }

    private var isCompleted: Bool {
        reminder.completedAt != nil
    }

    /// "{Connection} · {label}" when the row is connection-scoped; just
    /// the bare label otherwise. The connection name is the bolder half
    /// since it's the more identifying piece of info. Strikethrough kicks
    /// in when the reminder is completed so the row visibly reads as done.
    private var labelText: Text {
        if let conn = connectionLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !conn.isEmpty {
            var attr = AttributedString()

            var nameAttrs = AttributeContainer()
            nameAttrs.inlinePresentationIntent = .stronglyEmphasized
            if isCompleted { nameAttrs.strikethroughStyle = .single }
            attr.append(AttributedString(conn, attributes: nameAttrs))

            var sepAttrs = AttributeContainer()
            sepAttrs.foregroundColor = .sacredMuted
            attr.append(AttributedString(" · ", attributes: sepAttrs))

            var labelAttrs = AttributeContainer()
            if isCompleted { labelAttrs.strikethroughStyle = .single }
            attr.append(AttributedString(reminder.label, attributes: labelAttrs))
            return Text(attr)
        }
        var bare = AttributedString(reminder.label)
        if isCompleted {
            var attrs = AttributeContainer()
            attrs.strikethroughStyle = .single
            bare.setAttributes(attrs)
        }
        return Text(bare)
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 12) {
            leadingSlot

            VStack(alignment: .leading, spacing: 2) {
                labelText
                    .font(.sacredTextMedium)
                    .foregroundColor(isCompleted ? .sacredMuted : .sacredText)
                    .lineLimit(1)

                if let sharedLabel = sharedSubtitle {
                    Text(sharedLabel)
                        .font(.sacredMicro)
                        .foregroundColor(.sacredGold.opacity(0.85))
                        .lineLimit(1)
                } else if showDateStamp, let status = relativeDateLabel {
                    Text(status)
                        .font(localDaysRemaining <= 0 ? .sacredSmallSemibold : .sacredSmall)
                        .foregroundColor(dateStatusColor)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isCompleted {
                doneBadge
                    // Poof in — the badge bursts into existence like a
                    // small magical confirmation. Pairs with the
                    // strikethrough that already reads as past-tense.
                    .transition(.movingParts.poof)
            } else if !hideDateBadge && !showDateStamp {
                Text(dueDateLabel)
                    .font(localDaysRemaining <= 0 ? .sacredSmallSemibold : .sacredSmall)
                    .foregroundColor(dateStatusColor)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .topTrailing) {
            // Discreet sharing cue: small overlapping avatars in the
            // corner showing the OTHER people on this task — never
            // including the viewer themselves. Hidden when the row is
            // completed so the green checkmark owns that corner.
            if !othersOnReminder.isEmpty && !isCompleted {
                collaboratorAvatarStack
                    .padding(.top, 6)
                    .padding(.trailing, 10)
            }
        }
        .opacity(isCompleted ? 0.55 : 1)
        // Drives the .poof transition above when isCompleted flips.
        // Without this animation context the transition would snap.
        .animation(SacredMotion.respecting(SacredMotion.morph), value: isCompleted)
        // Whole-row gold glow at the moment of completion — like the
        // entry quietly says "received." Restraint: glow only, no
        // motion noise.
        .changeEffect(
            .glow(color: .sacredGold, radius: 18),
            value: isCompleted
        )
        .background(
            Group {
                if swipeActive {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.sacredBgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.sacredMuted.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        )
    }

    /// "Shared by Alice" line for collaborator views. Returns nil on
    /// owner-side rows so the existing date-stamp line keeps its place;
    /// the collaborator stack on the right already cues sharing for the
    /// owner.
    private var sharedSubtitle: String? {
        if reminder.isSharedWithMe,
           let name = reminder.ownerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "Shared by \(name)"
        }
        return nil
    }

    /// The other people on this reminder. Built as
    /// `[owner if I'm a recipient] + [collaborators except me]`, so
    /// every shared row surfaces "who else is on this with you" — the
    /// viewer is treated as a participant by default and doesn't need
    /// their own avatar reflected back at them.
    private var othersOnReminder: [ReminderCollaboratorSummary] {
        var others: [ReminderCollaboratorSummary] = []
        if reminder.isSharedWithMe,
           let name = reminder.ownerDisplayName,
           !name.isEmpty {
            // The owner isn't in `collaborators` (they're the UserId
            // owner). Surface them as a synthetic participant row so
            // the recipient's pip isn't empty.
            others.append(ReminderCollaboratorSummary(
                userId: UUID(),
                displayName: name,
                avatarUrl: reminder.ownerAvatarUrl))
        }
        let me = currentUserId
        for c in reminder.collaborators where c.userId != me {
            others.append(c)
        }
        return others
    }

    /// Compact top-right pip: up to two 16pt avatars overlapped, plus a
    /// "+N" gold dot when the share list is bigger. Intentionally small
    /// and tucked into the corner so the row's primary content
    /// (label / due) stays the focus.
    @ViewBuilder
    private var collaboratorAvatarStack: some View {
        let others = othersOnReminder
        let visible = Array(others.prefix(2))
        let overflow = others.count - visible.count
        HStack(spacing: -6) {
            ForEach(visible, id: \.userId) { c in
                ProfileAvatarImage(rawUrl: c.avatarUrl, size: 16, borderWidth: 1)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.sacredText)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.sacredGold.opacity(0.20)))
                    .overlay(Circle().stroke(Color.sacredBgCard, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var leadingSlot: some View {
        if showDateStamp, let parsed = parseISODate(reminder.date) {
            SacredDateStamp(date: parsed, daysRemaining: localDaysRemaining)
        } else {
            Image(systemName: "calendar.badge.clock")
                .font(.sacredText)
                .foregroundColor(.sacredGold)
                .frame(width: 24, height: 24)
        }
    }

    /// Replaces the right-side date label when a reminder is completed.
    /// Bare green checkmark — the strikethrough on the label already
    /// reads as past-tense, so no badge chrome is needed.
    private var doneBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.sacredGreen)
            .padding(.trailing, 4)
    }

    private var dueDateLabel: String {
        if let relativeDateLabel { return relativeDateLabel }
        if let date = parseISODate(reminder.date) {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
        return ""
    }

    private var relativeDateLabel: String? {
        let days = localDaysRemaining
        if days < -1 { return "\(abs(days)) days ago" }
        if days == -1 { return "Yesterday" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days < 14 { return "in \(days) days" }
        return nil
    }

    private var dateStatusColor: Color {
        if isCompleted { return .sacredMuted }
        if localDaysRemaining < 0 { return .sacredRed }
        if localDaysRemaining == 0 { return .sacredGold }
        return .sacredMuted
    }

    private var localDaysRemaining: Int {
        reminder.localDaysRemaining
    }

    private func parseISODate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    private var swipeGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                activeSwipeId?.wrappedValue = reminder.id.uuidString
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .sequenced(before:
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard swipeActive else { return }
                        offset = max(0, value.translation.width)
                        activeSwipe = offset > swipeThreshold
                    }
                    .onEnded { _ in
                        if activeSwipe {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.easeOut(duration: 0.2)) {
                                offset = 300
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onComplete?()
                                offset = 0
                                activeSwipe = false
                            }
                        } else {
                            withAnimation(.spring(response: 0.3)) {
                                offset = 0
                            }
                        }
                        activeSwipeId?.wrappedValue = nil
                    }
            )
    }
}
