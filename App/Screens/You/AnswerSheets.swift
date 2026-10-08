import PrefillKit
import SwiftUI

// The student starter set: one answer per question that has none yet, the school filled in.
// Blank answers are left out, and each saved one is an ordinary field to edit afterwards.
struct StudentAnswersSheet: View {
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
                            if await model.addStudentAnswers(answers) { onSaved() }
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

// Adds a field, or edits one when `original` is set. A draft (a cover letter, a paragraph on
// why this company) takes several lines and is only ever offered, never filled.
struct CustomFieldSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let original: CustomField?
    var isDraft = false

    private var draft: Bool { original?.isDraft ?? isDraft }

    @State private var label = ""
    @State private var value = ""
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(draft ? "Label, like Cover letter" : "Label, like School", text: $label)
                        .textInputAutocapitalization(.sentences)
                        .focused($isFocused)
                        .accessibilityLabel("Label")
                        .accessibilityIdentifier("custom-label")
                    if draft {
                        TextField("Your draft", text: $value, axis: .vertical)
                            .lineLimit(6...14)
                            .accessibilityLabel("Draft")
                            .accessibilityIdentifier("custom-value")
                    } else {
                        TextField("Answer, like UC Berkeley", text: $value)
                            .accessibilityLabel("Answer")
                            .accessibilityIdentifier("custom-value")
                    }
                } footer: {
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Palette.destructive)
                    } else if draft {
                        Text("""
                            Prefill offers a draft in its list under a matching field, for you to pick and edit. \
                            Fill form never uses it.
                            """)
                    }
                }
            }
            .navigationTitle(title)
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
                isFocused = true
            }
        }
        .presentationBackground(Palette.canvas)
    }

    private var title: LocalizedStringKey {
        switch (original == nil, draft) {
        case (true, true): "Add draft"
        case (true, false): "Add field"
        case (false, true): "Edit draft"
        case (false, false): "Edit field"
        }
    }

    // Match words are no longer edited, but a field saved with some keeps them.
    private func submit() async {
        let words = original?.alsoMatches ?? ""
        switch CustomField.make(label: label, value: value, alsoMatches: words, isDraft: draft) {
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
