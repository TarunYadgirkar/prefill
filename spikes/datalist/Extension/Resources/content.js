(() => {
    const params = new URLSearchParams(location.search);
    const cfg = {
        when: params.get("dl_when") ?? "load",
        ac: params.get("dl_ac") ?? "keep",
        rename: params.get("dl_rename") === "1",
        labels: params.get("dl_labels") === "1",
        mutate: params.get("dl_mutate") === "1",
        n: Number(params.get("dl_n") ?? "5"),
    };
    const WORDS = ["one", "two", "three", "four", "five", "six", "seven", "eight"];
    const LIST_ID = "prefill-dl";
    const SELECTOR = "input:not([type=hidden]):not([type=password]):not([type=submit])";

    const log = (event, extra = {}) => {
        const entry = { src: "cs", event, t: Date.now(), ...extra };
        const pane = document.getElementById("log");
        if (pane) pane.textContent = `[cs] ${event} ${JSON.stringify(extra)}\n` + pane.textContent;
        fetch("/log", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(entry) }).catch(() => {});
    };

    const fillOptions = (list, prefix, offset) => {
        list.replaceChildren(...WORDS.slice(offset, offset + cfg.n).map((w, i) => {
            const opt = document.createElement("option");
            opt.value = `${prefix}-${w}@example.net`;
            if (cfg.labels) opt.label = `Label ${offset + i + 1}`;
            return opt;
        }));
    };

    const ensureList = () => {
        let list = document.getElementById(LIST_ID);
        if (list) return list;
        list = document.createElement("datalist");
        list.id = LIST_ID;
        fillOptions(list, "dl", 0);
        document.body.appendChild(list);
        return list;
    };

    const attach = (input) => {
        ensureList();
        input.setAttribute("list", LIST_ID);
    };

    const applyAttributeVariants = (input, i) => {
        if (cfg.ac === "off") input.setAttribute("autocomplete", "off");
        if (cfg.ac === "nope") input.setAttribute("autocomplete", "prefill-nope");
        if (cfg.ac === "remove") input.removeAttribute("autocomplete");
        if (cfg.rename) {
            input.name = `pf_field_${i}`;
            input.id = `pf_field_${i}`;
        }
    };

    if (params.get("dl_hide") === "1") {
        const style = document.createElement("style");
        style.textContent = "input[list]::-webkit-calendar-picker-indicator, input[list]::-webkit-list-button { display: none !important; }";
        document.head.appendChild(style);
    }

    const inputs = [...document.querySelectorAll(SELECTOR)];
    inputs.forEach(applyAttributeVariants);
    if (cfg.when === "load") inputs.forEach(attach);

    document.addEventListener("focusin", (e) => {
        const target = e.composedPath()[0];
        if (!(target instanceof HTMLInputElement)) return;
        if (cfg.when === "focus") {
            attach(target);
            log("attached-on-focusin", { field: target.id });
        }
        if (cfg.mutate) {
            setTimeout(() => {
                fillOptions(ensureList(), "mut", 2);
                log("options-mutated", { values: [...ensureList().options].map((o) => o.value) });
            }, 4000);
        }
    }, true);

    document.documentElement.dataset.prefillCs = "active";
    log("content-script-ready", { cfg, frame: window === top ? "top" : "sub", fields: inputs.map((i) => `${i.id}|${i.name}|${i.getAttribute("autocomplete")}|list=${i.getAttribute("list")}`) });
})();
