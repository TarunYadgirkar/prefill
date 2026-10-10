import PrefillKit
import SwiftUI
import UniformTypeIdentifiers

// Every job application sent from Safari on this iPhone, newest first. A search covers the
// questions and answers too, so "graduation" finds what each form was told. Export shares a
// CSV, one row per question, that Google Sheets opens as is.
struct ApplicationsList: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private var shown: [SubmittedApplication] {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return model.applications }
        return model.applications.filter { $0.matches(words) }
    }

    var body: some View {
        List(shown) { application in
            NavigationLink {
                ApplicationDetail(application: application)
            } label: {
                ApplicationRow(application: application)
            }
            .accessibilityIdentifier("application-\(application.id)")
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Applications")
        .searchable(text: $query, prompt: Text("Search questions and answers"))
        .overlay { emptyState }
        .toolbar {
            if !model.applications.isEmpty {
                ShareLink(
                    item: ApplicationsCSV(text: ApplicationExport.csv(model.applications)),
                    preview: SharePreview(ApplicationsCSV.fileName)
                ) {
                    Label("Export for Google Sheets", systemImage: "square.and.arrow.up")
                }
            }
        }
        .background(Palette.canvas)
    }

    @ViewBuilder private var emptyState: some View {
        if model.applications.isEmpty {
            EmptyStateView(title: "No applications yet", systemImage: "doc.text", message: Text("""
                When you send a job application in Safari, Prefill keeps every answer and the name of the \
                resume you attached here.
                """))
        } else if shown.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }
}

struct ApplicationRow: View {
    let application: SubmittedApplication

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(application.title).textRole(.value).lineLimit(2)
            Text("\(application.site) · \(application.date.formatted(date: .abbreviated, time: .omitted))")
                .textRole(.valueCaption)
        }
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }
}

// One application: the files sent, then each question with its answer. Answers can be
// selected and copied, for reusing an essay.
struct ApplicationDetail: View {
    let application: SubmittedApplication

    var body: some View {
        List {
            Section {
                Text("\(application.site) · \(application.date.formatted(date: .long, time: .shortened))")
                    .textRole(.secondary)
            }
            if !application.files.isEmpty {
                Section {
                    ForEach(application.files, id: \.self) { file in
                        answer(question: file.question, text: file.name)
                    }
                } header: {
                    Text("Files").textRole(.groupHeader)
                }
            }
            Section {
                ForEach(Array(application.fields.enumerated()), id: \.offset) { _, field in
                    answer(question: field.question, text: field.answer)
                }
            } header: {
                Text("Answers").textRole(.groupHeader)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(application.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.canvas)
    }

    private func answer(question: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(question).textRole(.valueCaption)
            Text(text)
                .textRole(.value)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xxSmall)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
    }
}

struct ApplicationsCSV: Transferable {
    static let fileName = "Job Applications.csv"

    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { csv in Data(csv.text.utf8) }
            .suggestedFileName(fileName)
    }
}

extension SubmittedApplication {
    func matches(_ query: String) -> Bool {
        let texts = [title, host] + fields.flatMap { [$0.question, $0.answer] } + files.map(\.name)
        return texts.contains { $0.localizedStandardContains(query) }
    }
}
