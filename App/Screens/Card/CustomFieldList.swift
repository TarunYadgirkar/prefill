import PrefillKit
import SwiftUI

// Answers of the person's own that no contact field holds, like a school or a major. Prefill
// offers each one in Safari's bar on a form field whose label names it. Tapping a row edits
// it; Edit shows the drag handles.
struct CustomFieldList: View {
    @Environment(AppModel.self) private var model
    @State private var editing: CustomField?
    @State private var removing: CustomField?
    @State private var isAdding = false
    @State private var isAddingStudentAnswers = false
    @AppStorage("studentStarterDone") private var isStarterDone = false

    private var offersStarter: Bool {
        !isStarterDone && !StudentStarter.missing(from: fields).isEmpty
    }

    private var fields: [CustomField] { model.customFields }

    var body: some View {
        List {
            Section {
                ForEach(fields) { field in
                    Button {
                        editing = field
                    } label: {
                        CustomFieldRow(field: field)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Edits this field"))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            removing = field
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    Task { await model.moveCustomFields(from: source, to: destination) }
                }
            } footer: {
                if !fields.isEmpty {
                    Text("Prefill offers a field in Safari when a form asks for its label or one of its other words.")
                }
            }
            Section {
                Button {
                    isAdding = true
                } label: {
                    Label("Add field", systemImage: "plus.circle.fill")
                        .textRole(.action)
                }
                .padding(.vertical, Spacing.xxSmall)
                .accessibilityIdentifier("add-custom-field")
                if offersStarter {
                    Button {
                        isAddingStudentAnswers = true
                    } label: {
                        Label("Add student answers", systemImage: "graduationcap.fill")
                            .textRole(.action)
                    }
                    .padding(.vertical, Spacing.xxSmall)
                    .accessibilityIdentifier("add-student-answers")
                }
            } footer: {
                if offersStarter {
                    Text("School, degree, major, GPA and graduation date, the questions job applications ask students.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if fields.isEmpty {
                EmptyStateView(title: "No custom fields yet", systemImage: "text.badge.plus", message: Text("""
                    Save answers forms ask for that aren’t on your card, like your school or major. \
                    Prefill offers them in Safari when a field’s label matches.
                    """)) {
                    PrefillButton(title: "Add field", systemImage: "plus") { isAdding = true }
                        .fixedSize()
                    if offersStarter {
                        PrefillButton(title: "Add student answers", systemImage: "graduationcap", kind: .secondary) {
                            isAddingStudentAnswers = true
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .sheet(item: $editing) { field in
            CustomFieldSheet(original: field)
        }
        .sheet(isPresented: $isAdding) {
            CustomFieldSheet(original: nil)
        }
        .sheet(isPresented: $isAddingStudentAnswers) {
            StudentAnswersSheet(missing: StudentStarter.missing(from: fields)) { isStarterDone = true }
        }
        .confirmationDialog(
            "Remove this field from your card?", isPresented: isRemoving, titleVisibility: .visible,
            presenting: removing
        ) { field in
            Button("Remove field", role: .destructive) {
                Task { await model.removeCustomField(field) }
            }
        } message: { _ in
            Text("Prefill stops offering it, on this iPhone and on your other devices that share this card.")
        }
    }

    private var isRemoving: Binding<Bool> {
        Binding { removing != nil } set: { if !$0 { removing = nil } }
    }
}

private struct CustomFieldRow: View {
    let field: CustomField

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(field.label)
                .textRole(.valueCaption)
            Text(field.value)
                .textRole(.value)
                .fixedSize(horizontal: false, vertical: true)
            if !field.matchWords.isEmpty {
                Text("Also matches \(field.alsoMatches)")
                    .textRole(.footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xxSmall)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("custom-\(field.label)")
    }
}

// The student starter set: one answer per question that has none yet, the school filled in.
// Blank answers are left out, and each saved one is an ordinary field to edit afterwards.
private struct StudentAnswersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let missing: [JobQuestion]
    let onSaved: () -> Void

    @State private var answers = StudentStarter.answers

    private var filled: Int {
        StudentStarter.fields(for: answers, adding: model.customFields).count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(missing, id: \.self) { question in
                        LabeledContent(question.label) {
                            TextField(StudentStarter.example(question), text: answer(question))
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("student-\(question.rawValue)")
                        }
                    }
                } footer: {
                    Text("Change anything that isn’t right and leave blank what you’d rather type each time.")
                }
            }
            .navigationTitle("Student answers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(filled)") {
                        Task {
                            await model.addStudentAnswers(answers)
                            onSaved()
                            dismiss()
                        }
                    }
                    .disabled(filled == 0)
                    .accessibilityIdentifier("save-student-answers")
                }
            }
        }
        .presentationBackground(Palette.canvas)
    }

    private func answer(_ question: JobQuestion) -> Binding<String> {
        Binding { answers[question] ?? "" } set: { answers[question] = $0 }
    }
}

// Adds a field, or edits one when `original` is set.
struct CustomFieldSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let original: CustomField?

    @State private var label = ""
    @State private var value = ""
    @State private var alsoMatches = ""
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label, like School", text: $label)
                        .textInputAutocapitalization(.sentences)
                        .focused($isFocused)
                        .accessibilityLabel("Label")
                        .accessibilityIdentifier("custom-label")
                    TextField("Answer, like UC Berkeley", text: $value)
                        .accessibilityLabel("Answer")
                        .accessibilityIdentifier("custom-value")
                } footer: {
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.destructive)
                    }
                }
                Section {
                    TextField("university, college", text: $alsoMatches)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Also matches")
                } header: {
                    Text("Also matches")
                } footer: {
                    Text("Other words a form might use for this field, separated by commas. Optional.")
                }
            }
            .navigationTitle(original == nil ? "Add field" : "Edit field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(original == nil ? "Add" : "Save") { Task { await submit() } }
                        .accessibilityIdentifier("save-custom-field")
                }
            }
            .onAppear {
                label = original?.label ?? ""
                value = original?.value ?? ""
                alsoMatches = original?.alsoMatches ?? ""
                isFocused = true
            }
        }
        .presentationBackground(Palette.canvas)
    }

    private func submit() async {
        switch CustomField.make(label: label, value: value, alsoMatches: alsoMatches) {
        case .failure(let problem):
            report(problem.message)
        case .success(let field):
            if let problem = await model.saveCustomField(field, replacing: original) {
                report(problem)
            } else {
                dismiss()
            }
        }
    }

    private func report(_ message: String) {
        error = message
        AccessibilityNotification.Announcement(message).post()
    }
}

#Preview {
    CustomFieldList()
        .previewModel()
}
