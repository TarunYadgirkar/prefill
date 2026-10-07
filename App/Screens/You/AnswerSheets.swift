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
