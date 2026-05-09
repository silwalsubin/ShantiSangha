import SwiftUI

/// Sheet for adding a local connection — someone the owner wants in
/// their circle who isn't on ShantiSangha. Friend invitations remain a
/// separate flow (the existing user-search → request path).
///
/// Required: a name + a relation type. If relation is "Other," a
/// custom label is also required. Everything else (location, contact)
/// is optional and folded behind "Add more details" so the fastest add
/// stays one screen of two fields.
struct AddConnectionView: View {
    @ObservedObject var vm: CircleViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var circles: [String] = []
    @State private var showCirclesPicker = false
    @State private var showOptional = false
    @State private var phone: String = ""
    @State private var city: String = ""
    @State private var stateValue: String = ""
    @State private var country: String = ""

    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SacredSpacing.l) {
                    nameSection
                    relationSection
                    optionalToggle
                    if showOptional {
                        optionalSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, SacredSpacing.m)
                    }
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, SacredSpacing.l)
            }
            .background(SacredBackground().ignoresSafeArea())
            .navigationTitle("Add to your circle")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.sacredMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { Task { await save() } }
                        .foregroundColor(canSave ? .sacredGold : .sacredMutedLight)
                        .disabled(!canSave || saving)
                }
            }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("NAME")
            SacredListCard {
                TextField("Their name", text: $name)
                    .font(.sacredText)
                    .foregroundColor(.sacredText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .submitLabel(.next)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    private var relationSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            sectionLabel("CIRCLES")
            SacredListCard {
                CircleChipsRow(
                    circles: circles,
                    onRemove: { name in
                        circles.removeAll {
                            $0.caseInsensitiveCompare(name) == .orderedSame
                        }
                    },
                    onAdd: { showCirclesPicker = true })
            }
            Text("Tag this person with one or more circles — Friend, Coworker, Family, anything you want. Optional, you can add later.")
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
                .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showCirclesPicker) {
            CirclesPickerSheet(
                catalog: vm.circleCatalog,
                alreadyAdded: Set(circles),
                onPick: { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty
                        && !circles.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        circles.append(trimmed)
                    }
                    showCirclesPicker = false
                },
                onCancel: { showCirclesPicker = false })
        }
    }

    private var optionalToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showOptional.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showOptional ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(showOptional ? "Hide more details" : "Add more details (optional)")
                    .font(.sacredSmall)
            }
            .foregroundColor(.sacredGold)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            SacredListCard {
                VStack(spacing: 0) {
                    optionalRow("Phone", text: $phone, keyboard: .phonePad)
                    Divider().padding(.leading, 16)
                    optionalRow("City", text: $city)
                    Divider().padding(.leading, 16)
                    optionalRow("State", text: $stateValue)
                    Divider().padding(.leading, 16)
                    optionalRow("Country", text: $country)
                }
            }
        }
    }

    private func optionalRow(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.sacredMicroBold)
                .foregroundColor(.sacredLabel)
                .frame(width: 80, alignment: .leading)
            TextField("Add", text: text)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .keyboardType(keyboard)
                .submitLabel(.done)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.sacredSectionLabel)
            .foregroundColor(.sacredLabel)
            .padding(.horizontal, 4)
    }

    private func save() async {
        guard canSave else { return }
        saving = true
        defer { saving = false }
        do {
            let req = CreateConnectionRequest(
                displayName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                circles: circles.isEmpty ? nil : circles,
                phoneNumber: phone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                country: country.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                state: stateValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                city: city.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            _ = try await vm.addLocal(req)
            dismiss()
        } catch {
            errorMessage = "Couldn't add. Try again."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
