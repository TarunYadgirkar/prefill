// A Greenhouse-style application built with the real React-Select, the searchable dropdown
// Greenhouse's job boards use for every question with choices. Its ids follow Greenhouse:
// the input's id is the question's, so React-Select names its parts react-select-<id>-*.
// Bundled by web/src/e2e/fillChrome.ts with esbuild.
import { createElement as h, useState } from "react";
import { createRoot } from "react-dom/client";
import Select from "react-select";

const QUESTIONS = [
  { id: "question_1", label: "Are you legally authorized to work in the United States?", options: ["Yes", "No"] },
  { id: "question_2", label: "Will you now or in the future require sponsorship?", options: ["Yes", "No"] },
  { id: "school--0", label: "School", options: ["Stanford University", "University of California, Berkeley", "University of California, Los Angeles", "University of Washington"] },
  { id: "gender", label: "Gender", options: ["Male", "Female", "Decline To Self Identify"] },
  { id: "veteran_status", label: "Veteran Status", options: ["I am not a protected veteran", "I identify as one or more of the classifications of protected veteran", "I don't wish to answer"] },
];

function Question({ id, label, options }) {
  const [value, setValue] = useState(null);
  return h("div", { className: "field" },
    h("label", { id: `${id}-label`, htmlFor: id }, label),
    h(Select, {
      inputId: id,
      instanceId: id,
      "aria-labelledby": `${id}-label`,
      value,
      onChange: setValue,
      options: options.map((text) => ({ value: text, label: text })),
    }),
    h("output", { "data-answer": id }, value?.label ?? ""));
}

function App() {
  return h("form", { id: "application_form" },
    h("div", { className: "field" }, h("label", { htmlFor: "first_name" }, "First Name *"), h("input", { id: "first_name", type: "text" })),
    h("div", { className: "field" }, h("label", { htmlFor: "email" }, "Email *"), h("input", { id: "email", type: "text" })),
    ...QUESTIONS.map((question) => h(Question, { key: question.id, ...question })),
    h("button", { type: "submit" }, "Submit application"));
}

createRoot(document.getElementById("root")).render(h(App));
